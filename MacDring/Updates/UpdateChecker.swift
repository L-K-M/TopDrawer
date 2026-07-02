import AppKit

/// Drop-in "is there a newer release on GitHub?" checker.
///
/// Configure it with a repository and call `start()` once at launch: it checks on
/// startup and then daily — throttled by a stored last-check date so relaunches don't
/// spam — and shows an AppKit alert offering **Download**, **Remind Me Later**, or
/// **Skip This Version** when a newer release exists. `checkNow()` is the
/// user-initiated path (ignores the throttle and also reports "you're up to date" and
/// errors).
///
/// Self-contained and reusable across apps: it owns its small state (enabled flag,
/// skipped version, last-check date) in `UserDefaults` under namespaced keys, so reuse
/// in another app is just `UpdateChecker(configuration: .init(owner:, repo:))`, a
/// `start()` call, a toggle bound to `automaticChecksEnabled`, and a menu item calling
/// `checkNow()`. Depends only on AppKit + Foundation.
final class UpdateChecker: ObservableObject {

    struct Configuration {
        var owner: String
        var repo: String
        var appName: String
        var currentVersion: String
        var allowPrereleases: Bool
        /// When true (default), the alert's **Download** action saves the release's
        /// disk image/zip to `~/Downloads` and reveals it in Finder; when false it just
        /// opens the release page in the browser.
        var autoDownloadAssets: Bool
        var minimumCheckInterval: TimeInterval
        /// Namespacing prefix for this checker's `UserDefaults` keys.
        var defaultsKeyPrefix: String

        init(owner: String,
             repo: String,
             appName: String = Bundle.main.appDisplayName,
             currentVersion: String = Bundle.main.shortVersionString,
             allowPrereleases: Bool = false,
             autoDownloadAssets: Bool = true,
             minimumCheckInterval: TimeInterval = 24 * 60 * 60,
             defaultsKeyPrefix: String? = nil) {
            self.owner = owner
            self.repo = repo
            self.appName = appName
            self.currentVersion = currentVersion
            self.allowPrereleases = allowPrereleases
            self.autoDownloadAssets = autoDownloadAssets
            self.minimumCheckInterval = minimumCheckInterval
            self.defaultsKeyPrefix = defaultsKeyPrefix ?? "UpdateChecker.\(owner).\(repo)"
        }
    }

    let configuration: Configuration
    private let client: GitHubReleaseClient
    private let downloader = UpdateDownloader()
    private let defaults: UserDefaults
    private var timer: Timer?

    /// Whether to check automatically (on launch and daily). User-facing toggle.
    @Published var automaticChecksEnabled: Bool {
        didSet {
            defaults.set(automaticChecksEnabled, forKey: key("enabled"))
            if automaticChecksEnabled, !oldValue { checkInBackground() }
        }
    }

    /// When the last successful check completed (for a Settings "last checked" line).
    @Published private(set) var lastCheckDate: Date?

    /// True while a check is in flight (to disable a "Check Now" button, say).
    @Published private(set) var isChecking = false

    /// True while an update asset is downloading to `~/Downloads`.
    @Published private(set) var isDownloading = false

    init(configuration: Configuration, defaults: UserDefaults = .standard) {
        self.configuration = configuration
        self.defaults = defaults
        self.client = GitHubReleaseClient(owner: configuration.owner, repo: configuration.repo)
        let prefix = configuration.defaultsKeyPrefix
        // Default ON unless the user has explicitly turned it off.
        self.automaticChecksEnabled = defaults.object(forKey: "\(prefix).enabled") as? Bool ?? true
        self.lastCheckDate = defaults.object(forKey: "\(prefix).lastCheck") as? Date
    }

    deinit { timer?.invalidate() }

    // MARK: Public API

    /// Begins automatic checking: an immediate (throttled) check plus a daily timer.
    /// Call once at launch. No-op under XCTest.
    func start() {
        guard !Self.isRunningTests else { return }
        checkInBackground()
        let interval = configuration.minimumCheckInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkInBackground()
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Runs a check only if automatic checks are on and the throttle interval has
    /// elapsed. Silent unless a newer, non-skipped version is found.
    func checkInBackground() {
        guard automaticChecksEnabled else { return }
        // Throttle against 90% of the interval, not the full interval:
        // `lastCheckDate` is stamped when the previous request *completed*, a
        // beat after the timer's reference point — so a punctual daily timer
        // would otherwise find `elapsed` just short of a full day, skip, and
        // defer the check to the day after.
        if let last = lastCheckDate,
           Date().timeIntervalSince(last) < configuration.minimumCheckInterval * 0.9 { return }
        performCheck(userInitiated: false)
    }

    /// User-initiated check (menu / Settings): ignores the throttle and always reports
    /// the outcome, including "you're up to date" and errors.
    func checkNow() {
        performCheck(userInitiated: true)
    }

    // MARK: Check

    private var skippedVersion: String? {
        get { defaults.string(forKey: key("skippedVersion")) }
        set { defaults.set(newValue, forKey: key("skippedVersion")) }
    }

    private func performCheck(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isChecking = false }
            do {
                let release = try await self.client.latestRelease(includePrereleases: self.configuration.allowPrereleases)
                self.lastCheckDate = Date()
                self.defaults.set(self.lastCheckDate, forKey: self.key("lastCheck"))

                guard let remote = SemanticVersion(release.tagName),
                      let current = SemanticVersion(self.configuration.currentVersion) else {
                    // "You're up to date" would be a guess: nothing was compared.
                    if userInitiated { self.presentVersionsNotComparable(release: release) }
                    return
                }
                if remote > current {
                    if userInitiated || self.skippedVersion != release.tagName {
                        self.presentUpdateAvailable(release: release, remote: remote, current: current)
                    }
                } else if userInitiated {
                    self.presentUpToDate()
                }
            } catch {
                if userInitiated { self.presentError(error) }
                else { NSLog("UpdateChecker: background check failed: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: Presentation

    @MainActor
    private func presentUpdateAvailable(release: GitHubRelease, remote: SemanticVersion, current: SemanticVersion) {
        let alert = NSAlert()
        alert.messageText = "A new version of \(configuration.appName) is available"
        var info = "\(configuration.appName) \(remote) is available — you have \(current)."
        if let notes = release.releaseNotes() { info += "\n\n\(notes)" }
        alert.informativeText = info
        alert.addButton(withTitle: "Download")           // .alertFirstButtonReturn
        alert.addButton(withTitle: "Remind Me Later")    // .alertSecondButtonReturn
        alert.addButton(withTitle: "Skip This Version")  // .alertThirdButtonReturn

        switch runModal(alert) {
        case .alertFirstButtonReturn:
            if configuration.autoDownloadAssets {
                downloadAndReveal(release)
            } else {
                NSWorkspace.shared.open(release.htmlURL)
            }
        case .alertThirdButtonReturn:
            skippedVersion = release.tagName
        default:
            break   // Remind Me Later — re-offered on the next check.
        }
    }

    /// Downloads the release's preferred asset to `~/Downloads` and reveals it in
    /// Finder. Falls back to opening the release page if there's no downloadable asset
    /// or the download fails.
    @MainActor
    private func downloadAndReveal(_ release: GitHubRelease) {
        guard let asset = release.preferredAsset else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }
        guard !isDownloading else { return }
        isDownloading = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isDownloading = false }
            do {
                let fileURL = try await self.downloader.downloadToDownloads(asset)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } catch {
                NSLog("UpdateChecker: download failed (\(error.localizedDescription)); opening release page")
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    /// Shown when the release tag or the app's own version string couldn't be
    /// parsed for comparison — an honest "couldn't tell" instead of the misleading
    /// "you're up to date", with the release page as the manual way out.
    @MainActor
    private func presentVersionsNotComparable(release: GitHubRelease) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't compare versions"
        alert.informativeText = "The latest release is tagged “\(release.tagName)”, which couldn't be compared with this build (\(configuration.currentVersion)). You can check the releases page yourself."
        alert.addButton(withTitle: "Open Releases Page")
        alert.addButton(withTitle: "Cancel")
        if runModal(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    @MainActor
    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "\(configuration.appName) \(configuration.currentVersion) is the latest version."
        alert.addButton(withTitle: "OK")
        _ = runModal(alert)
    }

    @MainActor
    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        _ = runModal(alert)
    }

    /// Brings the alert forward before running it modally — a menu-bar agent isn't the
    /// active app, so without this the alert can appear behind other windows with no
    /// Dock icon to click.
    @MainActor
    private func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        alert.window.level = .floating
        return alert.runModal()
    }

    // MARK: Helpers

    private func key(_ suffix: String) -> String { "\(configuration.defaultsKeyPrefix).\(suffix)" }

    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

extension Bundle {
    /// `CFBundleShortVersionString` (the marketing version), or `"0"`.
    var shortVersionString: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// The app's display name, falling back to the bundle name then the process name.
    var appDisplayName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ProcessInfo.processInfo.processName
    }
}

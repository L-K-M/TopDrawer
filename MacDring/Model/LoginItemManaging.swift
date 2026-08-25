import Foundation

/// The launch-at-login seam (LP-13): read whether the app is a system login item and
/// enable/disable it. macOS backs this with ServiceManagement's `SMAppService`
/// (`SystemLoginItem`); a platform with no system login item (Linux, for now) reads
/// nothing and applies nothing, so `Preferences.launchAtLogin` stays a stored preference
/// there until a Linux autostart backend is wired up. See PLAN.md §LP-13.
protocol LoginItemManaging {
    /// The authoritative system login-item state, or `nil` if unavailable/unsupported.
    func isEnabled() -> Bool?

    /// Registers (`true`) or unregisters (`false`) the app as a login item. Returns `nil`
    /// on success, or a human-readable message on failure. A platform without a
    /// login-item mechanism returns `nil` and makes no system change.
    func setEnabled(_ enabled: Bool) -> String?
}

#if canImport(ServiceManagement)
import ServiceManagement

/// macOS login item backed by `SMAppService.mainApp` (macOS 13+). Registration needs no
/// helper bundle and no admin rights.
struct SystemLoginItem: LoginItemManaging {
    func isEnabled() -> Bool? {
        guard #available(macOS 13.0, *) else { return nil }
        switch SMAppService.mainApp.status {
        case .enabled: return true
        case .notRegistered, .notFound: return false
        default: return nil
        }
    }

    func setEnabled(_ enabled: Bool) -> String? {
        // Unreachable at the macOS 13 deployment target, but honest defensively: macOS
        // < 13 does have login items, so surface an error rather than silently "succeed".
        guard #available(macOS 13.0, *) else { return "Launch at login requires macOS 13 or later." }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
#else

/// The no-op login item for platforms without a system login-item mechanism (Linux):
/// nothing to read, nothing to apply — the caller keeps `launchAtLogin` as a stored
/// preference so it round-trips like any other setting.
struct SystemLoginItem: LoginItemManaging {
    func isEnabled() -> Bool? { nil }
    func setEnabled(_ enabled: Bool) -> String? { nil }
}
#endif

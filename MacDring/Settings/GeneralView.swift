import SwiftUI

/// General behavior: launch at login, the global drawer-interaction defaults (which
/// every tab follows unless it overrides them in the Tabs pane), new-tab defaults,
/// and the multi-display policy.
struct GeneralView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        Form {
            Section {
                Toggle("Launch Top Drawer at login", isOn: $preferences.launchAtLogin)
                if let error = preferences.launchAtLoginError {
                    Text("Couldn't update login item: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Software updates") {
                Toggle("Automatically check for updates", isOn: $updateChecker.automaticChecksEnabled)
                HStack {
                    Button("Check Now") { updateChecker.checkNow() }
                        .disabled(updateChecker.isChecking || updateChecker.isDownloading)
                    if updateChecker.isChecking || updateChecker.isDownloading {
                        ProgressView().controlSize(.small)
                    }
                    if updateChecker.isDownloading {
                        Text("Downloading…").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let date = updateChecker.lastCheckDate {
                        Text("Last checked \(date.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Checks GitHub for new releases on launch and once a day. When an update is found you can download it straight to your Downloads folder (it's revealed in Finder), skip that version, or be reminded later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Drawers") {
                Toggle("Open items with a single click", isOn: $preferences.launchOnSingleClick)
                Toggle("Open on hover instead of click", isOn: $preferences.newTabOpenOnHover)
                Toggle("Close drawer when you click elsewhere", isOn: $preferences.newTabAutoHide)
                VStack(alignment: .leading) {
                    Text("Open / close animation: \(Int(preferences.animationMs)) ms")
                    Slider(value: $preferences.animationMs, in: 0...300, step: 10)
                }
                Text("Hover and close are the default for every tab. A tab set to a specific value in the Tabs pane keeps it regardless of this — change it back to “Use global default” there to follow this again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("New tab defaults") {
                Picker("When idle", selection: $preferences.newTabConcealment) {
                    ForEach(TabConcealment.allCases) { Text($0.displayName).tag($0) }
                }
                // Ranges match Preferences' clamps (1…12 / 1…16), so a stored
                // value at the top of the valid range isn't out of the stepper's.
                Stepper("Grid columns: \(Int(preferences.gridColumns))", value: $preferences.gridColumns, in: 1...12)
                Stepper("Grid rows: \(Int(preferences.gridRows))", value: $preferences.gridRows, in: 1...16)
                Text("Apply to newly created tabs. Existing tabs keep their own (edit them in the Tabs pane).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Idle tabs") {
                Toggle("Reveal all hidden tabs together", isOn: $preferences.revealAllConcealedTogether)
                Text("When you move the pointer to a screen edge to reveal one auto-hidden or auto-faded tab, every hidden tab reveals at once — and they hide again together when the pointer leaves.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Fresh tabs") {
                Toggle("Also check Downloads, Desktop & Documents directly", isOn: $preferences.freshDirectScan)
                    .onChange(of: preferences.freshDirectScan) { enabled in
                        // Fire the folder-access prompts now, in response to the very
                        // click that opted in — not at the next badge beat or drawer
                        // open, long after the user has moved on.
                        if enabled { FreshScanner.promptForAccess() }
                    }
                Text("Fresh tabs normally list new arrivals from the Spotlight index only, which needs no permission at all — but finds nothing on Macs where Spotlight is off, still indexing, or set to skip those folders. This adds Top Drawer's own check of the three folders on top, so Fresh tabs work regardless. Turning it on makes macOS ask once per folder for access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Multiple displays") {
                Picker("When a tab's display is disconnected", selection: $preferences.disconnectPolicy) {
                    ForEach(DisconnectPolicy.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Float tabs", selection: $preferences.tabWindowLevel) {
                    ForEach(TabWindowLevel.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Tabs are anchored by a stable display identity and a fractional edge position, so they return to the same spot after a restart, resolution change, or reconnection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { preferences.refreshLaunchAtLoginStatus() }
    }
}

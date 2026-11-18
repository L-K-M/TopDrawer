import SwiftUI
import KeycapKit

/// A small control that records a global hotkey: click it, then press a key
/// combination — ⌘/⌃/⌥ plus a key, or a bare function key (F1–F20). The
/// recording behaviour comes from Keycap's `ShortcutRecorder`: Esc cancels,
/// bare ⌫/⌦ clears, and a combo that is not a usable global hotkey (shift-only,
/// or one the system reserves such as ⌘Q) beeps and keeps recording. Used in
/// the Tabs pane to set a tab's optional toggle shortcut.
///
/// A shortcut saved by an older Top Drawer may be one the current rule refuses;
/// it is not registered, so the view says so instead of showing a shortcut
/// that silently does nothing.
struct HotkeyRecorderView: View {
    @Binding var hotkey: HotkeySpec?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            recorder
            if let combo = hotkey?.combo, !combo.isUsableGlobalHotkey {
                Text("\(combo.displayString(keyName: KeyNames.displayName(for: combo.keyCode))) can't be used as a global shortcut, so Top Drawer doesn't register it. Record a new one.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recorder: some View {
        HStack(spacing: 8) {
            ShortcutRecorder(
                combo: Binding(
                    get: { hotkey?.combo },
                    set: { hotkey = $0.map { HotkeySpec(combo: $0) } }
                ),
                deleteAction: .clear,
                placeholder: "Record Shortcut",
                recordingPrompt: "Press shortcut… (Esc to cancel)"
            )
            .frame(minWidth: 130)
            if hotkey != nil {
                Button("Clear") { hotkey = nil }
            }
        }
    }
}

import SwiftUI
import AppKit

/// A small control that records a global hotkey: click it, then press a key
/// combination — ⌘/⌃/⌥ plus a key, or a bare function key (F1–F20). Shift-only
/// combos are rejected (they'd swallow ordinary typing). Used in the Tabs pane to
/// set a tab's optional toggle shortcut.
struct HotkeyRecorderView: View {
    @Binding var hotkey: HotkeySpec?

    @State private var recording = false
    @State private var monitor: Any?
    /// Why the last rejected keystroke wasn't accepted — shown inline so a silent
    /// rejection doesn't read as a broken control.
    @State private var rejectionHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: toggle) {
                    Text(label)
                        .frame(minWidth: 130)
                }
                if hotkey != nil && !recording {
                    Button("Clear") { hotkey = nil }
                }
            }
            if let rejectionHint {
                Text(rejectionHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stop)
        // A local key monitor only sees events delivered to this app. If the user
        // Cmd-Tabs away mid-recording, no further key event ever arrives and the
        // control would sit there looking stuck; resigning active is the exit.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if recording { stop() }
        }
    }

    private var label: String {
        if recording { return "Press shortcut… (Esc to cancel)" }
        if let hotkey { return KeyCodes.displayString(for: hotkey) }
        return "Record Shortcut"
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        guard monitor == nil else { return }   // never stack two key monitors
        recording = true
        rejectionHint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {            // Escape cancels
                stop()
                return nil
            }
            let modifiers = KeyCodes.carbonModifiers(from: event.modifierFlags)
            // ⌘/⌃/⌥ combos and bare function keys are accepted; Shift-only combos
            // are not — they'd swallow ordinary typing system-wide (⇧A vs "A").
            if KeyCodes.isUsableHotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers) {
                hotkey = HotkeySpec(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
                stop()
            } else {
                rejectionHint = KeyCodes.rejectionHint
            }
            return nil                          // consume keys while recording
        }
    }

    private func stop() {
        recording = false
        rejectionHint = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

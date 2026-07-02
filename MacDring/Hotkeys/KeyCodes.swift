import AppKit
import Carbon.HIToolbox

/// Conversions between Cocoa key events and the Carbon key code + modifier mask
/// that `RegisterEventHotKey` wants, plus a symbolic display string for the UI.
enum KeyCodes {

    /// Converts Cocoa modifier flags into a Carbon modifier mask.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    /// A symbolic representation of a hotkey, e.g. `⌃⌥⇧⌘M`.
    static func displayString(for hotkey: HotkeySpec) -> String {
        var result = ""
        let m = hotkey.carbonModifiers
        if m & UInt32(controlKey) != 0 { result += "⌃" }
        if m & UInt32(optionKey) != 0 { result += "⌥" }
        if m & UInt32(shiftKey) != 0 { result += "⇧" }
        if m & UInt32(cmdKey) != 0 { result += "⌘" }
        result += keyName(for: hotkey.keyCode)
        return result
    }

    /// Whether a modifier mask includes a *commanding* modifier — ⌘, ⌃, or ⌥.
    /// Shift alone doesn't count: a ⇧-only "hotkey" (e.g. ⇧A) collides with typing
    /// a capital letter and would swallow it system-wide.
    static func hasCommandingModifier(_ carbonModifiers: UInt32) -> Bool {
        carbonModifiers & (UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)) != 0
    }

    /// Whether `keyCode` is a function key (F1–F20). Function keys don't collide
    /// with typing, so they make fine global hotkeys even without a modifier —
    /// the classic launcher convention (F12 toggles a dock).
    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        functionKeys.contains(keyCode)
    }

    /// Whether a key + modifier combination is usable as a global hotkey: it needs
    /// a commanding modifier (⌘/⌃/⌥ — Shift alone would swallow ordinary typing),
    /// unless the key is a function key, which is safe bare.
    static func isUsableHotkey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        hasCommandingModifier(modifiers) || isFunctionKey(keyCode)
    }

    private static let functionKeys: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4), UInt32(kVK_F5),
        UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8), UInt32(kVK_F9), UInt32(kVK_F10),
        UInt32(kVK_F11), UInt32(kVK_F12), UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15),
        UInt32(kVK_F16), UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20),
    ]

    /// A readable name for a virtual key code (common keys; falls back to a hex label).
    static func keyName(for keyCode: UInt32) -> String {
        if let name = names[keyCode] { return name }
        return String(format: "key 0x%02X", keyCode)
    }

    private static let names: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Escape): "⎋", UInt32(kVK_Delete): "⌫",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
    ]
}

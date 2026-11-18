import Foundation
import KeycapCore

/// A global hotkey stored as a raw virtual key code plus a Carbon modifier mask,
/// so it can be registered with `RegisterEventHotKey` — which needs **no**
/// Accessibility permission (see PLAN.md §10).
///
/// This is Top Drawer's persisted shape only: the combo model and usability
/// rules live in Keycap, and the stored JSON stays
/// `{"keyCode":N,"carbonModifiers":N}`.
struct HotkeySpec: Codable, Equatable {
    /// Virtual key code (e.g. `kVK_ANSI_M`).
    var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey | optionKey | …`).
    var carbonModifiers: UInt32

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// The Keycap model this persisted value converts to.
    var combo: KeyCombo {
        KeyCombo(keyCode: keyCode,
                 modifiers: HotkeyModifiers(carbonFlags: carbonModifiers))
    }

    init(combo: KeyCombo) {
        self.init(keyCode: combo.keyCode, carbonModifiers: combo.carbonModifiers)
    }
}

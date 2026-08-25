/// The global-hotkey seam (LP-13): register and unregister a system-wide hotkey by
/// `HotkeySpec`. macOS backs this with Carbon's `RegisterEventHotKey`
/// (`CarbonHotkeyRegistrar`, wrapping `CarbonHotkey`); a platform without a global-hotkey
/// backend yet (Linux — a compositor/portal binding is a later LP) has no conformer here,
/// so nothing on Linux registers a hotkey until that backend lands. The registrar owns the
/// underlying platform object and hands the caller an opaque `HotkeyToken` to release it
/// with. See PLAN.md §LP-13 / §10.
protocol GlobalHotkeyRegistering {
    /// Attempts to register `spec` as a global hotkey that invokes `onPressed` on the
    /// main thread. Returns an opaque token on success (pass it to `unregister`), or `nil`
    /// if the platform refused the registration — a system-reserved combination, one
    /// another app already owns, or (on a platform with no hotkey backend) always.
    func register(_ spec: HotkeySpec, onPressed: @escaping () -> Void) -> HotkeyToken?

    /// Releases a token previously returned by `register`. An unknown token is a no-op.
    func unregister(_ token: HotkeyToken)
}

/// An opaque handle to one live global-hotkey registration. The caller stores it and
/// passes it back to `unregister`; only the registrar that issued it interprets the
/// underlying value.
struct HotkeyToken {
    fileprivate let id: UInt32
}

#if canImport(Carbon)

/// macOS global-hotkey registrar backed by Carbon (`CarbonHotkey`). It owns the live
/// `CarbonHotkey` instances — keyed by the monotonic id it stamps into each
/// `HotkeyToken` — and installs no Accessibility permission, matching Top Drawer's
/// existing per-tab trigger mechanism.
final class CarbonHotkeyRegistrar: GlobalHotkeyRegistering {

    private var registrations: [UInt32: CarbonHotkey] = [:]
    private var counter: UInt32 = 1

    func register(_ spec: HotkeySpec, onPressed: @escaping () -> Void) -> HotkeyToken? {
        let id = counter
        counter += 1
        let hotkey = CarbonHotkey(identifier: id)
        hotkey.onPressed = onPressed
        guard hotkey.register(keyCode: spec.keyCode, modifiers: spec.carbonModifiers) else {
            return nil
        }
        registrations[id] = hotkey
        return HotkeyToken(id: id)
    }

    func unregister(_ token: HotkeyToken) {
        registrations[token.id]?.unregister()
        registrations[token.id] = nil
    }
}
#endif

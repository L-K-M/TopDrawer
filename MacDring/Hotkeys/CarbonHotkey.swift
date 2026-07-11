import AppKit
import Carbon.HIToolbox

/// A global hotkey registered via Carbon's `RegisterEventHotKey`. Carbon hotkeys
/// need **no** Accessibility permission, which is why Top Drawer uses them for
/// optional per-tab triggers (see PLAN.md §10).
final class CarbonHotkey {

    /// Invoked on the main thread when the hotkey fires.
    var onPressed: (() -> Void)?

    private let identifier: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Four-char signature `'MDRH'`.
    private static let signature: OSType = 0x4D44_5248

    init(identifier: UInt32) {
        self.identifier = identifier
    }

    deinit { unregister() }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Each instance installs its own handler on the application target, and
        // Carbon stops the handler chain at the first one that returns `noErr` —
        // so this handler must claim **only its own** hotkey ID and pass every
        // other event along with `eventNotHandledErr`, or the most recently
        // registered hotkey would swallow all the others' presses.
        let handlerCallback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<CarbonHotkey>.fromOpaque(userData).takeUnretainedValue()

            var pressedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressedID
            )
            guard status == noErr,
                  pressedID.signature == CarbonHotkey.signature,
                  pressedID.id == me.identifier else {
                return OSStatus(eventNotHandledErr)
            }

            DispatchQueue.main.async { me.onPressed?() }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            unregister()
            NSLog("Top Drawer: failed to register Carbon hotkey \(identifier): status \(registerStatus)")
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

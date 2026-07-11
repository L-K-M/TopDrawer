import XCTest
import Carbon.HIToolbox
@testable import MacDring

final class KeyCodesTests: XCTestCase {

    private let cmd = UInt32(cmdKey)
    private let opt = UInt32(optionKey)
    private let ctrl = UInt32(controlKey)
    private let shift = UInt32(shiftKey)

    // MARK: Commanding modifiers

    func testCommandOptionControlAreCommanding() {
        XCTAssertTrue(KeyCodes.hasCommandingModifier(cmd))
        XCTAssertTrue(KeyCodes.hasCommandingModifier(opt))
        XCTAssertTrue(KeyCodes.hasCommandingModifier(ctrl))
        XCTAssertTrue(KeyCodes.hasCommandingModifier(cmd | shift))
    }

    func testShiftAloneIsNotCommanding() {
        XCTAssertFalse(KeyCodes.hasCommandingModifier(shift))
        XCTAssertFalse(KeyCodes.hasCommandingModifier(0))
    }

    // MARK: Usable hotkeys

    func testShiftOnlyLetterIsNotAUsableHotkey() {
        // ⇧A would swallow every typed capital "A" system-wide.
        XCTAssertFalse(KeyCodes.isUsableHotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: shift))
    }

    func testBareLetterIsNotAUsableHotkey() {
        XCTAssertFalse(KeyCodes.isUsableHotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: 0))
    }

    func testCommandLetterIsUsable() {
        XCTAssertTrue(KeyCodes.isUsableHotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: cmd | shift))
    }

    func testBareFunctionKeysAreUsable() {
        XCTAssertTrue(KeyCodes.isUsableHotkey(keyCode: UInt32(kVK_F1), modifiers: 0))
        XCTAssertTrue(KeyCodes.isUsableHotkey(keyCode: UInt32(kVK_F12), modifiers: 0))
        XCTAssertTrue(KeyCodes.isUsableHotkey(keyCode: UInt32(kVK_F20), modifiers: 0))
    }

    func testShiftedFunctionKeyIsUsable() {
        XCTAssertTrue(KeyCodes.isUsableHotkey(keyCode: UInt32(kVK_F5), modifiers: shift))
    }

    // MARK: Display names

    func testExtendedFunctionKeysHaveNames() {
        XCTAssertEqual(KeyCodes.keyName(for: UInt32(kVK_F13)), "F13")
        XCTAssertEqual(KeyCodes.keyName(for: UInt32(kVK_F20)), "F20")
    }

    func testDisplayStringForBareFunctionKey() {
        let spec = HotkeySpec(keyCode: UInt32(kVK_F12), carbonModifiers: 0)
        XCTAssertEqual(KeyCodes.displayString(for: spec), "F12")
    }
}

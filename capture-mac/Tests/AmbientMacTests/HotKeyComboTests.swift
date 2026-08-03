import Carbon.HIToolbox
import XCTest
@testable import AmbientMac

/// We shipped ⌥⌘Space, which is macOS's own "Show Finder search window". The
/// cost was a live test session where every note attempt opened Finder instead.
/// These tests pin the replacement and the parser.
final class HotKeyComboTests: XCTestCase {

    func testDefaultUsesThreeModifiersAndIsNotSpace() {
        let combo = HotKey.Combo.default

        XCTAssertNotEqual(
            combo.keyCode, UInt32(kVK_Space),
            "Space is booked by Spotlight, input sources, Finder search and the emoji viewer"
        )

        let hasCommand = combo.modifiers & UInt32(cmdKey) != 0
        let hasOption = combo.modifiers & UInt32(optionKey) != 0
        let hasControl = combo.modifiers & UInt32(controlKey) != 0
        XCTAssertTrue(
            hasCommand && hasOption && hasControl,
            "a global hotkey outranks every app's own shortcut, so two modifiers is not enough"
        )
    }

    func testParsesAModifierChord() throws {
        let combo = try XCTUnwrap(HotKey.Combo.parse("ctrl+opt+cmd+j"))
        XCTAssertEqual(combo.keyCode, UInt32(kVK_ANSI_J))
        XCTAssertEqual(combo.display, "⌃⌥⌘J")
    }

    func testParseIsCaseAndSpaceInsensitive() throws {
        let combo = try XCTUnwrap(HotKey.Combo.parse("  CTRL + Opt + CMD + K "))
        XCTAssertEqual(combo.keyCode, UInt32(kVK_ANSI_K))
    }

    func testAliasesAreAccepted() throws {
        let a = try XCTUnwrap(HotKey.Combo.parse("control+option+command+n"))
        let b = try XCTUnwrap(HotKey.Combo.parse("ctrl+alt+cmd+n"))
        XCTAssertEqual(a.keyCode, b.keyCode)
        XCTAssertEqual(a.modifiers, b.modifiers)
    }

    func testFunctionKeysParse() throws {
        let combo = try XCTUnwrap(HotKey.Combo.parse("ctrl+f13"))
        XCTAssertEqual(combo.keyCode, UInt32(kVK_F13))
    }

    /// A typo must fall back to the default, not register some other key.
    func testGarbageIsRejected() {
        XCTAssertNil(HotKey.Combo.parse("ctrl+opt+cmd+£"))
        XCTAssertNil(HotKey.Combo.parse("banana+n"))
        XCTAssertNil(HotKey.Combo.parse(""))
        XCTAssertNil(HotKey.Combo.parse("n"), "a bare key with no modifier would fire while typing")
    }
}

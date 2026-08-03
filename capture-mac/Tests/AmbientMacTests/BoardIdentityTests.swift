import XCTest
@testable import AmbientMac

/// board_id is the join key between the capture lane and the graph lane. If it
/// is not stable, the consolidation view shows one board per poll and the demo
/// has no story.
final class BoardIdentityTests: XCTestCase {

    func testSameSurfaceAlwaysProducesTheSameID() {
        let a = BoardIdentity.boardID(app: "Codex", title: "signal pipeline session")
        let b = BoardIdentity.boardID(app: "Codex", title: "signal pipeline session")
        XCTAssertEqual(a, b)
    }

    func testDifferentSurfacesProduceDifferentIDs() {
        let codex = BoardIdentity.boardID(app: "Codex", title: "signal pipeline session")
        let preview = BoardIdentity.boardID(app: "Preview", title: "attention-signals-paper.pdf")
        XCTAssertNotEqual(codex, preview)
    }

    func testIDIsAWellFormedUUIDv5() throws {
        let id = BoardIdentity.boardID(app: "Safari", title: "LinkedIn - profile")

        XCTAssertNotNil(UUID(uuidString: id), "board_id must parse as a UUID: the contract says uuid")
        XCTAssertEqual(id.count, 36)
        XCTAssertEqual(id.lowercased(), id, "lowercase, so string comparison in Cypher is safe")

        let parts = id.split(separator: "-")
        XCTAssertEqual(parts.count, 5)
        XCTAssertEqual(parts[2].first, "5", "version nibble must be 5 (name-based, SHA-1)")
        XCTAssertTrue(
            ["8", "9", "a", "b"].contains(String(parts[3].first!)),
            "variant nibble must be RFC 4122"
        )
    }

    func testUnreadCountsDoNotForkTheBoard() {
        let quiet = BoardIdentity.boardID(app: "Safari", title: "LinkedIn - profile")
        let noisy = BoardIdentity.boardID(app: "Safari", title: "(3) LinkedIn - profile")
        XCTAssertEqual(quiet, noisy, "an arriving notification must not create a new board")
    }

    func testDirtyMarkersDoNotForkTheBoard() {
        let saved = BoardIdentity.boardID(app: "Xcode", title: "SwitchChain.swift")
        let edited = BoardIdentity.boardID(app: "Xcode", title: "• SwitchChain.swift")
        XCTAssertEqual(saved, edited, "typing a character must not create a new board")
    }

    func testWhitespaceIsNormalized() {
        let tidy = BoardIdentity.boardID(app: "Preview", title: "attention signals paper")
        let messy = BoardIdentity.boardID(app: "Preview", title: "  attention   signals  paper  ")
        XCTAssertEqual(tidy, messy)
    }

    /// CROSS-LANGUAGE VECTORS. These values were generated with Python's
    /// `uuid.uuid5` (stdlib, RFC 4122) over the same namespace and name rule,
    /// and `laser-bridge/laser_common.py:board_id()` reproduces them. Swift and
    /// Python agreeing here is what lets the graph lane derive a board_id
    /// without asking the Mac for one.
    func testMatchesThePythonImplementation() {
        let vectors: [(String, String, String)] = [
            ("Codex", "signal pipeline session", "4f079617-6cf8-54d9-899f-e0f4aae7ac74"),
            ("Preview", "attention-signals-paper.pdf", "1deed4a1-c50d-5f5f-aaa3-b8b235b4bfe9"),
            ("Safari", "LinkedIn - profile", "1775bd62-4c99-536f-a59a-e89d4a259c44"),
            ("Safari", "(3) LinkedIn - profile", "1775bd62-4c99-536f-a59a-e89d4a259c44"),
            ("Xcode", "• SwitchChain.swift", "ff97d14c-52be-5c06-aefd-f444f23e7e1f"),
        ]
        for (app, title, expected) in vectors {
            XCTAssertEqual(
                BoardIdentity.boardID(app: app, title: title), expected,
                "board_id for (\(app), \(title)) drifted from the Python implementation"
            )
        }
    }

    func testAppAndTitleAreNotConfusable() {
        // "A|B" must not collide with an app literally named "A|B".
        let split = BoardIdentity.boardID(app: "Codex", title: "session")
        let joined = BoardIdentity.boardID(app: "Codex|session", title: "")
        XCTAssertNotEqual(split, joined)
    }
}

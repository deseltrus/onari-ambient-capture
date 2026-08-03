import XCTest
@testable import AmbientMac

/// The integration risk at 13:00 is that Swift's JSON does not look like the
/// fixtures the graph lane built against. These tests pin our output to the
/// real `fixtures/events-sample.jsonl` in this repo, so the mismatch is caught
/// here at compile-and-test time instead of on stage.
final class ContractConformanceTests: XCTestCase {

    /// Walk up from the test file to the repo root and read the real fixtures.
    private func fixtureEvents() throws -> [[String: Any]] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AmbientMacTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // capture-mac
            .deletingLastPathComponent()  // repo root
        let url = repoRoot.appendingPathComponent("fixtures/events-sample.jsonl")

        let text = try String(contentsOf: url, encoding: .utf8)
        return try text
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
                return try XCTUnwrap(object as? [String: Any])
            }
    }

    private func encodeToDictionary(_ event: AmbientEvent) throws -> [String: Any] {
        let data = try event.encoded()
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    func testSwitchEventHasExactlyTheFixtureKeys() throws {
        let fixtures = try fixtureEvents()
        let fixtureSwitch = try XCTUnwrap(fixtures.first { $0["type"] as? String == "switch" })

        let event = SwitchEvent(
            t: "2026-08-03T18:00:01Z",
            seq: 1,
            from: .origin,
            to: SurfaceRef(app: "Codex", title: "signal pipeline session", boardID: "abc"),
            dwellMsFrom: nil
        )
        let ours = try encodeToDictionary(.switchEvent(event))

        XCTAssertEqual(
            Set(ours.keys), Set(fixtureSwitch.keys),
            "switch event keys drifted from the fixture the graph lane consumes"
        )

        let oursFrom = try XCTUnwrap(ours["from"] as? [String: Any])
        let fixtureFrom = try XCTUnwrap(fixtureSwitch["from"] as? [String: Any])
        XCTAssertEqual(Set(oursFrom.keys), Set(fixtureFrom.keys))
    }

    func testNoteEventHasExactlyTheFixtureKeys() throws {
        let fixtures = try fixtureEvents()
        let fixtureNote = try XCTUnwrap(fixtures.first { $0["type"] as? String == "note" })

        let event = NoteEvent(
            t: "2026-08-03T18:00:20Z",
            boardID: "abc",
            app: "Codex",
            title: "signal pipeline session",
            text: "interesting, ties into the signal thing",
            mode: .note,
            field: nil
        )
        let ours = try encodeToDictionary(.note(event))

        XCTAssertEqual(Set(ours.keys), Set(fixtureNote.keys))
        XCTAssertEqual(ours["mode"] as? String, "note")
    }

    /// Nulls must be PRESENT, not omitted. The consumer reads `from.board_id`
    /// unconditionally; a missing key is a KeyError, not a None.
    func testNullsAreEmittedNotOmitted() throws {
        let event = SwitchEvent(
            t: "2026-08-03T18:00:01Z", seq: 1,
            from: .origin,
            to: SurfaceRef(app: "Codex", title: "s", boardID: "b"),
            dwellMsFrom: nil
        )
        let json = try event.jsonString()

        XCTAssertTrue(json.contains("\"dwell_ms_from\":null"))
        XCTAssertTrue(json.contains("\"app\":null"))
        XCTAssertTrue(json.contains("\"board_id\":null"))
    }

    func testTimestampFormatMatchesFixtures() throws {
        let fixtures = try fixtureEvents()
        let fixtureStamp = try XCTUnwrap(fixtures.first?["t"] as? String)

        let stamp = Contract.stamp(Date(timeIntervalSince1970: 1_785_780_001))

        XCTAssertEqual(stamp.count, fixtureStamp.count, "timestamp shape drifted from the fixtures")
        XCTAssertTrue(stamp.hasSuffix("Z"), "timestamps must be UTC with a Z suffix")
        XCTAssertFalse(stamp.contains("."), "fixtures carry no fractional seconds")
    }

    func testContractConstantsMatchTheContractFile() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("event-contract.json")

        let data = try Data(contentsOf: url)
        let contract = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(contract["version"] as? Int, Contract.version)
        XCTAssertEqual(contract["stream_in"] as? String, Contract.streamIn)
        XCTAssertEqual(contract["stream_out"] as? String, Contract.streamOut)
    }
}

// Small helper so the null test reads clearly.
private extension SwitchEvent {
    func jsonString() throws -> String {
        try AmbientEvent.switchEvent(self).encodedString()
    }
}

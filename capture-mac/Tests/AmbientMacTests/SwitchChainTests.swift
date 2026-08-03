import XCTest
@testable import AmbientMac

/// The chain is where the demo's numbers come from, so it is tested against a
/// clock we control rather than against a real Mac session.
final class SwitchChainTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_785_780_000)

    private func sample(_ app: String, _ title: String) -> SurfaceSample {
        SurfaceSample(app: app, title: title)
    }

    func testFirstSampleCommitsImmediatelyFromNullOrigin() {
        let chain = SwitchChain()
        let event = chain.observe(sample("Codex", "signal pipeline session"), at: t0)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.seq, 1)
        XCTAssertEqual(event?.from, SurfaceRef.origin)
        XCTAssertNil(event?.dwellMsFrom, "the opening switch has no previous board to have dwelled on")
        XCTAssertEqual(event?.to.app, "Codex")
    }

    func testStayingOnTheSameBoardEmitsNothing() {
        let chain = SwitchChain()
        _ = chain.observe(sample("Codex", "signal pipeline session"), at: t0)

        // Twenty polls of sitting still.
        for i in 1...20 {
            let event = chain.observe(
                sample("Codex", "signal pipeline session"),
                at: t0.addingTimeInterval(Double(i) * 0.4)
            )
            XCTAssertNil(event, "polling a stationary surface must not emit switches")
        }
        XCTAssertEqual(chain.seq, 1)
    }

    func testSwitchNeedsToSettleBeforeItCommits() {
        let chain = SwitchChain(minimumDwell: 0.75)
        _ = chain.observe(sample("Codex", "session"), at: t0)

        // Seen once, not yet settled.
        XCTAssertNil(chain.observe(sample("Preview", "paper.pdf"), at: t0.addingTimeInterval(1.0)))
        // Still inside the settle window.
        XCTAssertNil(chain.observe(sample("Preview", "paper.pdf"), at: t0.addingTimeInterval(1.4)))
        // Settled.
        let event = chain.observe(sample("Preview", "paper.pdf"), at: t0.addingTimeInterval(1.8))
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.seq, 2)
        XCTAssertEqual(event?.from.app, "Codex")
        XCTAssertEqual(event?.to.app, "Preview")
    }

    func testFlickThroughIsNotABoard() {
        let chain = SwitchChain(minimumDwell: 0.75)
        _ = chain.observe(sample("Codex", "session"), at: t0)

        // Alt-tab passes over Mail for one poll on the way to Preview.
        XCTAssertNil(chain.observe(sample("Mail", "Inbox"), at: t0.addingTimeInterval(1.0)))
        XCTAssertNil(chain.observe(sample("Preview", "paper.pdf"), at: t0.addingTimeInterval(1.4)))
        let event = chain.observe(sample("Preview", "paper.pdf"), at: t0.addingTimeInterval(2.3))

        XCTAssertEqual(event?.to.app, "Preview")
        XCTAssertEqual(event?.from.app, "Codex", "Mail was never committed, so we came from Codex")
        XCTAssertEqual(chain.seq, 2, "the flicked-past surface must not consume a sequence number")
    }

    func testDwellMeasuresThePreviousBoardNotTheNewOne() {
        let chain = SwitchChain(minimumDwell: 0.5)
        _ = chain.observe(sample("Safari", "LinkedIn - profile"), at: t0)

        _ = chain.observe(sample("Codex", "session"), at: t0.addingTimeInterval(25.0))
        let event = chain.observe(sample("Codex", "session"), at: t0.addingTimeInterval(25.6))

        // 25.6s on the LinkedIn profile — this is the "seen, never noted" beat.
        XCTAssertEqual(Double(event?.dwellMsFrom ?? 0), 25_600, accuracy: 50)
    }

    func testReturningToAPreviousBoardReusesItsIdentity() {
        let chain = SwitchChain(minimumDwell: 0.5)
        _ = chain.observe(sample("Codex", "signal pipeline session"), at: t0)

        _ = chain.observe(sample("Safari", "LinkedIn - profile"), at: t0.addingTimeInterval(2))
        let away = chain.observe(sample("Safari", "LinkedIn - profile"), at: t0.addingTimeInterval(3))

        _ = chain.observe(sample("Codex", "signal pipeline session"), at: t0.addingTimeInterval(10))
        let back = chain.observe(sample("Codex", "signal pipeline session"), at: t0.addingTimeInterval(11))

        XCTAssertNotNil(away)
        XCTAssertEqual(
            back?.to.boardID, away?.from.boardID,
            "coming back to a window must land on the same board, or the wander chain lies"
        )
    }

    func testNoteTargetIsTheCommittedBoard() {
        let chain = SwitchChain(minimumDwell: 0.75)
        _ = chain.observe(sample("Codex", "session"), at: t0)
        // A candidate that has not settled yet.
        _ = chain.observe(sample("Preview", "paper.pdf"), at: t0.addingTimeInterval(1.0))

        XCTAssertEqual(
            chain.noteTarget?.app, "Codex",
            "a note spoken mid-flick belongs to the surface you were actually working in"
        )
    }
}

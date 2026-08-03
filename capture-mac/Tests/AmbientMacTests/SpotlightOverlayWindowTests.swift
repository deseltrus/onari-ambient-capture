import XCTest
@testable import AmbientMac

/// Pins the transplanted window contract. If any of these change, the overlay
/// stops being ambient (steals focus, eats clicks, or gains chrome).
@MainActor
final class SpotlightOverlayWindowTests: XCTestCase {
    func testPanelContract() {
        let panel = SpotlightOverlayWindow.makeConfiguredPanel()
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertFalse(panel.hidesOnDeactivate)
    }

    func testClickThroughIsDefault() {
        let panel = SpotlightOverlayWindow.makeConfiguredPanel()
        XCTAssertTrue(panel.ignoresMouseEvents)
    }
}

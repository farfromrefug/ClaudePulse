import XCTest
import AppKit
@testable import ccpulse

/// The panel's anchoring, which is what keeps a growing panel where the user
/// left it — and on the screen.
final class PanelGeometryTests: XCTestCase {
    /// A 1440×900 screen with the menu bar and Dock taken out.
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)

    private func anchor(
        _ proposed: NSRect,
        from previous: NSRect,
        position: PanelPosition
    ) -> NSRect {
        DynamicIslandPanel.anchoredFrame(
            proposed,
            previous: previous,
            screenFrame: screen,
            position: position
        )
    }

    /// AppKit grows a window from its top left, so the extra height lands below
    /// the old bottom edge — half of a bottom panel off the bottom of the
    /// screen. The panel takes its own bottom edge back.
    func testBottomPanelGrowsUpwardFromItsBottomEdge() {
        let previous = NSRect(x: 1148, y: 12, width: 280, height: 100)
        // What AppKit proposes: same top, taller, so the bottom drops to -388.
        let proposed = NSRect(x: 1148, y: -388, width: 280, height: 500)
        let frame = anchor(proposed, from: previous, position: .bottomRight)

        XCTAssertEqual(frame.minY, previous.minY)
        XCTAssertEqual(frame.height, 500)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
    }

    func testBottomPanelShrinksBackDownToItsBottomEdge() {
        let previous = NSRect(x: 1148, y: 12, width: 280, height: 500)
        let proposed = NSRect(x: 1148, y: 412, width: 280, height: 100)
        XCTAssertEqual(anchor(proposed, from: previous, position: .bottomLeft).minY, previous.minY)
    }

    /// A panel taller than the screen is pushed back onto it rather than
    /// hanging off an edge.
    func testAnOverlyTallPanelIsPulledOntoTheScreen() {
        let previous = NSRect(x: 1148, y: 12, width: 280, height: 100)
        let proposed = NSRect(x: 1148, y: -900, width: 280, height: 1000)
        let frame = anchor(proposed, from: previous, position: .bottomRight)
        XCTAssertEqual(frame.minY, screen.minY)
    }

    /// The bottom-right panel keeps its right edge, so growing wider does not
    /// slide the capsule — and the chevron on it — out from under the cursor.
    func testBottomRightKeepsItsRightEdgeWhenTheWidthChanges() {
        let previous = NSRect(x: 1148, y: 12, width: 280, height: 300)
        let proposed = NSRect(x: 1148, y: 12, width: 320, height: 300)
        XCTAssertEqual(anchor(proposed, from: previous, position: .bottomRight).maxX, previous.maxX)
    }

    func testBottomLeftKeepsItsLeftEdgeWhenTheWidthChanges() {
        let previous = NSRect(x: 12, y: 12, width: 280, height: 300)
        let proposed = NSRect(x: 12, y: 12, width: 320, height: 300)
        XCTAssertEqual(anchor(proposed, from: previous, position: .bottomLeft).minX, previous.minX)
    }

    /// The top panel hangs from its top edge and grows downward instead.
    func testTopPanelKeepsItsTopEdgeAndItsCentre() {
        let previous = NSRect(x: 580, y: 800, width: 280, height: 40)
        let proposed = NSRect(x: 580, y: 800, width: 280, height: 300)
        let frame = anchor(proposed, from: previous, position: .topCenter)
        XCTAssertEqual(frame.maxY, previous.maxY)
        XCTAssertEqual(frame.midX, previous.midX)
    }

    /// A panel dragged low on the screen still cannot grow off the bottom of it.
    func testTopPanelGrowingNearTheBottomStaysOnScreen() {
        let previous = NSRect(x: 580, y: 20, width: 280, height: 40)
        let proposed = NSRect(x: 580, y: 20, width: 280, height: 400)
        let frame = anchor(proposed, from: previous, position: .topCenter)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
        XCTAssertEqual(frame.height, 400)
    }

    /// Dragging the panel is a move, not a resize, and is left alone.
    func testAMoveIsNotAnchored() {
        let previous = NSRect(x: 1148, y: 12, width: 280, height: 300)
        let proposed = NSRect(x: 400, y: 500, width: 280, height: 300)
        XCTAssertEqual(anchor(proposed, from: previous, position: .bottomRight), proposed)
    }
}

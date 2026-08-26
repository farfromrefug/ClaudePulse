import SwiftUI
import AppKit

/// The panel's content view. The window follows the content's own size, so the
/// only thing left to handle is the moment before it catches up: while the
/// window is still taller than what is drawn in it, clicks in the empty strip
/// above the content belong to whatever is behind the panel.
class SizeTrackingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: ((CGSize) -> Void)?
    private var contentHeight: CGFloat = .zero
    private var lastReportedSize: CGSize = .zero

    override func layout() {
        super.layout()
        // Use ceil to avoid fractional sizes that can clip content on some macOS versions
        let fitting = CGSize(width: ceil(fittingSize.width), height: ceil(fittingSize.height))
        contentHeight = fitting.height
        guard fitting != lastReportedSize else { return }
        lastReportedSize = fitting
        // Defer to the next run loop iteration to avoid re-entrant constraint
        // updates, which crash in _postWindowNeedsUpdateConstraints during the
        // display cycle.
        let callback = onSizeChange
        DispatchQueue.main.async { callback?(fitting) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if PanelSettings.shared.position != .topCenter, contentHeight > 0 {
            // AppKit coordinates: y=0 is at the bottom of the view.
            // Content is bottom-aligned, occupying y: 0 ..< contentHeight.
            if point.y > contentHeight {
                return nil
            }
        }
        return super.hitTest(point)
    }
}

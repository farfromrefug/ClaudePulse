import SwiftUI
import AppKit

/// A hosting view that can always move its window.
///
/// `isMovableByWindowBackground` leaves it to AppKit to decide that a press is a
/// window drag, and it was seen not to: the settings window and the panel both
/// stopped moving while the hit view still said it could. So the drag is also
/// started here, by hand, once a press has travelled far enough that it is not a
/// click — and the press still goes to SwiftUI first, so buttons keep working.
class DraggableHostingView<Content: View>: NSHostingView<Content> {
    /// The press a drag may turn out to have started with.
    private var pressEvent: NSEvent?

    /// How far the pointer travels with the button down before a press becomes
    /// a drag rather than a click.
    private let dragThreshold: CGFloat = 4

    override func mouseDown(with event: NSEvent) {
        pressEvent = event
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let press = pressEvent {
            let travelled = hypot(
                event.locationInWindow.x - press.locationInWindow.x,
                event.locationInWindow.y - press.locationInWindow.y
            )
            if travelled > dragThreshold {
                pressEvent = nil
                window?.performDrag(with: press)
                return
            }
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        pressEvent = nil
        super.mouseUp(with: event)
    }

    /// The menu a right click opens, built fresh each time. Nil leaves the
    /// right button to SwiftUI.
    var contextMenuProvider: (() -> NSMenu?)?

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenuProvider?() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// The panel's content view. The window follows the content's own size, so the
/// only thing left to handle is the moment before it catches up: while the
/// window is still taller than what is drawn in it, clicks in the empty strip
/// above the content belong to whatever is behind the panel.
class SizeTrackingHostingView<Content: View>: DraggableHostingView<Content> {
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

    /// Whether `y` falls in the empty strip above the content.
    ///
    /// The content is bottom-aligned in a window that may be taller than it. The
    /// view is flipped — y grows downwards — so the content sits at the *high*
    /// end of y and the strip is the low end; reading it the other way round
    /// threw away every click on the content itself, the capsule included.
    static func isInEmptyStrip(y: CGFloat, boundsHeight: CGFloat, contentHeight: CGFloat, flipped: Bool) -> Bool {
        flipped ? y < boundsHeight - contentHeight : y > contentHeight
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if PanelSettings.shared.position != .topCenter, contentHeight > 0 {
            // `point` is in the superview's coordinates.
            let local = superview.map { convert(point, from: $0) } ?? point
            if Self.isInEmptyStrip(y: local.y, boundsHeight: bounds.height,
                                   contentHeight: contentHeight, flipped: isFlipped) {
                return nil
            }
        }
        return super.hitTest(point)
    }
}

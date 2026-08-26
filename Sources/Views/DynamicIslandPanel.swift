import SwiftUI
import AppKit

class DynamicIslandPanel: NSPanel {
    /// Margin kept between the panel and the screen edges.
    static let screenMargin: CGFloat = 12

    /// The tallest a panel may be on the current screen.
    static func maxPanelHeight(on screen: NSScreen? = NSScreen.main) -> CGFloat {
        guard let screen else { return 600 }
        return screen.visibleFrame.height - screenMargin * 2
    }

    /// Set while the panel places itself, so `setFrame` takes the new frame as
    /// given instead of anchoring it to the old one.
    private var isPlacingItself = false

    /// The latest content size waiting to be applied, and whether a turn of the
    /// run loop has already been booked to apply it.
    private var pendingContentSize: CGSize?
    private var resizeScheduled = false

    /// True while the active space belongs to a fullscreen app. The panel joins
    /// every space so it follows the user around, and that includes fullscreen
    /// ones — so unless the user asked for it, it hides itself there instead.
    private var activeSpaceIsFullscreen = false
    private var hiddenForFullscreen = false

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        self.contentView = contentView
        observeSpaceChanges()
        applyWindowBehavior()
        repositionForCurrentSettings()
    }

    /// True while a permission prompt is waiting: the panel then floats over
    /// fullscreen apps even when the user opted out of that for normal use.
    var isUrgent = false {
        didSet {
            guard isUrgent != oldValue else { return }
            applyWindowBehavior()
        }
    }

    /// Whether the panel joins fullscreen spaces, and how high it floats.
    func applyWindowBehavior() {
        let overFullscreen = isUrgent || PanelSettings.shared.showOverFullscreen
        if overFullscreen {
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            // Above the menu bar / fullscreen chrome so the prompt is reachable.
            level = isUrgent ? .screenSaver : .floating
        } else {
            // Without .fullScreenAuxiliary the panel stays out of fullscreen
            // spaces a *window* owns, but a fullscreen video player is often
            // just a borderless window filling the screen on the current space,
            // and .canJoinAllSpaces puts the panel on top of it either way.
            collectionBehavior = [.canJoinAllSpaces, .stationary]
            level = .floating
        }
        applyFullscreenVisibility()
    }

    // MARK: - Fullscreen spaces

    private func observeSpaceChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeSpaceChanged() {
        applyFullscreenVisibility()
    }

    /// Hides the panel while a fullscreen app owns the screen, unless the user
    /// asked for it there or a prompt is waiting on them.
    func applyFullscreenVisibility() {
        activeSpaceIsFullscreen = Self.screenIsCoveredByAnotherApp()
        let allowed = isUrgent || PanelSettings.shared.showOverFullscreen

        if activeSpaceIsFullscreen && !allowed {
            if isVisible {
                hiddenForFullscreen = true
                orderOut(nil)
            }
        } else if hiddenForFullscreen {
            hiddenForFullscreen = false
            orderFrontRegardless()
        } else if isVisible {
            orderFrontRegardless()
        }
    }

    /// Show or hide the panel because the user asked to, rather than because a
    /// fullscreen app took the screen.
    func setUserVisible(_ visible: Bool) {
        hiddenForFullscreen = false
        if visible {
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
    }

    /// True when another application has a window covering the whole screen —
    /// a fullscreen space, or a video player that simply fills it.
    ///
    /// Only window geometry is read, which needs no screen-recording access.
    static func screenIsCoveredByAnotherApp(screen: NSScreen? = NSScreen.main) -> Bool {
        guard let screen else { return false }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return screenIsCovered(
            by: windows,
            screenFrame: screen.frame,
            ownPID: Int(ProcessInfo.processInfo.processIdentifier),
            frontmostPID: NSWorkspace.shared.frontmostApplication.map { Int($0.processIdentifier) }
        )
    }

    /// The geometry half of the test, kept apart from the window server.
    ///
    /// A fullscreen app owns the space it is in and is always the frontmost
    /// one, which is what separates it from the maximized windows sitting on
    /// other spaces that the window list also reports.
    static func screenIsCovered(
        by windows: [[String: Any]],
        screenFrame: CGRect,
        ownPID: Int,
        frontmostPID: Int?
    ) -> Bool {
        for window in windows {
            // Layer 0 is the normal window layer: the menu bar, the Dock and
            // floating panels (Pulse included) all sit above it.
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int,
                  pid != ownPID,
                  frontmostPID == nil || pid == frontmostPID,
                  let frameValue = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: frameValue as CFDictionary) else { continue }

            if abs(frame.width - screenFrame.width) < 2 && abs(frame.height - screenFrame.height) < 2 {
                return true
            }
        }
        return false
    }

    func repositionForCurrentSettings() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let margin = Self.screenMargin
        let width = PanelSettings.shared.contentWidth
        let height = min(max(frame.height, minimumHeight), Self.maxPanelHeight(on: screen))

        let origin: NSPoint
        switch PanelSettings.shared.position {
        case .topCenter:
            origin = NSPoint(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height - 8)
        case .bottomLeft:
            origin = NSPoint(x: screenFrame.minX + margin, y: screenFrame.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: screenFrame.maxX - width - margin, y: screenFrame.minY + margin)
        }

        isPlacingItself = true
        setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
        isPlacingItself = false
    }

    /// The least a bottom-positioned panel measures. Content shorter than this
    /// opens and closes inside a frame that never moves, which is what keeps
    /// the capsule — and the chevron on it — still under the cursor.
    private var minimumHeight: CGFloat {
        switch PanelSettings.shared.position {
        case .topCenter: return 0
        case .bottomLeft, .bottomRight: return PanelSettings.shared.actionDetail.bottomPanelHeight
        }
    }

    /// Follows the SwiftUI content's size, because the window is the only thing
    /// that clips it. Which way it grows is the anchoring's business.
    ///
    /// A SwiftUI animation reports a new size on every frame it draws, and
    /// resizing a window from inside its own layout pass as fast as that is
    /// what AppKit refuses to do — so the sizes are coalesced and only the last
    /// one of a run loop turn is applied.
    func resizeToContent(_ contentSize: CGSize) {
        pendingContentSize = contentSize
        guard !resizeScheduled else { return }
        resizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeScheduled = false
            guard let size = self.pendingContentSize else { return }
            self.pendingContentSize = nil
            self.applyContentSize(size)
        }
    }

    private func applyContentSize(_ contentSize: CGSize) {
        guard let screen = NSScreen.main else { return }
        let width = ceil(max(contentSize.width, PanelSettings.shared.contentWidth))
        let height = min(max(ceil(contentSize.height), minimumHeight), Self.maxPanelHeight(on: screen))
        guard width != frame.width || height != frame.height else { return }

        // The origin is left as it is: `setFrame` anchors it to the edge this
        // position grows from.
        let target = NSRect(origin: frame.origin, size: CGSize(width: width, height: height))
        setFrame(target, display: false)
    }

    /// Keeps a resized panel on the edge it belongs to.
    ///
    /// The hosting view grows the window to fit its content and AppKit anchors
    /// that growth at the *top left*, which walks a bottom-positioned panel off
    /// the bottom of the screen — the taller the prompt, the further off. Every
    /// resize goes through here, whoever asked for it, so the panel keeps its
    /// own edge and stays on the screen instead.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard !isPlacingItself, let screen = NSScreen.main else {
            super.setFrame(frameRect, display: flag)
            return
        }
        super.setFrame(
            Self.anchoredFrame(
                frameRect,
                previous: frame,
                screenFrame: screen.visibleFrame,
                position: PanelSettings.shared.position
            ),
            display: flag
        )
    }

    /// Where a resized panel belongs — the geometry alone, so it can be
    /// reasoned about (and tested) without a window server.
    ///
    /// The panel keeps the edge it grows from: its top at the top position, its
    /// bottom at the bottom ones, and the side it was last left on. A move that
    /// does not change the size — the user dragging the panel — is left alone.
    static func anchoredFrame(
        _ proposed: NSRect,
        previous: NSRect,
        screenFrame: NSRect,
        position: PanelPosition
    ) -> NSRect {
        guard proposed.size != previous.size else { return proposed }

        var rect = proposed
        switch position {
        case .topCenter:
            rect.origin.x = previous.midX - rect.width / 2
            rect.origin.y = previous.maxY - rect.height
        case .bottomLeft:
            rect.origin.x = previous.minX
            rect.origin.y = previous.minY
        case .bottomRight:
            rect.origin.x = previous.maxX - rect.width
            rect.origin.y = previous.minY
        }

        rect.origin.x = min(max(rect.minX, screenFrame.minX), max(screenFrame.minX, screenFrame.maxX - rect.width))
        rect.origin.y = min(max(rect.minY, screenFrame.minY), max(screenFrame.minY, screenFrame.maxY - rect.height))
        return rect
    }
}

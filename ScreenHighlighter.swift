import AppKit

// MARK: - OverlayView

final class OverlayView: NSView {
    var dimOpacity: CGFloat = 0.6      { didSet { needsDisplay = true } }
    var highlightRectGlobal: CGRect?   { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 0      { didSet { needsDisplay = true } }
    var isBlurEnabled: Bool = false    { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // In blur mode the NSVisualEffectView handles the darkening layer.
        if !isBlurEnabled {
            ctx.setFillColor(NSColor.black.withAlphaComponent(dimOpacity).cgColor)
            ctx.fill(bounds)
        }

        guard let highlightRectGlobal,
              let window = self.window,
              let screen = window.screen else {
            return
        }

        let screenFrame = screen.frame
        let localRect = highlightRectGlobal.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)

        // Cut a (rounded) hole for the focused window.
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        let clipPath = CGPath(
            roundedRect: localRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.addPath(clipPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Also brighten the menu bar when the focused app is on this screen.
        if highlightRectGlobal.intersects(screenFrame) {
            let menuBarLocalY = screen.visibleFrame.maxY - screenFrame.minY
            let menuBarHeight = screenFrame.height - menuBarLocalY
            if menuBarHeight > 0 {
                let menuBarRect = CGRect(x: 0, y: menuBarLocalY, width: screenFrame.width, height: menuBarHeight)
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.fill(menuBarRect)
                ctx.restoreGState()
            }
        }
    }
}

// MARK: - OverlayWindow

final class OverlayWindow: NSWindow {
    let overlayView = OverlayView(frame: .zero)
    private let visualEffectView = NSVisualEffectView(frame: .zero)

    var isBlurEnabled: Bool = false {
        didSet {
            overlayView.isBlurEnabled = isBlurEnabled
            visualEffectView.isHidden = !isBlurEnabled
            if !isBlurEnabled { visualEffectView.maskImage = nil }
        }
    }

    var blurIntensity: CGFloat = 1.0 {
        didSet { visualEffectView.alphaValue = blurIntensity }
    }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let size = screen.frame.size

        visualEffectView.frame = NSRect(origin: .zero, size: size)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .fullScreenUI
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.isHidden = true

        overlayView.frame = NSRect(origin: .zero, size: size)
        overlayView.autoresizingMask = [.width, .height]

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(visualEffectView)
        container.addSubview(overlayView)
        contentView = container

        setFrame(screen.frame, display: true)
    }

    func updateForScreen(_ screen: NSScreen) {
        setFrame(screen.frame, display: true)
        let size = screen.frame.size
        overlayView.frame = NSRect(origin: .zero, size: size)
        visualEffectView.frame = NSRect(origin: .zero, size: size)
    }

    func updateBlurMask(_ highlightRect: CGRect?, cornerRadius: CGFloat = 0) {
        guard isBlurEnabled, let screen = self.screen else {
            visualEffectView.maskImage = nil
            return
        }

        let size = frame.size
        let screenFrame = screen.frame

        let image = NSImage(size: size, flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }

            // Fill everything white to blur the whole screen.
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(bounds)

            ctx.setBlendMode(.clear)

            // Exclude the focused window area (rounded to match its corners).
            if let highlightRect {
                let localRect = highlightRect.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)
                let clearPath = CGPath(
                    roundedRect: localRect,
                    cornerWidth: cornerRadius,
                    cornerHeight: cornerRadius,
                    transform: nil
                )
                ctx.addPath(clearPath)
                ctx.fillPath()
            }

            // Exclude the menu bar.
            if let highlightRect, highlightRect.intersects(screenFrame) {
                let menuBarLocalY = screen.visibleFrame.maxY - screenFrame.minY
                let menuBarHeight = screenFrame.height - menuBarLocalY
                if menuBarHeight > 0 {
                    ctx.fill(CGRect(x: 0, y: menuBarLocalY, width: size.width, height: menuBarHeight))
                }
            }

            return true
        }
        visualEffectView.maskImage = image
    }
}


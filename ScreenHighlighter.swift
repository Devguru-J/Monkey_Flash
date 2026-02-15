import AppKit
import CoreImage

// MARK: - GaussianBlurView

/// Compositor-backed Gaussian blur view.
/// Uses CALayer.backgroundFilters (same underlying path as NSVisualEffectView) so it
/// blurs cross-window content without any screen-capture API.
/// An even-odd CAShapeLayer mask cuts out the focused window and menu bar.
final class GaussianBlurView: NSView {
    var sigma: CGFloat = 30 { didSet { applyBlurFilter() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        applyBlurFilter()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func applyBlurFilter() {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
        filter.setValue(sigma, forKey: kCIInputRadiusKey)
        backgroundFilters = [filter]
    }

    /// Rebuild the even-odd mask: blurs the entire screen EXCEPT the focused window
    /// rect (and the menu bar when the focused window is on this screen).
    func updateMask(screen: NSScreen, highlightRectGlobal: CGRect?, cornerRadius: CGFloat) {
        guard let layer else { return }

        let path = CGMutablePath()
        path.addRect(layer.bounds)          // outer rect — the blurred region

        if let highlightRectGlobal {
            let screenFrame = screen.frame
            let localRect = highlightRectGlobal.offsetBy(
                dx: -screenFrame.origin.x,
                dy: -screenFrame.origin.y
            )
            // Hole 1: focused window
            path.addPath(CGPath(
                roundedRect: localRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            ))
            // Hole 2: menu bar (only when the focused window is on this screen)
            if highlightRectGlobal.intersects(screenFrame) {
                let menuBarLocalY = screen.visibleFrame.maxY - screenFrame.minY
                let menuBarHeight = screenFrame.height - menuBarLocalY
                if menuBarHeight > 0 {
                    path.addRect(CGRect(
                        x: 0, y: menuBarLocalY,
                        width: layer.bounds.width, height: menuBarHeight
                    ))
                }
            }
        }

        let maskLayer = CAShapeLayer()
        maskLayer.frame    = layer.bounds
        maskLayer.path     = path
        maskLayer.fillRule = .evenOdd
        layer.mask = maskLayer
    }
}

// MARK: - OverlayView

final class OverlayView: NSView {
    var dimOpacity: CGFloat = 0.6      { didSet { needsDisplay = true } }
    var highlightRectGlobal: CGRect?   { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 0      { didSet { needsDisplay = true } }
    // blur mode: GaussianBlurView owns all compositing, this view draws nothing
    var isBlurEnabled: Bool = false    { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard !isBlurEnabled else { return }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(dimOpacity).cgColor)
        ctx.fill(bounds)

        guard let highlightRectGlobal,
              let window = self.window,
              let screen = window.screen else { return }

        let screenFrame = screen.frame
        let localRect = highlightRectGlobal.offsetBy(
            dx: -screenFrame.origin.x,
            dy: -screenFrame.origin.y
        )

        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addPath(CGPath(
            roundedRect: localRect,
            cornerWidth: cornerRadius, cornerHeight: cornerRadius,
            transform: nil
        ))
        ctx.fillPath()
        ctx.restoreGState()

        if highlightRectGlobal.intersects(screenFrame) {
            let menuBarLocalY = screen.visibleFrame.maxY - screenFrame.minY
            let menuBarHeight = screenFrame.height - menuBarLocalY
            if menuBarHeight > 0 {
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.fill(CGRect(
                    x: 0, y: menuBarLocalY,
                    width: screenFrame.width, height: menuBarHeight
                ))
                ctx.restoreGState()
            }
        }
    }
}

// MARK: - OverlayWindow

final class OverlayWindow: NSWindow {
    let overlayView      = OverlayView(frame: .zero)
    private let blurView = GaussianBlurView(frame: .zero)

    var isBlurEnabled: Bool = false {
        didSet {
            overlayView.isBlurEnabled = isBlurEnabled
            blurView.isHidden         = !isBlurEnabled
        }
    }

    // blurIntensity 0.1~1.0 → sigma 5~50px
    var blurIntensity: CGFloat = 1.0 {
        didSet { blurView.sigma = 5 + blurIntensity * 45 }
    }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )

        isOpaque           = false
        backgroundColor    = .clear
        hasShadow          = false
        level              = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let size = screen.frame.size

        blurView.frame            = NSRect(origin: .zero, size: size)
        blurView.autoresizingMask = [.width, .height]
        blurView.isHidden         = true

        overlayView.frame            = NSRect(origin: .zero, size: size)
        overlayView.autoresizingMask = [.width, .height]

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(blurView)    // bottom: Gaussian blur layer
        container.addSubview(overlayView) // top:    dim / cutout layer
        contentView = container

        setFrame(screen.frame, display: true)
    }

    func updateForScreen(_ screen: NSScreen) {
        setFrame(screen.frame, display: true)
        let size = screen.frame.size
        overlayView.frame = NSRect(origin: .zero, size: size)
        blurView.frame    = NSRect(origin: .zero, size: size)
    }

    // MARK: - Gaussian blur

    /// Update the blur mask whenever the focused window position or size changes.
    /// No screen capture or async work needed — the compositor handles rendering.
    func updateGaussianBlur(_ highlightRect: CGRect?, cornerRadius: CGFloat = 0) {
        guard isBlurEnabled, let screen = self.screen else { return }
        blurView.updateMask(
            screen: screen,
            highlightRectGlobal: highlightRect,
            cornerRadius: cornerRadius
        )
    }
}

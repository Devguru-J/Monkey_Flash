import AppKit
import CoreImage
import ScreenCaptureKit

// MARK: - OverlayView

final class OverlayView: NSView {
    var dimOpacity: CGFloat = 0.6      { didSet { needsDisplay = true } }
    var highlightRectGlobal: CGRect?   { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 0      { didSet { needsDisplay = true } }
    // blur mode: blurImageView owns all compositing, this view draws nothing
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
        let localRect = highlightRectGlobal.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)

        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addPath(CGPath(roundedRect: localRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()

        if highlightRectGlobal.intersects(screenFrame) {
            let menuBarLocalY = screen.visibleFrame.maxY - screenFrame.minY
            let menuBarHeight = screenFrame.height - menuBarLocalY
            if menuBarHeight > 0 {
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.fill(CGRect(x: 0, y: menuBarLocalY, width: screenFrame.width, height: menuBarHeight))
                ctx.restoreGState()
            }
        }
    }
}

// MARK: - OverlayWindow

final class OverlayWindow: NSWindow {
    let overlayView = OverlayView(frame: .zero)

    // Gaussian blur composite layer
    private let blurImageView = NSImageView(frame: .zero)

    // Reusable CIContext — GPU-accelerated, never recreated
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // blurIntensity 0.1~1.0 → sigma 5~50px (Photoshop-like Gaussian)
    private var blurSigma: CGFloat = 30.0

    // Prevents multiple concurrent capture jobs when window is dragged
    private var isCapturePending = false

    var isBlurEnabled: Bool = false {
        didSet {
            overlayView.isBlurEnabled = isBlurEnabled
            if !isBlurEnabled {
                blurImageView.image    = nil
                blurImageView.isHidden = true
                isCapturePending       = false
            }
        }
    }

    var blurIntensity: CGFloat = 1.0 {
        didSet { blurSigma = 5 + blurIntensity * 45 }  // 5px ~ 50px sigma
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

        blurImageView.frame = NSRect(origin: .zero, size: size)
        blurImageView.autoresizingMask = [.width, .height]
        blurImageView.imageScaling = .scaleAxesIndependently
        blurImageView.isHidden = true

        overlayView.frame = NSRect(origin: .zero, size: size)
        overlayView.autoresizingMask = [.width, .height]

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(blurImageView)   // bottom: Gaussian blur layer
        container.addSubview(overlayView)     // top:    dim / cutout layer
        contentView = container

        setFrame(screen.frame, display: true)
    }

    func updateForScreen(_ screen: NSScreen) {
        setFrame(screen.frame, display: true)
        let size = screen.frame.size
        overlayView.frame   = NSRect(origin: .zero, size: size)
        blurImageView.frame = NSRect(origin: .zero, size: size)
    }

    // MARK: - Gaussian blur

    func updateGaussianBlur(_ highlightRect: CGRect?, cornerRadius: CGFloat = 0) {
        guard isBlurEnabled else {
            blurImageView.image    = nil
            blurImageView.isHidden = true
            return
        }
        guard !isCapturePending else { return }
        isCapturePending = true

        // Hide blur image so our window is fully transparent during the capture.
        // (overlayView already draws nothing in blur mode.)
        blurImageView.isHidden = true

        let capturedRect   = highlightRect
        let capturedRadius = cornerRadius

        // Defer one run-loop so WindowServer composites our transparent window
        // before SCScreenshotManager captures the display.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard #available(macOS 14.0, *) else {
                self.isCapturePending = false
                return  // macOS 13: blur unavailable without screen capture API
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.isCapturePending = false }
                guard self.isBlurEnabled, let screen = self.screen else { return }
                guard let cgCapture = await self.captureDisplay(screen) else { return }
                self.applyGaussianBlur(
                    screen: screen, cgCapture: cgCapture,
                    highlightRect: capturedRect, cornerRadius: capturedRadius
                )
            }
        }
    }

    private func applyGaussianBlur(
        screen: NSScreen, cgCapture: CGImage,
        highlightRect: CGRect?, cornerRadius: CGFloat
    ) {
        // --- CIGaussianBlur (GPU path) ---
        let ciInput = CIImage(cgImage: cgCapture)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
        filter.setValue(ciInput,   forKey: kCIInputImageKey)
        filter.setValue(blurSigma, forKey: kCIInputRadiusKey)
        guard let ciOutput = filter.outputImage else { return }

        // Gaussian expands extent by ~3×sigma on each edge; crop back to original size
        let cropped = ciOutput.cropped(to: ciInput.extent)
        guard let blurredCG = ciContext.createCGImage(cropped, from: cropped.extent) else { return }

        // --- Composite: blurred background with focused window + menu bar cut out ---
        let outputSize  = frame.size
        let screenFrame = screen.frame

        let composite = NSImage(size: outputSize, flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }

            // SCScreenshotManager returns top-left origin; NSImage context is bottom-left → flip.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(blurredCG, in: bounds)
            ctx.restoreGState()

            ctx.setBlendMode(.clear)

            // Reveal focused window through the blur.
            if let highlightRect {
                let localRect = highlightRect.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)
                ctx.addPath(CGPath(roundedRect: localRect,
                                   cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                                   transform: nil))
                ctx.fillPath()
            }

            // Reveal menu bar.
            if let highlightRect, highlightRect.intersects(screenFrame) {
                let menuBarLocalY = screen.visibleFrame.maxY - screenFrame.minY
                let menuBarHeight = screenFrame.height - menuBarLocalY
                if menuBarHeight > 0 {
                    ctx.fill(CGRect(x: 0, y: menuBarLocalY, width: outputSize.width, height: menuBarHeight))
                }
            }

            return true
        }

        blurImageView.image    = composite
        blurImageView.isHidden = false
    }

    // MARK: - Display capture (ScreenCaptureKit)

    @available(macOS 14.0, *)
    private func captureDisplay(_ screen: NSScreen) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ) else { return nil }

        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
            ?? CGMainDisplayID()
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID })
        else { return nil }

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

        let config = SCStreamConfiguration()
        let scale  = screen.backingScaleFactor
        config.width       = Int(screen.frame.width  * scale)
        config.height      = Int(screen.frame.height * scale)
        config.showsCursor = false

        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

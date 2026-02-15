import AppKit
import ApplicationServices

final class OverlayView: NSView {
    var dimOpacity: CGFloat = 0.6 { didSet { needsDisplay = true } }
    var highlightRectGlobal: CGRect? { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(dimOpacity).cgColor)
        ctx.fill(bounds)

        guard let highlightRectGlobal,
              let window = self.window,
              let screen = window.screen else {
            return
        }

        let screenFrame = screen.frame
        let localRect = highlightRectGlobal.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)

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
    }
}

final class OverlayWindow: NSWindow {
    let overlayView = OverlayView(frame: .zero)

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

        overlayView.frame = NSRect(origin: .zero, size: screen.frame.size)
        overlayView.autoresizingMask = [.width, .height]
        contentView = overlayView

        setFrame(screen.frame, display: true)
    }

    func updateForScreen(_ screen: NSScreen) {
        setFrame(screen.frame, display: true)
        overlayView.frame = NSRect(origin: .zero, size: screen.frame.size)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct AXWindowMatch {
        let rect: CGRect
        let windowNumber: Int?
    }

    private struct WindowKey: Hashable {
        let pid: pid_t
        let windowNumber: Int
    }

    private enum CoordinateMode {
        case raw
        case flipped
    }

    private var statusItem: NSStatusItem!
    private var overlays: [NSScreen: OverlayWindow] = [:]
    private var updateTimer: Timer?

    private var isEnabled = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
            rebuildMenu()
            syncOverlayVisibility()
        }
    }

    private var dimOpacity: CGFloat = 0.62 {
        didSet {
            UserDefaults.standard.set(Double(dimOpacity), forKey: "dimOpacity")
            propagateVisualSettings()
        }
    }

    private var padding: CGFloat = 0
    private var lastFocusedRect: CGRect?
    private var lastFocusedPID: pid_t?
    private var lastFocusedWindowNumber: Int?
    private var windowModeCache: [WindowKey: CoordinateMode] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        createStatusItem()
        rebuildOverlays()
        startTimer()
        rebuildMenu()
        loadSettings()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
    }

    @objc private func handleScreenChange() {
        rebuildOverlays()
    }

    private func loadSettings() {
        let ud = UserDefaults.standard
        if ud.object(forKey: "isEnabled") != nil {
            isEnabled = ud.bool(forKey: "isEnabled")
        }
        if ud.object(forKey: "dimOpacity") != nil {
            dimOpacity = CGFloat(ud.double(forKey: "dimOpacity"))
        }
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Focus"
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggleTitle = isEnabled ? "Disable Highlight" : "Enable Highlight"
        menu.addItem(NSMenuItem(title: toggleTitle, action: #selector(toggleEnabled), keyEquivalent: "t"))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Dim +", action: #selector(increaseDim), keyEquivalent: "="))
        menu.addItem(NSMenuItem(title: "Dim -", action: #selector(decreaseDim), keyEquivalent: "-"))
        menu.addItem(NSMenuItem(title: "Request Permission", action: #selector(recheckPermission), keyEquivalent: "p"))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func rebuildOverlays() {
        for (screen, window) in overlays {
            if NSScreen.screens.contains(screen) {
                window.updateForScreen(screen)
            } else {
                window.orderOut(nil)
            }
        }

        var next: [NSScreen: OverlayWindow] = [:]
        for screen in NSScreen.screens {
            if let existing = overlays[screen] {
                next[screen] = existing
            } else {
                next[screen] = OverlayWindow(screen: screen)
            }
        }

        overlays = next
        propagateVisualSettings()
        syncOverlayVisibility()
    }

    private func syncOverlayVisibility() {
        guard isEnabled else {
            for window in overlays.values {
                window.orderOut(nil)
            }
            return
        }
        tick()
    }

    private func propagateVisualSettings() {
        for window in overlays.values {
            window.overlayView.dimOpacity = dimOpacity
        }
    }

    private func startTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let updateTimer {
            updateTimer.tolerance = 0
            RunLoop.main.add(updateTimer, forMode: .common)
        }
    }

    private func tick() {
        guard isEnabled else { return }

        if let freshRect = focusedWindowRect()?.insetBy(dx: -padding, dy: -padding) {
            lastFocusedRect = freshRect
        }

        guard let focusRect = lastFocusedRect else {
            for window in overlays.values {
                window.orderOut(nil)
            }
            return
        }

        for window in overlays.values {
            window.overlayView.highlightRectGlobal = focusRect.integral
            window.orderFrontRegardless()
        }
    }

    private func focusedWindowRect() -> CGRect? {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        if frontmostPID == ProcessInfo.processInfo.processIdentifier { return nil }

        // If app focus changed, clear old window lock immediately so click-switch is not blocked.
        if lastFocusedPID != frontmostPID {
            lastFocusedPID = frontmostPID
            lastFocusedWindowNumber = nil
        }

        if AXIsProcessTrusted(),
           let axMatch = focusedWindowAXInfo(for: frontmostPID) {
            lastFocusedWindowNumber = axMatch.windowNumber

            if let windowNumber = axMatch.windowNumber,
               let cgRect = cgRectForWindowNumber(windowNumber, pid: frontmostPID) {
                return convertWindowServerRectToAppKit(cgRect).integral
            }
            return convertWindowServerRectToAppKit(axMatch.rect).integral
        }

        if let cgTop = topmostCGWindow(for: frontmostPID) {
            lastFocusedWindowNumber = cgTop.windowNumber
            return convertWindowServerRectToAppKit(cgTop.wsRect).integral
        }

        return nil
    }

    private func topmostCGWindow(for pid: pid_t) -> (windowNumber: Int, wsRect: CGRect)? {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in windowInfo {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
                continue
            }
            guard let windowNumber = info[kCGWindowNumber as String] as? Int else {
                continue
            }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                continue
            }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }
            var wsRect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &wsRect), wsRect.width > 40, wsRect.height > 40 else {
                continue
            }
            return (windowNumber: windowNumber, wsRect: wsRect)
        }
        return nil
    }

    private func focusedWindowAXInfoFromSystemWide() -> (pid: pid_t, match: AXWindowMatch)? {
        let system = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appRef)
        guard appResult == .success,
              let appRef,
              CFGetTypeID(appRef) == AXUIElementGetTypeID() else {
            return nil
        }

        let axApp = appRef as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(axApp, &pid) == .success else { return nil }
        if pid == ProcessInfo.processInfo.processIdentifier { return nil }

        if let match = readAXWindowMatch(attribute: kAXFocusedWindowAttribute as CFString, app: axApp) {
            return (pid: pid, match: match)
        }
        if let match = readAXWindowMatch(attribute: kAXMainWindowAttribute as CFString, app: axApp) {
            return (pid: pid, match: match)
        }

        if let match = firstAXWindowMatch(from: axApp) {
            return (pid: pid, match: match)
        }
        return nil
    }

    private func focusedWindowAXInfo(for pid: pid_t) -> AXWindowMatch? {
        let axApp = AXUIElementCreateApplication(pid)

        if let match = readAXWindowMatch(attribute: kAXFocusedWindowAttribute as CFString, app: axApp) {
            return match
        }

        if let match = readAXWindowMatch(attribute: kAXMainWindowAttribute as CFString, app: axApp) {
            return match
        }

        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard windowsResult == .success,
              let windowsRef,
              CFGetTypeID(windowsRef) == CFArrayGetTypeID() else {
            return nil
        }

        let windows = windowsRef as! [AXUIElement]
        for window in windows {
            if let minimized = readBoolAttribute(kAXMinimizedAttribute as CFString, from: window), minimized {
                continue
            }
            if let match = readAXWindowMatch(from: window) {
                return match
            }
        }
        return nil
    }

    private func firstAXWindowMatch(from axApp: AXUIElement) -> AXWindowMatch? {
        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard windowsResult == .success,
              let windowsRef,
              CFGetTypeID(windowsRef) == CFArrayGetTypeID() else {
            return nil
        }

        let windows = windowsRef as! [AXUIElement]
        for window in windows {
            if let minimized = readBoolAttribute(kAXMinimizedAttribute as CFString, from: window), minimized {
                continue
            }
            if let match = readAXWindowMatch(from: window) {
                return match
            }
        }
        return nil
    }

    private func readAXWindowMatch(attribute: CFString, app: AXUIElement) -> AXWindowMatch? {
        var focusedWindowRef: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(app, attribute, &focusedWindowRef)
        guard focusedWindowResult == .success,
              let focusedWindowRef,
              CFGetTypeID(focusedWindowRef) == AXUIElementGetTypeID() else {
            return nil
        }

        let windowElement = focusedWindowRef as! AXUIElement
        return readAXWindowMatch(from: windowElement)
    }

    private func readAXWindowMatch(from windowElement: AXUIElement) -> AXWindowMatch? {
        let windowNumber = readIntAttribute("AXWindowNumber" as CFString, from: windowElement)

        if let frame = readCGRectAttribute("AXFrame" as CFString, from: windowElement) {
            return AXWindowMatch(rect: frame, windowNumber: windowNumber)
        }

        guard let position = readCGPointAttribute(kAXPositionAttribute as CFString, from: windowElement),
              let size = readCGSizeAttribute(kAXSizeAttribute as CFString, from: windowElement) else {
            return nil
        }
        return AXWindowMatch(rect: CGRect(origin: position, size: size), windowNumber: windowNumber)
    }

    private func focusedWindowRectFromCGWindowList(for pid: pid_t, preferredRect: CGRect?) -> CGRect? {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var firstCandidate: CGRect?
        var bestOverlapRect: CGRect?
        var bestOverlapScore: CGFloat = 0

        for info in windowInfo {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
                continue
            }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                continue
            }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }
            var wsRect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &wsRect), wsRect.width > 40, wsRect.height > 40 else {
                continue
            }
            let candidate = normalizedCGRect(wsRect, referenceRect: preferredRect ?? lastFocusedRect)

            if firstCandidate == nil {
                firstCandidate = candidate
            }

            if let preferredRect {
                let score = overlapRatio(lhs: candidate, rhs: preferredRect)
                if score > bestOverlapScore {
                    bestOverlapScore = score
                    bestOverlapRect = candidate
                }
            }
        }

        if let bestOverlapRect, bestOverlapScore > 0.2 {
            return bestOverlapRect
        }
        return firstCandidate
    }

    private func cgRectForWindowNumber(_ windowNumber: Int, pid: pid_t) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]],
              let first = info.first else {
            return nil
        }
        guard let ownerPID = first[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
            return nil
        }
        guard let boundsDict = first[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        var wsRect = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDict, &wsRect), wsRect.width > 40, wsRect.height > 40 else {
            return nil
        }
        return wsRect
    }

    private func normalizedCGRect(_ wsRect: CGRect, referenceRect: CGRect?) -> CGRect {
        let raw = wsRect
        let flipped = convertWindowServerRectToAppKit(wsRect)
        guard let referenceRect else {
            return raw
        }
        let rawScore = overlapRatio(lhs: raw, rhs: referenceRect)
        let flippedScore = overlapRatio(lhs: flipped, rhs: referenceRect)
        return flippedScore > rawScore ? flipped : raw
    }

    private func chooseMode(wsRect: CGRect, referenceRect: CGRect) -> CoordinateMode {
        let rawScore = overlapRatio(lhs: wsRect, rhs: referenceRect)
        let flippedRect = convertWindowServerRectToAppKit(wsRect)
        let flippedScore = overlapRatio(lhs: flippedRect, rhs: referenceRect)
        return flippedScore > rawScore ? .flipped : .raw
    }

    private func rect(for wsRect: CGRect, mode: CoordinateMode) -> CGRect {
        switch mode {
        case .raw:
            return wsRect
        case .flipped:
            return convertWindowServerRectToAppKit(wsRect)
        }
    }

    private func convertWindowServerRectToAppKit(_ wsRect: CGRect) -> CGRect {
        let desktop = desktopFrame()
        let y = desktop.maxY - wsRect.maxY
        return CGRect(x: wsRect.minX, y: y, width: wsRect.width, height: wsRect.height)
    }

    private func desktopFrame() -> CGRect {
        var union = CGRect.null
        for screen in NSScreen.screens {
            union = union.union(screen.frame)
        }
        return union.isNull ? CGRect.zero : union
    }

    private func readCGRectAttribute(_ key: CFString, from element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(axValue, .cgRect, &rect) ? rect : nil
    }

    private func readCGPointAttribute(_ key: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func readCGSizeAttribute(_ key: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private func readBoolAttribute(_ key: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value,
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }
        return (value as! Bool)
    }

    private func readIntAttribute(_ key: CFString, from element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value,
              CFGetTypeID(value) == CFNumberGetTypeID() else {
            return nil
        }
        let number = value as! CFNumber
        var intValue: Int32 = 0
        guard CFNumberGetValue(number, .sInt32Type, &intValue) else { return nil }
        return Int(intValue)
    }

    private func overlapRatio(lhs: CGRect, rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let lhsArea = lhs.width * lhs.height
        guard lhsArea > 0 else { return 0 }
        return (intersection.width * intersection.height) / lhsArea
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
    }

    @objc private func increaseDim() {
        dimOpacity = min(0.9, dimOpacity + 0.05)
    }

    @objc private func decreaseDim() {
        dimOpacity = max(0.15, dimOpacity - 0.05)
    }

    @objc private func recheckPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

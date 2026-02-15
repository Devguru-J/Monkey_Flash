import AppKit
import ApplicationServices
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Types

    private struct AXWindowMatch {
        let rect: CGRect
        let windowNumber: Int?
        let cornerRadius: CGFloat
    }

    private struct FocusedWindowInfo {
        let rect: CGRect
        let cornerRadius: CGFloat
    }

    private struct WindowKey: Hashable {
        let pid: pid_t
        let windowNumber: Int
    }

    private enum CoordinateMode {
        case raw
        case flipped
    }

    // MARK: - Properties

    private let appState = AppState.shared
    private var cancellables: Set<AnyCancellable> = []

    private var statusItem: NSStatusItem!
    private var overlays: [NSScreen: OverlayWindow] = [:]
    private var updateTimer: Timer?

    private let padding: CGFloat = 0
    private var lastFocusedRect: CGRect?
    private var lastFocusedCornerRadius: CGFloat = 10.0
    private var lastFocusedPID: pid_t?
    private var lastFocusedWindowNumber: Int?
    private var windowModeCache: [WindowKey: CoordinateMode] = [:]
    private var lastBlurMaskRect: CGRect?

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(appState.showStatusBarIcon ? .accessory : .regular)

        createStatusItem()
        rebuildOverlays()
        startTimer()
        setupStateObservers()
        setupHotkeyManager()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
        HotkeyManager.shared.stopMonitoring()
    }

    // MARK: - State observers (Combine)

    private func setupStateObservers() {
        appState.$isEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncOverlayVisibility() }
            .store(in: &cancellables)

        appState.$dimOpacity
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.propagateVisualSettings() }
            .store(in: &cancellables)

        appState.$isBlurEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.propagateVisualSettings() }
            .store(in: &cancellables)

        appState.$blurIntensity
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.propagateVisualSettings() }
            .store(in: &cancellables)

        appState.$showStatusBarIcon
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyStatusBarIconPolicy() }
            .store(in: &cancellables)

        appState.$shortcuts
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newShortcuts in self?.updateHotkeyShortcuts(newShortcuts) }
            .store(in: &cancellables)
    }

    // MARK: - HotkeyManager

    private func setupHotkeyManager() {
        updateHotkeyShortcuts(appState.shortcuts)

        HotkeyManager.shared.actionHandler = { [weak self] action in
            self?.handleHotkeyAction(action)
        }
        HotkeyManager.shared.startMonitoring()
    }

    private func updateHotkeyShortcuts(_ shortcuts: [String: HotkeyCombo]) {
        var actionShortcuts: [HotkeyAction: HotkeyCombo] = [:]
        for (key, combo) in shortcuts {
            if let action = HotkeyAction(rawValue: key) {
                actionShortcuts[action] = combo
            }
        }
        HotkeyManager.shared.update(shortcuts: actionShortcuts)
    }

    private func handleHotkeyAction(_ action: HotkeyAction) {
        switch action {
        case .toggleEnabled:  appState.isEnabled.toggle()
        case .openSettings:   SettingsWindowController.shared.open()
        case .increaseDim:    appState.dimOpacity    = min(0.9,  appState.dimOpacity    + 0.05)
        case .decreaseDim:    appState.dimOpacity    = max(0.15, appState.dimOpacity    - 0.05)
        case .toggleBlur:     appState.isBlurEnabled.toggle()
        case .increaseBlur:   appState.blurIntensity = min(1.0,  appState.blurIntensity + 0.1)
        case .decreaseBlur:   appState.blurIntensity = max(0.1,  appState.blurIntensity - 0.1)
        }
    }

    // MARK: - Status item

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Focus"
        statusItem.button?.action = #selector(openSettings)
        statusItem.button?.target = self
        statusItem.isVisible = appState.showStatusBarIcon
    }

    private func applyStatusBarIconPolicy() {
        statusItem.isVisible = appState.showStatusBarIcon
        if appState.showStatusBarIcon {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
            SettingsWindowController.shared.open()
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.open()
    }

    // MARK: - Screen change

    @objc private func handleScreenChange() {
        rebuildOverlays()
    }

    // MARK: - Overlay management

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
        guard appState.isEnabled else {
            for window in overlays.values { window.orderOut(nil) }
            return
        }
        tick()
    }

    private func propagateVisualSettings() {
        for window in overlays.values {
            window.overlayView.dimOpacity = CGFloat(appState.dimOpacity)
            window.isBlurEnabled = appState.isBlurEnabled
            window.blurIntensity = CGFloat(appState.blurIntensity)
            if appState.isBlurEnabled {
                window.updateBlurMask(lastFocusedRect, cornerRadius: lastFocusedCornerRadius)
            }
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
        guard appState.isEnabled else { return }

        if let info = focusedWindowInfo() {
            lastFocusedRect = info.rect.insetBy(dx: -padding, dy: -padding)
            lastFocusedCornerRadius = info.cornerRadius
        }

        guard let focusRect = lastFocusedRect else {
            for window in overlays.values { window.orderOut(nil) }
            return
        }

        let focusIntegral = focusRect.integral
        let rectChanged = focusIntegral != lastBlurMaskRect

        for window in overlays.values {
            window.overlayView.highlightRectGlobal = focusIntegral
            window.overlayView.cornerRadius = lastFocusedCornerRadius
            if appState.isBlurEnabled && rectChanged {
                window.updateBlurMask(focusIntegral, cornerRadius: lastFocusedCornerRadius)
            }
            window.orderFrontRegardless()
        }

        if appState.isBlurEnabled && rectChanged {
            lastBlurMaskRect = focusIntegral
        }
    }

    // MARK: - Focused window detection

    private func focusedWindowInfo() -> FocusedWindowInfo? {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        if frontmostPID == ProcessInfo.processInfo.processIdentifier { return nil }

        if lastFocusedPID != frontmostPID {
            lastFocusedPID = frontmostPID
            lastFocusedWindowNumber = nil
        }

        if AXIsProcessTrusted(),
           let axMatch = focusedWindowAXInfo(for: frontmostPID) {
            lastFocusedWindowNumber = axMatch.windowNumber
            let cr = axMatch.cornerRadius

            if let windowNumber = axMatch.windowNumber,
               let cgRect = cgRectForWindowNumber(windowNumber, pid: frontmostPID) {
                return FocusedWindowInfo(
                    rect: convertWindowServerRectToAppKit(cgRect).integral,
                    cornerRadius: cr
                )
            }
            return FocusedWindowInfo(
                rect: convertWindowServerRectToAppKit(axMatch.rect).integral,
                cornerRadius: cr
            )
        }

        if let cgTop = topmostCGWindow(for: frontmostPID) {
            lastFocusedWindowNumber = cgTop.windowNumber
            return FocusedWindowInfo(
                rect: convertWindowServerRectToAppKit(cgTop.wsRect).integral,
                cornerRadius: defaultCornerRadius()
            )
        }

        return nil
    }

    // MARK: - Corner radius

    private func windowCornerRadius(for windowElement: AXUIElement) -> CGFloat {
        // 1. Try AX attribute (non-standard but supported by some apps).
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(windowElement, "AXCornerRadius" as CFString, &value) == .success,
           let number = value as? NSNumber {
            return CGFloat(number.doubleValue)
        }

        // 2. Full-screen windows have no corner radius.
        var subRoleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(windowElement, kAXSubroleAttribute as CFString, &subRoleRef) == .success,
           let subRole = subRoleRef as? String, subRole == "AXFullScreenWindow" {
            return 0
        }

        // 3. macOS version-based default.
        return defaultCornerRadius()
    }

    private func defaultCornerRadius() -> CGFloat {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion >= 26 { return 12.0 }
        return 10.0
    }

    // MARK: - AX helpers

    private func topmostCGWindow(for pid: pid_t) -> (windowNumber: Int, wsRect: CGRect)? {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for info in windowInfo {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
            guard let windowNumber = info[kCGWindowNumber as String] as? Int else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { continue }
            var wsRect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &wsRect), wsRect.width > 40, wsRect.height > 40 else { continue }
            return (windowNumber: windowNumber, wsRect: wsRect)
        }
        return nil
    }

    private func focusedWindowAXInfo(for pid: pid_t) -> AXWindowMatch? {
        let axApp = AXUIElementCreateApplication(pid)

        if let match = readAXWindowMatch(attribute: kAXFocusedWindowAttribute as CFString, app: axApp) { return match }
        if let match = readAXWindowMatch(attribute: kAXMainWindowAttribute as CFString, app: axApp) { return match }

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windowsRef, CFGetTypeID(windowsRef) == CFArrayGetTypeID() else { return nil }

        let windows = windowsRef as! [AXUIElement]
        for window in windows {
            if let minimized = readBoolAttribute(kAXMinimizedAttribute as CFString, from: window), minimized { continue }
            if let match = readAXWindowMatch(from: window) { return match }
        }
        return nil
    }

    private func readAXWindowMatch(attribute: CFString, app: AXUIElement) -> AXWindowMatch? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, attribute, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return readAXWindowMatch(from: ref as! AXUIElement)
    }

    private func readAXWindowMatch(from windowElement: AXUIElement) -> AXWindowMatch? {
        let windowNumber = readIntAttribute("AXWindowNumber" as CFString, from: windowElement)
        let cornerRadius = windowCornerRadius(for: windowElement)

        if let frame = readCGRectAttribute("AXFrame" as CFString, from: windowElement) {
            return AXWindowMatch(rect: frame, windowNumber: windowNumber, cornerRadius: cornerRadius)
        }

        guard let position = readCGPointAttribute(kAXPositionAttribute as CFString, from: windowElement),
              let size = readCGSizeAttribute(kAXSizeAttribute as CFString, from: windowElement) else { return nil }
        return AXWindowMatch(
            rect: CGRect(origin: position, size: size),
            windowNumber: windowNumber,
            cornerRadius: cornerRadius
        )
    }

    private func cgRectForWindowNumber(_ windowNumber: Int, pid: pid_t) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow], CGWindowID(windowNumber)
        ) as? [[String: Any]], let first = info.first else { return nil }
        guard let ownerPID = first[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { return nil }
        guard let boundsDict = first[kCGWindowBounds as String] as? NSDictionary else { return nil }
        var wsRect = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDict, &wsRect), wsRect.width > 40, wsRect.height > 40 else { return nil }
        return wsRect
    }

    // MARK: - Coordinate conversion

    private func convertWindowServerRectToAppKit(_ wsRect: CGRect) -> CGRect {
        let desktop = desktopFrame()
        let y = desktop.maxY - wsRect.maxY
        return CGRect(x: wsRect.minX, y: y, width: wsRect.width, height: wsRect.height)
    }

    private func desktopFrame() -> CGRect {
        var union = CGRect.null
        for screen in NSScreen.screens { union = union.union(screen.frame) }
        return union.isNull ? .zero : union
    }

    // MARK: - AX attribute readers

    private func readCGRectAttribute(_ key: CFString, from element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(axValue, .cgRect, &rect) ? rect : nil
    }

    private func readCGPointAttribute(_ key: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func readCGSizeAttribute(_ key: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private func readBoolAttribute(_ key: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return (value as! Bool)
    }

    private func readIntAttribute(_ key: CFString, from element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value, CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
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
}

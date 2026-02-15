import AppKit

// MARK: - HotkeyCombo

struct HotkeyCombo: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt   // NSEvent.ModifierFlags rawValue

    var displayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyNameForKeyCode(keyCode))
        return parts.joined()
    }
}

private func keyNameForKeyCode(_ keyCode: UInt16) -> String {
    let keyMap: [UInt16: String] = [
        0: "A",  1: "S",  2: "D",  3: "F",  4: "H",  5: "G",  6: "Z",  7: "X",
        8: "C",  9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
       16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
       23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
       30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
       37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
       44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
       51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
      100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
      115: "↖", 116: "⇞", 117: "⌦", 118: "F4", 119: "↘", 120: "F2",
      121: "⇟", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    return keyMap[keyCode] ?? "(\(keyCode))"
}

// MARK: - HotkeyAction

enum HotkeyAction: String, CaseIterable, Codable {
    case toggleEnabled  = "toggleEnabled"
    case openSettings   = "openSettings"
    case increaseDim    = "increaseDim"
    case decreaseDim    = "decreaseDim"
    case toggleBlur     = "toggleBlur"
    case increaseBlur   = "increaseBlur"
    case decreaseBlur   = "decreaseBlur"

    var displayName: String {
        switch self {
        case .toggleEnabled: return "Enable / Disable"
        case .openSettings:  return "Open Settings"
        case .increaseDim:   return "Increase Dim"
        case .decreaseDim:   return "Decrease Dim"
        case .toggleBlur:    return "Toggle Blur"
        case .increaseBlur:  return "Increase Blur"
        case .decreaseBlur:  return "Decrease Blur"
        }
    }
}

// MARK: - HotkeyManager

final class HotkeyManager {
    static let shared = HotkeyManager()

    var shortcuts: [HotkeyAction: HotkeyCombo] = [:]
    var actionHandler: ((HotkeyAction) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    func startMonitoring() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handle(event: event) == true { return nil }
            return event
        }
    }

    func stopMonitoring() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    func update(shortcuts: [HotkeyAction: HotkeyCombo]) {
        self.shortcuts = shortcuts
    }

    @discardableResult
    private func handle(event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        let keyCode = event.keyCode
        for (action, combo) in shortcuts {
            if combo.keyCode == keyCode && combo.modifiers == flags {
                DispatchQueue.main.async { [weak self] in
                    self?.actionHandler?(action)
                }
                return true
            }
        }
        return false
    }
}

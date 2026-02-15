import Foundation
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }

    @Published var dimOpacity: Double {
        didSet { UserDefaults.standard.set(dimOpacity, forKey: "dimOpacity") }
    }

    @Published var isBlurEnabled: Bool {
        didSet { UserDefaults.standard.set(isBlurEnabled, forKey: "blurEnabled") }
    }

    @Published var blurIntensity: Double {
        didSet { UserDefaults.standard.set(blurIntensity, forKey: "blurIntensity") }
    }

    @Published var showStatusBarIcon: Bool {
        didSet { UserDefaults.standard.set(showStatusBarIcon, forKey: "showStatusBarIcon") }
    }

    @Published var shortcuts: [String: HotkeyCombo] {
        didSet {
            if let data = try? JSONEncoder().encode(shortcuts) {
                UserDefaults.standard.set(data, forKey: "shortcuts")
            }
        }
    }

    private init() {
        let ud = UserDefaults.standard
        isEnabled      = ud.object(forKey: "isEnabled")      != nil ? ud.bool(forKey: "isEnabled")         : true
        dimOpacity     = ud.object(forKey: "dimOpacity")     != nil ? ud.double(forKey: "dimOpacity")      : 0.62
        isBlurEnabled  = ud.object(forKey: "blurEnabled")    != nil ? ud.bool(forKey: "blurEnabled")       : false
        blurIntensity  = ud.object(forKey: "blurIntensity")  != nil ? ud.double(forKey: "blurIntensity")   : 1.0
        showStatusBarIcon = ud.object(forKey: "showStatusBarIcon") != nil
            ? ud.bool(forKey: "showStatusBarIcon") : true

        if let data = ud.data(forKey: "shortcuts"),
           let decoded = try? JSONDecoder().decode([String: HotkeyCombo].self, from: data) {
            shortcuts = decoded
        } else {
            shortcuts = [:]
        }
    }
}

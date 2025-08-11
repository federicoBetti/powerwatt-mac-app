import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var refreshIntervalSeconds: Double {
        didSet {
            UserDefaults.standard.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds)
        }
    }

    enum DisplayMode: Int, CaseIterable, Identifiable {
        case netOnly
        case separateInOut

        var id: Int { rawValue }
        var title: String {
            switch self {
            case .netOnly: return "Net Only (IN−OUT)"
            case .separateInOut: return "Separate IN and OUT"
            }
        }
    }

    @Published var displayMode: DisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    enum LabelStyle: Int, CaseIterable, Identifiable {
        case iconAndWatts
        case wattsOnly
        case prefixAndWatts

        var id: Int { rawValue }
        var title: String {
            switch self {
            case .iconAndWatts: return "Icon + Watts"
            case .wattsOnly: return "Watts Only"
            case .prefixAndWatts: return "IN/OUT + Watts"
            }
        }
    }

    @Published var labelStyle: LabelStyle {
        didSet { UserDefaults.standard.set(labelStyle.rawValue, forKey: Keys.labelStyle) }
    }

    @Published var decimalPlaces: Int {
        didSet { UserDefaults.standard.set(decimalPlaces, forKey: Keys.decimalPlaces) }
    }

    @Published var showBatteryPercentInMenu: Bool {
        didSet { UserDefaults.standard.set(showBatteryPercentInMenu, forKey: Keys.showBatteryPercentInMenu) }
    }

    @Published var coloredIndicators: Bool {
        didSet { UserDefaults.standard.set(coloredIndicators, forKey: Keys.coloredIndicators) }
    }

    @Published var smoothingWindowSeconds: Double {
        didSet { UserDefaults.standard.set(smoothingWindowSeconds, forKey: Keys.smoothingWindowSeconds) }
    }



    private init() {
        let saved = UserDefaults.standard.double(forKey: Keys.refreshIntervalSeconds)
        self.refreshIntervalSeconds = saved > 0 ? saved : 2.0

        let displayModeRaw = UserDefaults.standard.integer(forKey: Keys.displayMode)
        self.displayMode = DisplayMode(rawValue: displayModeRaw) ?? .netOnly

        let styleRaw = UserDefaults.standard.integer(forKey: Keys.labelStyle)
        self.labelStyle = LabelStyle(rawValue: styleRaw) ?? .iconAndWatts

        let decimals = UserDefaults.standard.object(forKey: Keys.decimalPlaces) as? Int
        self.decimalPlaces = decimals ?? 1

        self.showBatteryPercentInMenu = UserDefaults.standard.object(forKey: Keys.showBatteryPercentInMenu) as? Bool ?? true
        self.coloredIndicators = UserDefaults.standard.object(forKey: Keys.coloredIndicators) as? Bool ?? true
        let windowSaved = UserDefaults.standard.double(forKey: Keys.smoothingWindowSeconds)
        self.smoothingWindowSeconds = windowSaved >= 0 ? windowSaved : 5.0
    }

    private enum Keys {
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let displayMode = "displayMode"
        static let labelStyle = "labelStyle"
        static let decimalPlaces = "decimalPlaces"
        static let showBatteryPercentInMenu = "showBatteryPercentInMenu"
        static let coloredIndicators = "coloredIndicators"
        static let smoothingWindowSeconds = "smoothingWindowSeconds"

    }
}



import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var refreshIntervalSeconds: Double {
        didSet {
            UserDefaults.standard.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds)
        }
    }

    @Published var telemetryEnabled: Bool {
        didSet { UserDefaults.standard.set(telemetryEnabled, forKey: Keys.telemetryEnabled) }
    }

    @Published var telemetryPromptShown: Bool {
        didSet { UserDefaults.standard.set(telemetryPromptShown, forKey: Keys.telemetryPromptShown) }
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

    // MARK: - Usage Tracking Settings
    
    /// Whether usage tracking is enabled
    @Published var usageTrackingEnabled: Bool {
        didSet { UserDefaults.standard.set(usageTrackingEnabled, forKey: Keys.usageTrackingEnabled) }
    }
    
    /// Sampling interval for usage tracking (2-10 seconds)
    @Published var usageSamplingIntervalSeconds: Double {
        didSet { 
            let clamped = max(2.0, min(10.0, usageSamplingIntervalSeconds))
            UserDefaults.standard.set(clamped, forKey: Keys.usageSamplingIntervalSeconds)
        }
    }
    
    /// Include background (non-app) processes in tracking
    @Published var usageIncludeBackgroundProcesses: Bool {
        didSet { UserDefaults.standard.set(usageIncludeBackgroundProcesses, forKey: Keys.usageIncludeBackgroundProcesses) }
    }
    
    /// Data retention period for usage data
    enum UsageRetentionPeriod: Int, CaseIterable, Identifiable {
        case hours6 = 6
        case hours24 = 24
        case days7 = 168
        
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .hours6: return "6 hours"
            case .hours24: return "24 hours"
            case .days7: return "7 days"
            }
        }
    }
    
    @Published var usageRetentionPeriod: UsageRetentionPeriod {
        didSet { UserDefaults.standard.set(usageRetentionPeriod.rawValue, forKey: Keys.usageRetentionPeriod) }
    }
    
    // MARK: - Energy Impact Coefficient Overrides (for debugging)
    
    @Published var useCustomCoefficients: Bool {
        didSet { UserDefaults.standard.set(useCustomCoefficients, forKey: Keys.useCustomCoefficients) }
    }
    
    @Published var cpuWeight: Double {
        didSet { UserDefaults.standard.set(cpuWeight, forKey: Keys.cpuWeight) }
    }
    
    @Published var wakeupsWeight: Double {
        didSet { UserDefaults.standard.set(wakeupsWeight, forKey: Keys.wakeupsWeight) }
    }
    
    @Published var diskWeight: Double {
        didSet { UserDefaults.standard.set(diskWeight, forKey: Keys.diskWeight) }
    }
    
    @Published var networkWeight: Double {
        didSet { UserDefaults.standard.set(networkWeight, forKey: Keys.networkWeight) }
    }

    private init() {
        let saved = UserDefaults.standard.double(forKey: Keys.refreshIntervalSeconds)
        self.refreshIntervalSeconds = saved > 0 ? saved : 2.0

        self.telemetryEnabled = UserDefaults.standard.bool(forKey: Keys.telemetryEnabled)
        self.telemetryPromptShown = UserDefaults.standard.bool(forKey: Keys.telemetryPromptShown)

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
        
        // Usage tracking settings
        self.usageTrackingEnabled = UserDefaults.standard.object(forKey: Keys.usageTrackingEnabled) as? Bool ?? true
        let samplingInterval = UserDefaults.standard.double(forKey: Keys.usageSamplingIntervalSeconds)
        self.usageSamplingIntervalSeconds = samplingInterval > 0 ? samplingInterval : 5.0
        self.usageIncludeBackgroundProcesses = UserDefaults.standard.bool(forKey: Keys.usageIncludeBackgroundProcesses)
        
        let retentionRaw = UserDefaults.standard.integer(forKey: Keys.usageRetentionPeriod)
        self.usageRetentionPeriod = UsageRetentionPeriod(rawValue: retentionRaw) ?? .hours24
        
        // Coefficient overrides
        self.useCustomCoefficients = UserDefaults.standard.bool(forKey: Keys.useCustomCoefficients)
        self.cpuWeight = UserDefaults.standard.object(forKey: Keys.cpuWeight) as? Double ?? 0.70
        self.wakeupsWeight = UserDefaults.standard.object(forKey: Keys.wakeupsWeight) as? Double ?? 0.10
        self.diskWeight = UserDefaults.standard.object(forKey: Keys.diskWeight) as? Double ?? 0.15
        self.networkWeight = UserDefaults.standard.object(forKey: Keys.networkWeight) as? Double ?? 0.05
    }

    private enum Keys {
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let telemetryEnabled = "telemetryEnabled"
        static let telemetryPromptShown = "telemetryPromptShown"
        static let displayMode = "displayMode"
        static let labelStyle = "labelStyle"
        static let decimalPlaces = "decimalPlaces"
        static let showBatteryPercentInMenu = "showBatteryPercentInMenu"
        static let coloredIndicators = "coloredIndicators"
        static let smoothingWindowSeconds = "smoothingWindowSeconds"
        
        // Usage tracking keys
        static let usageTrackingEnabled = "usageTrackingEnabled"
        static let usageSamplingIntervalSeconds = "usageSamplingIntervalSeconds"
        static let usageIncludeBackgroundProcesses = "usageIncludeBackgroundProcesses"
        static let usageRetentionPeriod = "usageRetentionPeriod"
        
        // Coefficient keys
        static let useCustomCoefficients = "useCustomCoefficients"
        static let cpuWeight = "cpuWeight"
        static let wakeupsWeight = "wakeupsWeight"
        static let diskWeight = "diskWeight"
        static let networkWeight = "networkWeight"
    }
    
    // MARK: - Custom Coefficients Helper
    
    /// Get custom coefficients if enabled
    var customEnergyCoefficients: EnergyCoefficients? {
        guard useCustomCoefficients else { return nil }
        return EnergyCoefficients(
            cpuWeight: cpuWeight,
            wakeupsWeight: wakeupsWeight,
            diskWeight: diskWeight,
            networkWeight: networkWeight
        )
    }
}



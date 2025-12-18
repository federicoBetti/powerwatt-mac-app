//
//  AppPowerSample.swift
//  PowerWatt
//
//  Per-app power allocation sample model
//

import Foundation

/// Represents allocated power for a single app at a point in time
struct AppPowerSample: Identifiable {
    var id: String { "\(timestamp.timeIntervalSince1970)-\(bundleId)" }
    
    /// Timestamp of the sample
    let timestamp: Date
    
    /// Bundle identifier
    let bundleId: String
    
    /// Application name
    let appName: String?
    
    /// Estimated power consumption in watts (nil if total watts unavailable)
    let estimatedWatts: Double?
    
    /// Relative energy impact score (0-1, sum across all apps = 1)
    let relativeScore: Double
    
    /// Whether estimated watts is available
    var hasEstimatedWatts: Bool {
        estimatedWatts != nil
    }
    
    /// Computed energy in mWh for a given interval in seconds
    func energy(forIntervalSeconds dt: Double) -> Double? {
        guard let watts = estimatedWatts else { return nil }
        return watts * (dt / 3600.0) * 1000.0 // Convert to mWh
    }
}

/// Aggregated app power data for a time range
struct AppPowerSummary: Identifiable {
    var id: String { bundleId }
    
    /// Bundle identifier
    let bundleId: String
    
    /// Application name
    let appName: String?
    
    /// Total energy in Wh for the time range
    let energyWh: Double
    
    /// Average power in watts (nil if estimated watts unavailable)
    let avgWatts: Double?
    
    /// Peak power in watts (max of minute averages)
    let peakWatts: Double?
    
    /// Number of active minutes
    let activeMinutes: Int
    
    /// Relative impact score (cumulative)
    let totalRelativeScore: Double
    
    /// Energy in mWh
    var energyMWh: Double {
        energyWh * 1000.0
    }
}

/// Combined power sample joining total power with per-app allocation
struct CombinedPowerSample {
    /// Timestamp
    let timestamp: Date
    
    /// Total system power sample
    let totalPower: TotalPowerSample
    
    /// Per-app power allocations
    let appPower: [AppPowerSample]
    
    /// Energy impact sample (for reference)
    let energyImpact: EnergyImpactSample
    
    /// Whether this sample has valid total watts
    var hasValidTotalWatts: Bool {
        totalPower.hasValidWatts
    }
    
    /// Sum of estimated watts across all apps (should approximately equal totalWatts)
    var sumEstimatedWatts: Double? {
        guard hasValidTotalWatts else { return nil }
        return appPower.compactMap(\.estimatedWatts).reduce(0, +)
    }
}

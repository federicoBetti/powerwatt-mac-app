//
//  TotalPowerSample.swift
//  PowerWatt
//
//  Total system power sample model
//

import Foundation

/// Source of total power measurement
enum TotalPowerSource: Int, Codable {
    case ioRegistrySystemPower = 0
    case batteryDerived = 1
    case unavailable = 2
    
    var description: String {
        switch self {
        case .ioRegistrySystemPower:
            return "System Power (IORegistry)"
        case .batteryDerived:
            return "Battery Derived"
        case .unavailable:
            return "Unavailable"
        }
    }
}

/// Represents a single total system power sample
struct TotalPowerSample {
    /// Timestamp of the sample
    let timestamp: Date
    
    /// Total system power in watts (nil if unavailable)
    let totalWatts: Double?
    
    /// Adapter/charger power in watts (optional)
    let adapterWatts: Double?
    
    /// Whether the system is on AC power
    let isOnAC: Bool
    
    /// Battery percentage (0-100)
    let batteryPercent: Double?
    
    /// Source of the power measurement
    let source: TotalPowerSource
    
    /// Battery voltage in volts (for debugging)
    let batteryVoltage: Double?
    
    /// Battery current in amps (for debugging)
    let batteryCurrent: Double?
    
    /// Whether this sample has valid total watts data
    var hasValidWatts: Bool {
        guard let watts = totalWatts else { return false }
        return watts >= 0 && watts <= 200 // Sanity check
    }
}

extension TotalPowerSample: CustomStringConvertible {
    var description: String {
        let wattsStr = totalWatts.map { String(format: "%.1fW", $0) } ?? "N/A"
        let adapterStr = adapterWatts.map { String(format: "%.1fW", $0) } ?? "N/A"
        let batteryStr = batteryPercent.map { String(format: "%.0f%%", $0) } ?? "N/A"
        return "TotalPowerSample(watts: \(wattsStr), adapter: \(adapterStr), battery: \(batteryStr), AC: \(isOnAC), source: \(source.description))"
    }
}

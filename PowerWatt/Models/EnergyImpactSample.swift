//
//  EnergyImpactSample.swift
//  PowerWatt
//
//  Energy impact score sample model
//

import Foundation

/// Represents per-app energy impact scores for a single sample interval
struct EnergyImpactSample {
    /// Timestamp of the sample
    let timestamp: Date
    
    /// Energy impact scores per app (bundleId -> score)
    /// Scores are normalized to sum to 1.0 when data exists
    let perAppScores: [String: Double]
    
    /// App metadata (bundleId -> name)
    let perAppMeta: [String: String]
    
    /// Total score (should be ~1.0 if normalized)
    var totalScore: Double {
        perAppScores.values.reduce(0, +)
    }
    
    /// Get score for a specific app
    func score(for bundleId: String) -> Double {
        perAppScores[bundleId] ?? 0
    }
    
    /// Get app name for a bundle ID
    func appName(for bundleId: String) -> String? {
        perAppMeta[bundleId]
    }
    
    /// Top N apps by score
    func topApps(n: Int) -> [(bundleId: String, score: Double, name: String?)] {
        perAppScores
            .sorted { $0.value > $1.value }
            .prefix(n)
            .map { (bundleId: $0.key, score: $0.value, name: perAppMeta[$0.key]) }
    }
}

/// Feature shares used to compute energy impact score
struct ProcessFeatureShares {
    let pid: pid_t
    let bundleId: String?
    let appName: String?
    
    /// Proportion of total CPU time used by this process
    let cpuShare: Double
    
    /// Proportion of total wakeups caused by this process
    let wakeupsShare: Double
    
    /// Proportion of total disk I/O by this process
    let diskShare: Double
    
    /// Proportion of total network I/O by this process
    let networkShare: Double
}

/// Energy impact coefficients/weights
struct EnergyCoefficients {
    /// Weight for CPU time contribution
    var cpuWeight: Double = 0.70
    
    /// Weight for wakeups contribution
    var wakeupsWeight: Double = 0.10
    
    /// Weight for disk I/O contribution
    var diskWeight: Double = 0.15
    
    /// Weight for network I/O contribution
    var networkWeight: Double = 0.05
    
    /// Default coefficients (built-in fallback)
    static let `default` = EnergyCoefficients()
    
    /// Validate coefficients sum to 1.0
    var isValid: Bool {
        let sum = cpuWeight + wakeupsWeight + diskWeight + networkWeight
        return abs(sum - 1.0) < 0.001
    }
    
    /// Compute energy impact score from feature shares
    func computeScore(from features: ProcessFeatureShares) -> Double {
        cpuWeight * features.cpuShare +
        wakeupsWeight * features.wakeupsShare +
        diskWeight * features.diskShare +
        networkWeight * features.networkShare
    }
}

extension EnergyCoefficients: CustomStringConvertible {
    var description: String {
        "EnergyCoefficients(cpu: \(cpuWeight), wakeups: \(wakeupsWeight), disk: \(diskWeight), network: \(networkWeight))"
    }
}

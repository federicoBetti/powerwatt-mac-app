//
//  EnergyImpactService.swift
//  PowerWatt
//
//  Service for computing per-app energy impact scores
//

import Foundation
import Combine

/// Service that computes energy impact scores from process metrics
final class EnergyImpactService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var latestSample: EnergyImpactSample?
    @Published private(set) var coefficients: EnergyCoefficients
    
    // MARK: - Private Properties
    
    private let coefficientsLoader = PmEnergyCoefficientsLoader()
    private var sampleSubject = PassthroughSubject<EnergyImpactSample, Never>()
    
    /// Publisher for samples
    var samplePublisher: AnyPublisher<EnergyImpactSample, Never> {
        sampleSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Configuration
    
    /// Custom coefficient overrides (for debugging)
    var customCoefficients: EnergyCoefficients? {
        didSet {
            if let custom = customCoefficients {
                coefficients = custom
            } else {
                coefficients = coefficientsLoader.loadCoefficients()
            }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        self.coefficients = EnergyCoefficients.default
        
        // Load coefficients from system if available
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let loaded = self?.coefficientsLoader.loadCoefficients() ?? .default
            DispatchQueue.main.async {
                self?.coefficients = loaded
            }
        }
    }
    
    // MARK: - Score Computation
    
    /// Compute energy impact scores from process metrics samples
    func computeScores(from processSamples: [ProcessMetricsSample]) -> EnergyImpactSample {
        let timestamp = processSamples.first?.timestamp ?? Date()
        
        // Aggregate by app (bundle ID)
        var appMetrics: [String: (name: String?, cpuTime: Double, wakeups: Int, diskBytes: Int64, netBytes: Int64)] = [:]
        
        for sample in processSamples {
            let key = sample.bundleId ?? "unknown.\(sample.pid)"
            var existing = appMetrics[key] ?? (name: sample.appName, cpuTime: 0, wakeups: 0, diskBytes: 0, netBytes: 0)
            
            existing.cpuTime += sample.cpuTimeDeltaSec
            existing.wakeups += sample.wakeupsDelta
            existing.diskBytes += sample.totalDiskBytes
            existing.netBytes += sample.totalNetworkBytes
            
            if existing.name == nil {
                existing.name = sample.appName
            }
            
            appMetrics[key] = existing
        }
        
        // Compute totals for normalization
        let totalCpuTime = appMetrics.values.map(\.cpuTime).reduce(0, +)
        let totalWakeups = appMetrics.values.map(\.wakeups).reduce(0, +)
        let totalDiskBytes = appMetrics.values.map(\.diskBytes).reduce(0, +)
        let totalNetBytes = appMetrics.values.map(\.netBytes).reduce(0, +)
        
        // Compute feature shares and scores for each app
        var perAppScores: [String: Double] = [:]
        var perAppMeta: [String: String] = [:]
        
        for (bundleId, metrics) in appMetrics {
            // Compute normalized feature shares
            let cpuShare = totalCpuTime > 0 ? metrics.cpuTime / totalCpuTime : 0
            let wakeupsShare = totalWakeups > 0 ? Double(metrics.wakeups) / Double(totalWakeups) : 0
            let diskShare = totalDiskBytes > 0 ? Double(metrics.diskBytes) / Double(totalDiskBytes) : 0
            let netShare = totalNetBytes > 0 ? Double(metrics.netBytes) / Double(totalNetBytes) : 0
            
            // Compute score using coefficients
            let score = coefficients.cpuWeight * cpuShare +
                       coefficients.wakeupsWeight * wakeupsShare +
                       coefficients.diskWeight * diskShare +
                       coefficients.networkWeight * netShare
            
            perAppScores[bundleId] = score
            
            if let name = metrics.name {
                perAppMeta[bundleId] = name
            }
        }
        
        let sample = EnergyImpactSample(
            timestamp: timestamp,
            perAppScores: perAppScores,
            perAppMeta: perAppMeta
        )
        
        DispatchQueue.main.async {
            self.latestSample = sample
        }
        sampleSubject.send(sample)
        
        return sample
    }
    
    /// Compute detailed feature shares for a single process sample
    func computeFeatureShares(
        for sample: ProcessMetricsSample,
        totalCpuTime: Double,
        totalWakeups: Int,
        totalDiskBytes: Int64,
        totalNetBytes: Int64
    ) -> ProcessFeatureShares {
        ProcessFeatureShares(
            pid: sample.pid,
            bundleId: sample.bundleId,
            appName: sample.appName,
            cpuShare: totalCpuTime > 0 ? sample.cpuTimeDeltaSec / totalCpuTime : 0,
            wakeupsShare: totalWakeups > 0 ? Double(sample.wakeupsDelta) / Double(totalWakeups) : 0,
            diskShare: totalDiskBytes > 0 ? Double(sample.totalDiskBytes) / Double(totalDiskBytes) : 0,
            networkShare: totalNetBytes > 0 ? Double(sample.totalNetworkBytes) / Double(totalNetBytes) : 0
        )
    }
    
    // MARK: - Coefficient Management
    
    /// Reload coefficients from system
    func reloadCoefficients() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let loaded = self?.coefficientsLoader.reloadCoefficients() ?? .default
            DispatchQueue.main.async {
                if self?.customCoefficients == nil {
                    self?.coefficients = loaded
                }
            }
        }
    }
    
    /// Whether coefficients were loaded from system
    var coefficientsLoadedFromSystem: Bool {
        coefficientsLoader.loadedFromSystem
    }
}

// MARK: - Convenience Extensions

extension EnergyImpactService {
    /// Get top N apps from latest sample
    func topApps(n: Int = 10) -> [(bundleId: String, score: Double, name: String?)] {
        latestSample?.topApps(n: n) ?? []
    }
    
    /// Get score for a specific app from latest sample
    func score(for bundleId: String) -> Double {
        latestSample?.score(for: bundleId) ?? 0
    }
}

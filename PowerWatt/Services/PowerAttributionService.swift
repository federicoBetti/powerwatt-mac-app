//
//  PowerAttributionService.swift
//  PowerWatt
//
//  Service for attributing system power to individual apps
//

import Foundation
import Combine

/// Service that combines total power with energy impact scores to attribute watts per app
final class PowerAttributionService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var latestCombinedSample: CombinedPowerSample?
    @Published private(set) var latestAppSamples: [AppPowerSample] = []
    @Published private(set) var isRunning: Bool = false
    
    // MARK: - Dependencies
    
    private let totalPowerService: TotalPowerService
    private let processMetricsService: ProcessMetricsService
    private let energyImpactService: EnergyImpactService
    
    // MARK: - Private Properties
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var sampleSubject = PassthroughSubject<CombinedPowerSample, Never>()
    
    /// Publisher for combined samples
    var samplePublisher: AnyPublisher<CombinedPowerSample, Never> {
        sampleSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Configuration
    
    /// Sampling interval in seconds
    var samplingIntervalSeconds: Double = 5.0 {
        didSet {
            if isRunning {
                restartSampling()
            }
        }
    }
    
    // MARK: - Initialization
    
    init(
        totalPowerService: TotalPowerService = TotalPowerService(),
        processMetricsService: ProcessMetricsService = ProcessMetricsService(),
        energyImpactService: EnergyImpactService = EnergyImpactService()
    ) {
        self.totalPowerService = totalPowerService
        self.processMetricsService = processMetricsService
        self.energyImpactService = energyImpactService
    }
    
    // MARK: - Sampling Control
    
    /// Start collecting and attributing power
    func startSampling(intervalSeconds: Double = 5.0) {
        stopSampling()
        
        samplingIntervalSeconds = max(2.0, min(10.0, intervalSeconds))
        isRunning = true
        
        // Start underlying services
        totalPowerService.startSampling(intervalSeconds: samplingIntervalSeconds)
        processMetricsService.startSampling(intervalSeconds: samplingIntervalSeconds)
        
        // Set up a timer to combine samples
        timer = Timer.scheduledTimer(withTimeInterval: samplingIntervalSeconds, repeats: true) { [weak self] _ in
            self?.collectCombinedSample()
        }
        RunLoop.main.add(timer!, forMode: .common)
        
        // Wait for initial data before first combined sample
        DispatchQueue.main.asyncAfter(deadline: .now() + samplingIntervalSeconds + 0.5) { [weak self] in
            self?.collectCombinedSample()
        }
    }
    
    /// Stop all sampling
    func stopSampling() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        
        totalPowerService.stopSampling()
        processMetricsService.stopSampling()
    }
    
    /// Restart sampling with current interval
    private func restartSampling() {
        let interval = samplingIntervalSeconds
        stopSampling()
        startSampling(intervalSeconds: interval)
    }
    
    // MARK: - Sample Collection
    
    /// Collect and combine samples from all services
    private func collectCombinedSample() {
        // Get latest data from services
        guard let totalPower = totalPowerService.latestSample else { return }
        let processSamples = processMetricsService.latestSamples
        
        // Compute energy impact scores (if we have process data); otherwise emit total-only samples
        let energyImpact: EnergyImpactSample
        if processSamples.isEmpty {
            energyImpact = EnergyImpactSample(timestamp: totalPower.timestamp, perAppScores: [:], perAppMeta: [:])
        } else {
            energyImpact = energyImpactService.computeScores(from: processSamples)
        }
        
        // Attribute power to apps
        let appPower = attributePower(
            totalPower: totalPower,
            energyImpact: energyImpact
        )
        
        let combined = CombinedPowerSample(
            timestamp: totalPower.timestamp,
            totalPower: totalPower,
            appPower: appPower,
            energyImpact: energyImpact
        )
        
        DispatchQueue.main.async {
            self.latestCombinedSample = combined
            self.latestAppSamples = appPower
        }
        
        sampleSubject.send(combined)
    }
    
    /// Attribute total power to individual apps based on energy impact scores
    private func attributePower(
        totalPower: TotalPowerSample,
        energyImpact: EnergyImpactSample
    ) -> [AppPowerSample] {
        let timestamp = totalPower.timestamp
        let totalScore = energyImpact.totalScore
        
        return energyImpact.perAppScores.map { (bundleId, score) in
            // Normalize score
            let normalizedScore = totalScore > 0 ? score / totalScore : 0
            
            // Calculate estimated watts if total watts available
            let estimatedWatts: Double?
            if let totalWatts = totalPower.totalWatts, totalPower.hasValidWatts {
                estimatedWatts = totalWatts * normalizedScore
            } else {
                estimatedWatts = nil
            }
            
            return AppPowerSample(
                timestamp: timestamp,
                bundleId: bundleId,
                appName: energyImpact.appName(for: bundleId),
                estimatedWatts: estimatedWatts,
                relativeScore: normalizedScore
            )
        }.sorted { $0.relativeScore > $1.relativeScore }
    }
    
    // MARK: - Service Access
    
    /// Access to underlying total power service
    var totalPower: TotalPowerService { totalPowerService }
    
    /// Access to underlying process metrics service
    var processMetrics: ProcessMetricsService { processMetricsService }
    
    /// Access to underlying energy impact service
    var energyImpact: EnergyImpactService { energyImpactService }
    
    /// Configure whether to include background processes
    func setIncludeBackgroundProcesses(_ include: Bool) {
        processMetricsService.includeBackgroundProcesses = include
    }
}

// MARK: - Convenience Extensions

extension PowerAttributionService {
    /// Current total system watts
    var currentTotalWatts: Double? {
        latestCombinedSample?.totalPower.totalWatts
    }
    
    /// Whether current sample has valid total watts
    var hasValidTotalWatts: Bool {
        latestCombinedSample?.hasValidTotalWatts ?? false
    }
    
    /// Top N apps by power consumption
    func topApps(n: Int = 10) -> [AppPowerSample] {
        Array(latestAppSamples.prefix(n))
    }
    
    /// Get power sample for a specific app
    func appPower(for bundleId: String) -> AppPowerSample? {
        latestAppSamples.first { $0.bundleId == bundleId }
    }
    
    /// Sum of estimated watts across all apps (should ≈ totalWatts)
    var sumEstimatedWatts: Double? {
        guard hasValidTotalWatts else { return nil }
        return latestAppSamples.compactMap(\.estimatedWatts).reduce(0, +)
    }
}

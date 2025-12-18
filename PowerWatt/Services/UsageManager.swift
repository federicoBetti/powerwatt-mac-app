//
//  UsageManager.swift
//  PowerWatt
//
//  Central manager for usage tracking
//

import Foundation
import Combine

/// Central manager that coordinates all usage tracking services
final class UsageManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = UsageManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var hasValidTotalWatts: Bool = false
    @Published private(set) var currentTotalWatts: Double?
    @Published private(set) var topApps: [AppPowerSample] = []
    
    // MARK: - Services
    
    let powerAttributionService: PowerAttributionService
    let aggregator: MinuteBucketAggregator
    let store: UsageStore
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var cleanupTimer: Timer?
    
    // MARK: - Initialization
    
    private init() {
        self.store = UsageStore.shared
        self.powerAttributionService = PowerAttributionService()
        self.aggregator = MinuteBucketAggregator(store: store)
        
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Subscribe aggregator to power attribution samples
        aggregator.subscribe(to: powerAttributionService)
        
        // Observe settings changes
        AppSettings.shared.$usageTrackingEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled && !(self?.isRunning ?? false) {
                    self?.start()
                } else if !enabled && (self?.isRunning ?? false) {
                    self?.stop()
                }
            }
            .store(in: &cancellables)
        
        AppSettings.shared.$usageSamplingIntervalSeconds
            .removeDuplicates()
            .sink { [weak self] interval in
                guard let self = self, self.isRunning else { return }
                self.powerAttributionService.samplingIntervalSeconds = interval
                self.aggregator.sampleIntervalSeconds = interval
            }
            .store(in: &cancellables)
        
        AppSettings.shared.$usageIncludeBackgroundProcesses
            .removeDuplicates()
            .sink { [weak self] include in
                self?.powerAttributionService.setIncludeBackgroundProcesses(include)
            }
            .store(in: &cancellables)
        
        AppSettings.shared.$usageRetentionPeriod
            .removeDuplicates()
            .sink { [weak self] period in
                switch period {
                case .hours6:
                    self?.store.retentionPeriod = .hours6
                case .hours24:
                    self?.store.retentionPeriod = .hours24
                case .days7:
                    self?.store.retentionPeriod = .days7
                }
                self?.store.performCleanup()
            }
            .store(in: &cancellables)
        
        // Apply custom coefficients if enabled
        AppSettings.shared.$useCustomCoefficients
            .combineLatest(
                AppSettings.shared.$cpuWeight,
                AppSettings.shared.$wakeupsWeight,
                AppSettings.shared.$diskWeight,
                AppSettings.shared.$networkWeight
            )
            .sink { [weak self] useCustom, cpu, wakeups, disk, network in
                if useCustom {
                    let coeffs = EnergyCoefficients(
                        cpuWeight: cpu,
                        wakeupsWeight: wakeups,
                        diskWeight: disk,
                        networkWeight: network
                    )
                    self?.powerAttributionService.energyImpact.customCoefficients = coeffs
                } else {
                    self?.powerAttributionService.energyImpact.customCoefficients = nil
                }
            }
            .store(in: &cancellables)
        
        // Observe attribution service output
        powerAttributionService.$latestCombinedSample
            .compactMap { $0 }
            .sink { [weak self] sample in
                DispatchQueue.main.async {
                    self?.hasValidTotalWatts = sample.hasValidTotalWatts
                    self?.currentTotalWatts = sample.totalPower.totalWatts
                    self?.topApps = Array(sample.appPower.prefix(10))
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Control
    
    /// Start usage tracking
    func start() {
        guard !isRunning else { return }
        
        let interval = AppSettings.shared.usageSamplingIntervalSeconds
        aggregator.sampleIntervalSeconds = interval
        powerAttributionService.setIncludeBackgroundProcesses(AppSettings.shared.usageIncludeBackgroundProcesses)
        
        powerAttributionService.startSampling(intervalSeconds: interval)
        isRunning = true
        
        // Schedule daily cleanup
        scheduleCleanup()
        
        // Initial cleanup
        store.performCleanup()
    }
    
    /// Stop usage tracking
    func stop() {
        guard isRunning else { return }
        
        // Flush any pending data
        aggregator.forceFlush()
        
        powerAttributionService.stopSampling()
        isRunning = false
        
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
    
    /// Restart with current settings
    func restart() {
        stop()
        start()
    }
    
    // MARK: - Cleanup
    
    private func scheduleCleanup() {
        cleanupTimer?.invalidate()
        
        // Run cleanup every hour
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.store.performCleanup()
        }
        RunLoop.main.add(cleanupTimer!, forMode: .common)
    }
    
    // MARK: - App Lifecycle
    
    /// Called when app is about to terminate
    func handleAppTermination() {
        aggregator.forceFlush()
    }
}

// MARK: - Convenience Extensions

extension UsageManager {
    /// Get current power source description
    var powerSourceDescription: String {
        guard let sample = powerAttributionService.latestCombinedSample else {
            return "Unknown"
        }
        return sample.totalPower.source.description
    }
    
    /// Whether total watts data is currently available
    var isTotalWattsAvailable: Bool {
        powerAttributionService.hasValidTotalWatts
    }
}

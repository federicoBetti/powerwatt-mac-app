//
//  MinuteBucketAggregator.swift
//  PowerWatt
//
//  Aggregates samples into minute buckets and flushes to storage
//

import Foundation
import Combine

/// Aggregates power samples into minute buckets for efficient storage
final class MinuteBucketAggregator: ObservableObject {
    
    // MARK: - Types
    
    /// In-memory accumulator for current minute
    private struct MinuteAccumulator {
        var totalMWh: Double = 0
        var totalWattsSum: Double = 0
        var totalWattsSampleCount: Int = 0
        var isOnAC: Bool = false
        var batteryPercent: Double?
        
        var totalWattsAvg: Double? {
            totalWattsSampleCount > 0 ? totalWattsSum / Double(totalWattsSampleCount) : nil
        }
    }
    
    /// In-memory accumulator for per-app data
    private struct AppAccumulator {
        var mWh: Double = 0
        var wattsSum: Double = 0
        var wattsSampleCount: Int = 0
        var relativeImpactSum: Double = 0
        var appName: String?
        
        var wattsAvg: Double? {
            wattsSampleCount > 0 ? wattsSum / Double(wattsSampleCount) : nil
        }
    }
    
    // MARK: - Properties
    
    private let store: UsageStore
    private var currentMinuteTs: Int64 = 0
    private var minuteAccumulator = MinuteAccumulator()
    private var appAccumulators: [String: AppAccumulator] = [:]
    private let lock = NSLock()
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Sample interval in seconds (for energy calculations)
    var sampleIntervalSeconds: Double = 5.0
    
    // MARK: - Initialization
    
    init(store: UsageStore = .shared) {
        self.store = store
        self.currentMinuteTs = Self.floorToMinute(Date())
    }
    
    // MARK: - Sample Processing
    
    /// Process a combined power sample
    func processSample(_ sample: CombinedPowerSample) {
        lock.lock()
        defer { lock.unlock() }
        
        let sampleMinuteTs = Self.floorToMinute(sample.timestamp)
        
        // Check if we need to flush the previous minute
        if sampleMinuteTs != currentMinuteTs && currentMinuteTs > 0 {
            flushCurrentMinute()
            currentMinuteTs = sampleMinuteTs
            resetAccumulators()
        } else if currentMinuteTs == 0 {
            currentMinuteTs = sampleMinuteTs
        }
        
        // Accumulate total power
        accumulateTotalPower(from: sample.totalPower)
        
        // Accumulate per-app power
        for appSample in sample.appPower {
            accumulateAppPower(from: appSample)
        }
    }
    
    /// Process just a total power sample (if no per-app data available)
    func processTotalPowerSample(_ sample: TotalPowerSample) {
        lock.lock()
        defer { lock.unlock() }
        
        let sampleMinuteTs = Self.floorToMinute(sample.timestamp)
        
        if sampleMinuteTs != currentMinuteTs && currentMinuteTs > 0 {
            flushCurrentMinute()
            currentMinuteTs = sampleMinuteTs
            resetAccumulators()
        } else if currentMinuteTs == 0 {
            currentMinuteTs = sampleMinuteTs
        }
        
        accumulateTotalPower(from: sample)
    }
    
    // MARK: - Accumulation
    
    private func accumulateTotalPower(from sample: TotalPowerSample) {
        // Calculate energy for this sample interval
        if let watts = sample.totalWatts, sample.hasValidWatts {
            let mWh = watts * (sampleIntervalSeconds / 3600.0) * 1000.0
            minuteAccumulator.totalMWh += mWh
            minuteAccumulator.totalWattsSum += watts
            minuteAccumulator.totalWattsSampleCount += 1
        }
        
        // Update latest state values
        minuteAccumulator.isOnAC = sample.isOnAC
        minuteAccumulator.batteryPercent = sample.batteryPercent
    }
    
    private func accumulateAppPower(from sample: AppPowerSample) {
        var accumulator = appAccumulators[sample.bundleId] ?? AppAccumulator()
        
        // Calculate energy for this sample interval
        if let watts = sample.estimatedWatts {
            let mWh = watts * (sampleIntervalSeconds / 3600.0) * 1000.0
            accumulator.mWh += mWh
            accumulator.wattsSum += watts
            accumulator.wattsSampleCount += 1
        }
        
        // Always accumulate relative score
        accumulator.relativeImpactSum += sample.relativeScore
        
        // Update app name if available
        if accumulator.appName == nil, let name = sample.appName {
            accumulator.appName = name
        }
        
        appAccumulators[sample.bundleId] = accumulator
    }
    
    // MARK: - Flushing
    
    /// Flush current minute's data to storage
    func flushCurrentMinute() {
        // This should be called with lock held
        guard currentMinuteTs > 0 else { return }
        
        // Flush total power bucket
        store.upsertMinuteBucket(
            tsMinute: currentMinuteTs,
            totalMWh: minuteAccumulator.totalMWh,
            totalWattsAvg: minuteAccumulator.totalWattsAvg,
            isOnAC: minuteAccumulator.isOnAC,
            batteryPercent: minuteAccumulator.batteryPercent
        )
        
        // Flush per-app buckets
        for (bundleId, accumulator) in appAccumulators {
            store.upsertAppMinuteBucket(
                tsMinute: currentMinuteTs,
                bundleId: bundleId,
                appName: accumulator.appName,
                mWh: accumulator.mWh,
                wattsAvg: accumulator.wattsAvg,
                relativeImpact: accumulator.relativeImpactSum
            )
        }
    }
    
    /// Force flush (e.g., when app is terminating)
    func forceFlush() {
        lock.lock()
        flushCurrentMinute()
        lock.unlock()
    }
    
    // MARK: - Reset
    
    private func resetAccumulators() {
        minuteAccumulator = MinuteAccumulator()
        appAccumulators.removeAll(keepingCapacity: true)
    }
    
    // MARK: - Utilities
    
    /// Floor a date to the start of its minute
    static func floorToMinute(_ date: Date) -> Int64 {
        let ts = Int64(date.timeIntervalSince1970)
        return ts - (ts % 60)
    }
    
    /// Convert a minute timestamp to Date
    static func dateFromMinuteTs(_ ts: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ts))
    }
}

// MARK: - Publisher Integration

extension MinuteBucketAggregator {
    /// Subscribe to a PowerAttributionService's sample publisher
    func subscribe(to attributionService: PowerAttributionService) {
        attributionService.samplePublisher
            .sink { [weak self] sample in
                self?.processSample(sample)
            }
            .store(in: &cancellables)
    }
    
    /// Subscribe to a TotalPowerService's sample publisher (fallback when no per-app data)
    func subscribe(to totalPowerService: TotalPowerService) {
        totalPowerService.samplePublisher
            .sink { [weak self] sample in
                self?.processTotalPowerSample(sample)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Time Range Helpers

extension MinuteBucketAggregator {
    /// Time range for last N minutes
    static func timeRange(lastMinutes: Int) -> (start: Int64, end: Int64) {
        let now = Int64(Date().timeIntervalSince1970)
        let end = now - (now % 60) + 60 // End of current minute
        let start = end - Int64(lastMinutes * 60)
        return (start, end)
    }
    
    /// Time range for last N hours
    static func timeRange(lastHours: Int) -> (start: Int64, end: Int64) {
        return timeRange(lastMinutes: lastHours * 60)
    }
    
    /// Predefined time ranges
    enum TimeRange: CaseIterable {
        case minutes15
        case hour1
        case hours6
        case hours24
        
        var minutes: Int {
            switch self {
            case .minutes15: return 15
            case .hour1: return 60
            case .hours6: return 360
            case .hours24: return 1440
            }
        }
        
        var title: String {
            switch self {
            case .minutes15: return "15m"
            case .hour1: return "1h"
            case .hours6: return "6h"
            case .hours24: return "24h"
            }
        }
        
        func getRange() -> (start: Int64, end: Int64) {
            MinuteBucketAggregator.timeRange(lastMinutes: minutes)
        }
    }
}

//
//  UsageViewModel.swift
//  PowerWatt
//
//  ViewModel for Usage view
//

import Foundation
import Combine
import AppKit

/// ViewModel for the Usage view
@MainActor
final class UsageViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var selectedTimeRange: MinuteBucketAggregator.TimeRange = .hour1
    @Published var showEstimatedWatts: Bool = true
    @Published var includeBackgroundProcesses: Bool = false
    
    @Published private(set) var minuteBuckets: [UsageStore.MinuteBucket] = []
    @Published private(set) var appBuckets: [UsageStore.AppMinuteBucket] = []
    @Published private(set) var appSummaries: [AppPowerSummary] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var hasWattsData: Bool = false
    
    @Published var selectedApp: AppPowerSummary?
    @Published var selectedAppBuckets: [UsageStore.AppMinuteBucket] = []
    
    // MARK: - Chart Data
    
    @Published var totalPowerChartData: [ChartDataPoint] = []
    @Published var appStackedChartData: [AppStackedChartData] = []
    @Published var topAppsForChart: [String] = []
    
    // MARK: - Dependencies
    
    private let store: UsageStore
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    /// Number of top apps to show in charts
    var topAppsCount: Int = 8
    
    // MARK: - Initialization
    
    init(store: UsageStore = .shared) {
        self.store = store
        
        // Observe time range changes
        $selectedTimeRange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.refreshData() }
            }
            .store(in: &cancellables)
        
        // Recompute charts when switching between Watts/Relative
        $showEstimatedWatts
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateAppStackedChartData()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    
    /// Refresh all data for current time range
    func refreshData() async {
        isLoading = true
        
        let range = selectedTimeRange.getRange()
        
        // Load minute buckets
        await withCheckedContinuation { continuation in
            store.getMinuteBuckets(from: range.start, to: range.end) { [weak self] buckets in
                Task { @MainActor in
                    self?.minuteBuckets = buckets
                    self?.hasWattsData = buckets.contains { $0.totalWattsAvg != nil }
                    self?.updateTotalPowerChartData(range: range)
                    continuation.resume()
                }
            }
        }
        
        // Load app buckets
        await withCheckedContinuation { continuation in
            store.getAppMinuteBuckets(from: range.start, to: range.end) { [weak self] buckets in
                Task { @MainActor in
                    self?.appBuckets = buckets
                    self?.updateAppStackedChartData()
                    continuation.resume()
                }
            }
        }
        
        // Load app summaries
        await withCheckedContinuation { continuation in
            store.getAppSummaries(from: range.start, to: range.end) { [weak self] summaries in
                Task { @MainActor in
                    self?.appSummaries = summaries
                    continuation.resume()
                }
            }
        }
        
        isLoading = false
    }
    
    /// Load detailed data for a specific app
    func loadAppDetail(bundleId: String) async {
        let range = selectedTimeRange.getRange()
        
        await withCheckedContinuation { continuation in
            store.getAppMinuteBuckets(bundleId: bundleId, from: range.start, to: range.end) { [weak self] buckets in
                Task { @MainActor in
                    self?.selectedAppBuckets = buckets
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Chart Data Preparation
    
    private func updateTotalPowerChartData() {
        let range = selectedTimeRange.getRange()
        updateTotalPowerChartData(range: range)
    }
    
    private func updateTotalPowerChartData(range: (start: Int64, end: Int64)) {
        // Keep the "No data yet" state until we have at least one stored bucket.
        guard !minuteBuckets.isEmpty else {
            totalPowerChartData = []
            return
        }
        
        let bucketsByMinute = Dictionary(uniqueKeysWithValues: minuteBuckets.map { ($0.tsMinute, $0) })
        let start = range.start - (range.start % 60)
        // `range.end` is "end of current minute", i.e. start-of-next-minute. Exclude the future minute.
        let end = max(start, (range.end - (range.end % 60)) - 60)
        
        var points: [ChartDataPoint] = []
        points.reserveCapacity(Int((end - start) / 60) + 1)
        
        var ts = start
        while ts <= end {
            if let bucket = bucketsByMinute[ts] {
                points.append(ChartDataPoint(
                timestamp: Date(timeIntervalSince1970: TimeInterval(bucket.tsMinute)),
                value: bucket.totalWattsAvg ?? 0,
                hasData: bucket.totalWattsAvg != nil
                ))
            } else {
                points.append(ChartDataPoint(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(ts)),
                    value: 0,
                    hasData: false
                ))
        }
            
            ts += 60
        }
        
        totalPowerChartData = points
    }
    
    private func updateAppStackedChartData() {
        let usingWatts = showEstimatedWatts && hasWattsData
        // Get top apps by total mWh
        var appTotals: [String: (name: String?, mWh: Double)] = [:]
        
        for bucket in appBuckets {
            var entry = appTotals[bucket.bundleId] ?? (name: bucket.appName, mWh: 0)
            // Rank by energy when watts are available, otherwise rank by relative impact.
            entry.mWh += usingWatts ? bucket.mWh : bucket.relativeImpactSum
            if entry.name == nil { entry.name = bucket.appName }
            appTotals[bucket.bundleId] = entry
        }
        
        let sortedApps = appTotals.sorted { $0.value.mWh > $1.value.mWh }
        topAppsForChart = Array(sortedApps.prefix(topAppsCount).map { $0.key })
        
        // Group buckets by minute
        var bucketsByMinute: [Int64: [String: Double]] = [:]
        
        for bucket in appBuckets {
            var minuteData = bucketsByMinute[bucket.tsMinute] ?? [:]
            
            if topAppsForChart.contains(bucket.bundleId) {
                if usingWatts {
                minuteData[bucket.bundleId] = bucket.mWh
                } else {
                    // Average normalized share for this minute (0..1-ish)
                    let avgShare = bucket.samplesCount > 0 ? (bucket.relativeImpactSum / Double(bucket.samplesCount)) : 0
                    minuteData[bucket.bundleId] = avgShare
                }
            } else {
                if usingWatts {
                minuteData["Others", default: 0] += bucket.mWh
                } else {
                    let avgShare = bucket.samplesCount > 0 ? (bucket.relativeImpactSum / Double(bucket.samplesCount)) : 0
                    minuteData["Others", default: 0] += avgShare
                }
            }
            
            bucketsByMinute[bucket.tsMinute] = minuteData
        }
        
        // Convert to chart data
        appStackedChartData = bucketsByMinute.sorted { $0.key < $1.key }.map { (minute, data) in
            AppStackedChartData(
                timestamp: Date(timeIntervalSince1970: TimeInterval(minute)),
                values: data
            )
        }
    }
    
    // MARK: - Auto Refresh
    
    /// Start auto-refreshing data
    func startAutoRefresh(intervalSeconds: Double = 30) {
        stopAutoRefresh()
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { await self?.refreshData() }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
        
        // Initial load
        Task { await refreshData() }
    }
    
    /// Stop auto-refreshing
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - App Actions
    
    /// Reveal app in Finder
    func revealInFinder(bundleId: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        NSWorkspace.shared.selectFile(appURL.path, inFileViewerRootedAtPath: "")
    }
    
    /// Quit app gracefully
    func quitApp(bundleId: String) {
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
            app.terminate()
        }
    }
    
    /// Get icon for app
    func getAppIcon(bundleId: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

// MARK: - Chart Data Types

/// Data point for line charts
struct ChartDataPoint: Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let value: Double
    let hasData: Bool
}

/// Data for stacked area/bar charts
struct AppStackedChartData: Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let values: [String: Double]  // bundleId/category -> value
}

// MARK: - App Name Helpers

extension UsageViewModel {
    /// Get display name for an app
    func appDisplayName(for bundleId: String) -> String {
        // Check summaries first
        if let summary = appSummaries.first(where: { $0.bundleId == bundleId }) {
            return summary.appName ?? bundleId
        }
        
        // Try to get from running apps
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            return app.localizedName ?? bundleId
        }
        
        // Fall back to bundle ID
        return bundleId
    }
}

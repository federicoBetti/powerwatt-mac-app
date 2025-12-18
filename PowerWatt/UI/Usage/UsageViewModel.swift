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
                    self?.updateTotalPowerChartData()
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
        totalPowerChartData = minuteBuckets.map { bucket in
            ChartDataPoint(
                timestamp: Date(timeIntervalSince1970: TimeInterval(bucket.tsMinute)),
                value: bucket.totalWattsAvg ?? 0,
                hasData: bucket.totalWattsAvg != nil
            )
        }
    }
    
    private func updateAppStackedChartData() {
        // Get top apps by total mWh
        var appTotals: [String: (name: String?, mWh: Double)] = [:]
        
        for bucket in appBuckets {
            var entry = appTotals[bucket.bundleId] ?? (name: bucket.appName, mWh: 0)
            entry.mWh += bucket.mWh
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
                minuteData[bucket.bundleId] = bucket.mWh
            } else {
                minuteData["Others", default: 0] += bucket.mWh
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

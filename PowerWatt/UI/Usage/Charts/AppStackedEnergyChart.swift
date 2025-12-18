//
//  AppStackedEnergyChart.swift
//  PowerWatt
//
//  Stacked area chart showing per-app energy over time
//

import SwiftUI
import Charts

/// Stacked area chart for per-app energy consumption
struct AppStackedEnergyChart: View {
    let data: [AppStackedChartData]
    let topApps: [String]
    let showWatts: Bool
    let getAppName: (String) -> String
    
    @State private var selectedPoint: AppStackedChartData?
    
    // Color palette for apps
    private let appColors: [Color] = [
        .blue, .green, .orange, .purple, .pink,
        .cyan, .indigo, .mint, .teal, .red
    ]
    
    var body: some View {
        if data.isEmpty {
            emptyView
        } else {
            VStack(spacing: 8) {
                chartView
                legendView
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Chart View
    
    private var chartView: some View {
        Chart {
            ForEach(Array(allCategories.enumerated()), id: \.element) { index, category in
                ForEach(data) { point in
                    let value = point.values[category] ?? 0
                    
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value(showWatts ? "Energy" : "Relative", value)
                    )
                    .foregroundStyle(by: .value("App", displayName(for: category)))
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartForegroundStyleScale(domain: allCategories.map { displayName(for: $0) }) { name in
            if let index = allCategories.firstIndex(where: { displayName(for: $0) == name }) {
                return appColors[index % appColors.count]
            }
            return Color.gray
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(showWatts ? formatEnergy(v) : formatRelative(v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .padding(.horizontal, 4)
    }
    
    // MARK: - Legend View
    
    private var legendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(allCategories.enumerated()), id: \.element) { index, category in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appColors[index % appColors.count])
                            .frame(width: 8, height: 8)
                        Text(displayName(for: category))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Per-app data unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("App Sandbox prevents reading other processes.\nDisable sandbox in Xcode to enable this feature.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Helpers
    
    /// All categories including "Others"
    private var allCategories: [String] {
        var categories = topApps
        
        // Check if there's "Others" data
        let hasOthers = data.contains { $0.values["Others"] != nil && ($0.values["Others"] ?? 0) > 0 }
        if hasOthers {
            categories.append("Others")
        }
        
        return categories
    }
    
    /// Get display name for a category
    private func displayName(for category: String) -> String {
        if category == "Others" {
            return "Others"
        }
        return getAppName(category)
    }
    
    /// Format energy value
    private func formatEnergy(_ mWh: Double) -> String {
        if mWh >= 1000 {
            return String(format: "%.1f Wh", mWh / 1000)
        } else if mWh >= 1 {
            return String(format: "%.0f mWh", mWh)
        } else {
            return String(format: "%.2f mWh", mWh)
        }
    }
    
    private func formatRelative(_ share: Double) -> String {
        let pct = max(0, min(1, share)) * 100
        if pct >= 10 {
            return String(format: "%.0f%%", pct)
        }
        return String(format: "%.1f%%", pct)
    }
}

// MARK: - Preview

#Preview {
    let sampleData = (0..<60).map { i in
        AppStackedChartData(
            timestamp: Date().addingTimeInterval(TimeInterval(-60 * (60 - i))),
            values: [
                "com.apple.Safari": Double.random(in: 0.5...2),
                "com.apple.mail": Double.random(in: 0.2...0.8),
                "com.apple.Xcode": Double.random(in: 1...5),
                "Others": Double.random(in: 0.5...1.5)
            ]
        )
    }
    
    return AppStackedEnergyChart(
        data: sampleData,
        topApps: ["com.apple.Safari", "com.apple.mail", "com.apple.Xcode"],
        showWatts: true,
        getAppName: { bundleId in
            switch bundleId {
            case "com.apple.Safari": return "Safari"
            case "com.apple.mail": return "Mail"
            case "com.apple.Xcode": return "Xcode"
            default: return bundleId
            }
        }
    )
    .frame(width: 500, height: 250)
    .padding()
}

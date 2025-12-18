//
//  AppDetailView.swift
//  PowerWatt
//
//  Detail view for a specific app's power usage
//

import SwiftUI
import Charts

/// Detail view showing power usage for a specific app
struct AppDetailView: View {
    let app: AppPowerSummary
    let buckets: [UsageStore.AppMinuteBucket]
    let viewModel: UsageViewModel
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Summary cards
                    summaryCardsView
                    
                    // Power chart
                    powerChartSection
                    
                    // Energy chart
                    energyChartSection
                }
                .padding()
            }
        }
        .frame(width: 550, height: 600)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            if let icon = viewModel.getAppIcon(bundleId: app.bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 48))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.appName ?? app.bundleId)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(app.bundleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Summary Cards
    
    private var summaryCardsView: some View {
        HStack(spacing: 16) {
            summaryCard(
                title: "Energy",
                value: formatEnergy(app.energyWh),
                icon: "bolt.fill",
                color: .yellow
            )
            
            if let avgWatts = app.avgWatts {
                summaryCard(
                    title: "Avg Power",
                    value: String(format: "%.1f W", avgWatts),
                    icon: "gauge.with.dots.needle.50percent",
                    color: .blue
                )
            }
            
            if let peakWatts = app.peakWatts {
                summaryCard(
                    title: "Peak Power",
                    value: String(format: "%.1f W", peakWatts),
                    icon: "arrow.up.forward",
                    color: .red
                )
            }
            
            summaryCard(
                title: "Active Time",
                value: formatMinutes(app.activeMinutes),
                icon: "clock.fill",
                color: .green
            )
        }
    }
    
    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Power Chart Section
    
    private var powerChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Power Over Time")
                .font(.headline)
            
            if buckets.isEmpty {
                emptyChartView
            } else {
                powerChart
            }
        }
    }
    
    private var powerChart: some View {
        Chart {
            ForEach(buckets, id: \.tsMinute) { bucket in
                if let watts = bucket.wattsAvg {
                    LineMark(
                        x: .value("Time", Date(timeIntervalSince1970: TimeInterval(bucket.tsMinute))),
                        y: .value("Watts", watts)
                    )
                    .foregroundStyle(Color.blue.gradient)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Time", Date(timeIntervalSince1970: TimeInterval(bucket.tsMinute))),
                        y: .value("Watts", watts)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
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
                    if let watts = value.as(Double.self) {
                        Text(String(format: "%.1fW", watts))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 180)
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Energy Chart Section
    
    private var energyChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Energy Consumption")
                .font(.headline)
            
            if buckets.isEmpty {
                emptyChartView
            } else {
                energyChart
            }
        }
    }
    
    private var energyChart: some View {
        Chart {
            ForEach(buckets, id: \.tsMinute) { bucket in
                BarMark(
                    x: .value("Time", Date(timeIntervalSince1970: TimeInterval(bucket.tsMinute))),
                    y: .value("Energy", bucket.mWh)
                )
                .foregroundStyle(Color.green.gradient)
            }
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
                    if let mWh = value.as(Double.self) {
                        Text(formatSmallEnergy(mWh))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 150)
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Empty View
    
    private var emptyChartView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No data available")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Formatting
    
    private func formatEnergy(_ wh: Double) -> String {
        if wh >= 1 {
            return String(format: "%.2f Wh", wh)
        } else {
            return String(format: "%.1f mWh", wh * 1000)
        }
    }
    
    private func formatSmallEnergy(_ mWh: Double) -> String {
        if mWh >= 100 {
            return String(format: "%.0f", mWh)
        } else if mWh >= 1 {
            return String(format: "%.1f", mWh)
        } else {
            return String(format: "%.2f", mWh)
        }
    }
    
    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return String(format: "%dh %dm", hours, mins)
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleApp = AppPowerSummary(
        bundleId: "com.apple.Safari",
        appName: "Safari",
        energyWh: 1.25,
        avgWatts: 12.5,
        peakWatts: 28.3,
        activeMinutes: 45,
        totalRelativeScore: 0.35
    )
    
    let sampleBuckets = (0..<60).map { i in
        UsageStore.AppMinuteBucket(
            tsMinute: Int64(Date().timeIntervalSince1970) - Int64((60 - i) * 60),
            bundleId: "com.apple.Safari",
            appName: "Safari",
            mWh: Double.random(in: 0.5...3),
            wattsAvg: Double.random(in: 5...25),
            relativeImpactSum: Double.random(in: 0.1...0.4),
            samplesCount: 12
        )
    }
    
    return AppDetailView(
        app: sampleApp,
        buckets: sampleBuckets,
        viewModel: UsageViewModel()
    )
}

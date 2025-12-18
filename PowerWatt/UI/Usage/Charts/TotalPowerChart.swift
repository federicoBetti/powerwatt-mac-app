//
//  TotalPowerChart.swift
//  PowerWatt
//
//  Line chart showing total system power over time
//

import SwiftUI
import Charts

/// Line chart displaying total system power consumption
struct TotalPowerChart: View {
    let data: [ChartDataPoint]
    let hasWattsData: Bool
    let isOnAC: Bool
    
    var body: some View {
        if data.isEmpty {
            emptyView
        } else if hasWattsData {
            chartView
        } else {
            unavailableView
        }
    }
    
    // MARK: - Chart View
    
    private var chartView: some View {
        Chart {
            ForEach(data) { point in
                if point.hasData {
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Watts", point.value)
                    )
                    .foregroundStyle(Color.blue.gradient)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        yStart: .value("Baseline", yAxisDomain.lowerBound),
                        yEnd: .value("Watts", point.value)
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
            
            // Show gaps where data is unavailable
            ForEach(gapSegments, id: \.start) { segment in
                RectangleMark(
                    xStart: .value("Start", segment.start),
                    xEnd: .value("End", segment.end),
                    yStart: nil,
                    yEnd: nil
                )
                .foregroundStyle(Color.gray.opacity(0.1))
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
                        Text("\(Int(watts))W")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: yAxisDomain)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
    
    // MARK: - Empty/Unavailable Views
    
    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No data yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Start collecting usage data to see power trends")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var unavailableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.slash")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Total watts unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(unavailableMessage)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var unavailableMessage: String {
        if isOnAC {
            return "Total system watts are often unavailable while plugged in/charging. Showing relative metrics instead."
        }
        
        return "System power data not available. Showing relative metrics instead."
    }
    
    // MARK: - Helpers
    
    /// Calculate Y-axis domain
    private var yAxisDomain: ClosedRange<Double> {
        let validData = data.filter(\.hasData)
        guard !validData.isEmpty else { return 0...100 }
        
        let minVal = validData.map(\.value).min() ?? 0
        let maxVal = validData.map(\.value).max() ?? 100
        
        let padding = max((maxVal - minVal) * 0.1, 5)
        return max(0, minVal - padding)...(maxVal + padding)
    }
    
    /// Find segments where data is unavailable (gaps)
    private var gapSegments: [(start: Date, end: Date)] {
        var gaps: [(start: Date, end: Date)] = []
        var gapStart: Date?
        
        for point in data {
            if !point.hasData {
                if gapStart == nil {
                    gapStart = point.timestamp
                }
            } else {
                if let start = gapStart {
                    gaps.append((start: start, end: point.timestamp))
                    gapStart = nil
                }
            }
        }
        
        // Handle trailing gap
        if let start = gapStart, let lastPoint = data.last {
            gaps.append((start: start, end: lastPoint.timestamp))
        }
        
        return gaps
    }
}

// MARK: - Preview

#Preview {
    let sampleData = (0..<60).map { i in
        ChartDataPoint(
            timestamp: Date().addingTimeInterval(TimeInterval(-60 * (60 - i))),
            value: Double.random(in: 15...45),
            hasData: i % 10 != 0
        )
    }
    
    return TotalPowerChart(data: sampleData, hasWattsData: true, isOnAC: true)
        .frame(width: 500, height: 200)
        .padding()
}

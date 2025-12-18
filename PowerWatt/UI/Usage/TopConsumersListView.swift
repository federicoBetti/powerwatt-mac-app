//
//  TopConsumersListView.swift
//  PowerWatt
//
//  Table view showing top energy consumers
//

import SwiftUI

/// List view showing top energy consuming apps
struct TopConsumersListView: View {
    let summaries: [AppPowerSummary]
    let showWatts: Bool
    let viewModel: UsageViewModel
    let onSelect: (AppPowerSummary) -> Void
    
    @State private var hoveredApp: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerRow
            
            Divider()
            
            // App rows
            ForEach(summaries.prefix(15)) { summary in
                appRow(for: summary)
                    .onTapGesture {
                        onSelect(summary)
                    }
                    .onHover { hovering in
                        hoveredApp = hovering ? summary.bundleId : nil
                    }
                
                if summary.id != summaries.prefix(15).last?.id {
                    Divider()
                }
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Header Row
    
    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("App")
                .frame(minWidth: 200, alignment: .leading)
            
            Spacer()
            
            Text("Energy")
                .frame(width: 80, alignment: .trailing)
            
            if showWatts {
                Text("Avg")
                    .frame(width: 60, alignment: .trailing)
                
                Text("Peak")
                    .frame(width: 60, alignment: .trailing)
            }
            
            Text("Minutes")
                .frame(width: 60, alignment: .trailing)
            
            // Space for actions
            Spacer()
                .frame(width: 60)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }
    
    // MARK: - App Row
    
    private func appRow(for summary: AppPowerSummary) -> some View {
        HStack(spacing: 8) {
            // App icon and name
            HStack(spacing: 8) {
                if let icon = viewModel.getAppIcon(bundleId: summary.bundleId) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app")
                        .frame(width: 20, height: 20)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.appName ?? summary.bundleId)
                        .lineLimit(1)
                    Text(summary.bundleId)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 200, alignment: .leading)
            
            Spacer()
            
            // Energy
            Text(formatEnergy(summary.energyWh))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            
            if showWatts {
                // Average watts
                if let avg = summary.avgWatts {
                    Text(String(format: "%.1fW", avg))
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                } else {
                    Text("--")
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
                
                // Peak watts
                if let peak = summary.peakWatts {
                    Text(String(format: "%.1fW", peak))
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                } else {
                    Text("--")
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
            
            // Active minutes
            Text("\(summary.activeMinutes)")
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
            
            // Actions
            HStack(spacing: 4) {
                Button {
                    viewModel.revealInFinder(bundleId: summary.bundleId)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                
                Button {
                    viewModel.quitApp(bundleId: summary.bundleId)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .help("Quit App")
            }
            .frame(width: 60)
            .opacity(hoveredApp == summary.bundleId ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hoveredApp == summary.bundleId ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
    
    // MARK: - Helpers
    
    private func formatEnergy(_ wh: Double) -> String {
        if wh >= 1 {
            return String(format: "%.2f Wh", wh)
        } else {
            return String(format: "%.1f mWh", wh * 1000)
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleSummaries = [
        AppPowerSummary(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            energyWh: 1.25,
            avgWatts: 12.5,
            peakWatts: 28.3,
            activeMinutes: 45,
            totalRelativeScore: 0.35
        ),
        AppPowerSummary(
            bundleId: "com.apple.Xcode",
            appName: "Xcode",
            energyWh: 2.8,
            avgWatts: 25.1,
            peakWatts: 55.0,
            activeMinutes: 60,
            totalRelativeScore: 0.45
        ),
        AppPowerSummary(
            bundleId: "com.apple.mail",
            appName: "Mail",
            energyWh: 0.15,
            avgWatts: 2.1,
            peakWatts: 5.5,
            activeMinutes: 30,
            totalRelativeScore: 0.08
        )
    ]
    
    return TopConsumersListView(
        summaries: sampleSummaries,
        showWatts: true,
        viewModel: UsageViewModel(),
        onSelect: { _ in }
    )
    .frame(width: 600)
    .padding()
}

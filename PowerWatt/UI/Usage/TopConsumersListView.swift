//
//  TopConsumersListView.swift
//  PowerWatt
//
//  Table view showing top energy consumers
//

import SwiftUI

/// List view showing top energy consuming apps
struct TopConsumersListView: View {
    fileprivate enum SortColumn: Equatable {
        case app
        case energyOrRelative
        case avgWatts
        case peakWatts
        case minutes
    }
    
    fileprivate enum SortDirection: Equatable {
        case ascending
        case descending
        
        mutating func toggle() {
            self = (self == .ascending) ? .descending : .ascending
        }
    }
    
    let summaries: [AppPowerSummary]
    let showWatts: Bool
    let viewModel: UsageViewModel
    let onSelect: (AppPowerSummary) -> Void
    
    @State private var hoveredApp: String?
    @State private var sortColumn: SortColumn = .energyOrRelative
    @State private var sortDirection: SortDirection = .descending
    
    var body: some View {
        let totalRelative = summaries.map(\.totalRelativeScore).reduce(0, +)
        let visibleSummaries = Array(sortedSummaries(totalRelative: totalRelative).prefix(15))
        
        VStack(spacing: 0) {
            // Header
            headerRow
            
            Divider()
            
            // App rows
            ForEach(visibleSummaries) { summary in
                appRow(for: summary, totalRelative: totalRelative)
                    .onTapGesture {
                        onSelect(summary)
                    }
                    .onHover { hovering in
                        hoveredApp = hovering ? summary.bundleId : nil
                    }
                
                if summary.id != visibleSummaries.last?.id {
                    Divider()
                }
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: showWatts) { _, newValue in
            // If watts columns disappear, fall back to the visible Energy/Relative column.
            if !newValue, (sortColumn == .avgWatts || sortColumn == .peakWatts) {
                sortColumn = .energyOrRelative
                sortDirection = .descending
            }
        }
    }
    
    // MARK: - Header Row
    
    private var headerRow: some View {
        HStack(spacing: 8) {
            SortableHeader(
                title: "App",
                column: .app,
                width: nil,
                minWidth: 200,
                alignment: .leading,
                infoText: nil,
                sortColumn: $sortColumn,
                sortDirection: $sortDirection
            )
            
            Spacer()
            
            SortableHeader(
                title: showWatts ? "Energy" : "Relative",
                column: .energyOrRelative,
                width: 80,
                minWidth: nil,
                alignment: .trailing,
                infoText: showWatts ? energyInfoText : relativeInfoText,
                sortColumn: $sortColumn,
                sortDirection: $sortDirection
            )
            
            if showWatts {
                SortableHeader(
                    title: "Avg",
                    column: .avgWatts,
                    width: 60,
                    minWidth: nil,
                    alignment: .trailing,
                    infoText: wattsInfoText,
                    sortColumn: $sortColumn,
                    sortDirection: $sortDirection
                )
                
                SortableHeader(
                    title: "Peak",
                    column: .peakWatts,
                    width: 60,
                    minWidth: nil,
                    alignment: .trailing,
                    infoText: peakWattsInfoText,
                    sortColumn: $sortColumn,
                    sortDirection: $sortDirection
                )
            }
            
            SortableHeader(
                title: "Minutes",
                column: .minutes,
                width: 60,
                minWidth: nil,
                alignment: .trailing,
                infoText: minutesInfoText,
                sortColumn: $sortColumn,
                sortDirection: $sortDirection
            )
            
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
    
    private func appRow(for summary: AppPowerSummary, totalRelative: Double) -> some View {
        let relativePct = totalRelative > 0 ? (summary.totalRelativeScore / totalRelative) * 100 : 0
        
        return HStack(spacing: 8) {
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
            
            // Energy or Relative
            Text(showWatts ? formatEnergy(summary.energyWh) : formatRelative(relativePct))
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
    
    private func sortedSummaries(totalRelative: Double) -> [AppPowerSummary] {
        summaries.sorted { lhs, rhs in
            compare(lhs: lhs, rhs: rhs, totalRelative: totalRelative)
        }
    }
    
    private func compare(lhs: AppPowerSummary, rhs: AppPowerSummary, totalRelative: Double) -> Bool {
        switch sortColumn {
        case .app:
            let leftName = (lhs.appName ?? lhs.bundleId).lowercased()
            let rightName = (rhs.appName ?? rhs.bundleId).lowercased()
            if leftName != rightName {
                return sortDirection == .ascending ? (leftName < rightName) : (leftName > rightName)
            }
            return sortDirection == .ascending ? (lhs.bundleId.lowercased() < rhs.bundleId.lowercased()) : (lhs.bundleId.lowercased() > rhs.bundleId.lowercased())
            
        case .energyOrRelative:
            let left = showWatts ? lhs.energyWh : lhs.totalRelativeScore
            let right = showWatts ? rhs.energyWh : rhs.totalRelativeScore
            if left != right {
                return sortDirection == .ascending ? (left < right) : (left > right)
            }
            // Tie-breakers for stable-ish ordering.
            if lhs.activeMinutes != rhs.activeMinutes {
                return sortDirection == .ascending ? (lhs.activeMinutes < rhs.activeMinutes) : (lhs.activeMinutes > rhs.activeMinutes)
            }
            return lhs.bundleId.lowercased() < rhs.bundleId.lowercased()
            
        case .avgWatts:
            return compareOptionalNumeric(
                lhs: lhs.avgWatts,
                rhs: rhs.avgWatts,
                fallback: { lhs.bundleId.lowercased() < rhs.bundleId.lowercased() }
            )
            
        case .peakWatts:
            return compareOptionalNumeric(
                lhs: lhs.peakWatts,
                rhs: rhs.peakWatts,
                fallback: { lhs.bundleId.lowercased() < rhs.bundleId.lowercased() }
            )
            
        case .minutes:
            if lhs.activeMinutes != rhs.activeMinutes {
                return sortDirection == .ascending ? (lhs.activeMinutes < rhs.activeMinutes) : (lhs.activeMinutes > rhs.activeMinutes)
            }
            return lhs.bundleId.lowercased() < rhs.bundleId.lowercased()
        }
    }
    
    private func compareOptionalNumeric(
        lhs: Double?,
        rhs: Double?,
        fallback: () -> Bool
    ) -> Bool {
        switch (lhs, rhs) {
        case let (l?, r?):
            if l != r {
                return sortDirection == .ascending ? (l < r) : (l > r)
            }
            return fallback()
        case (nil, nil):
            return fallback()
        case (nil, _?):
            // Keep nil values last (regardless of direction).
            return false
        case (_?, nil):
            return true
        }
    }
    
    private var energyInfoText: String {
        """
        Energy is the total energy used during the selected range.
        
        - Wh / mWh are energy units (accumulated over time)
        - 1 Wh = 1000 mWh
        - Energy (Wh) = Average Power (W) × Time (hours)
        
        Example: 2 W for 30 minutes → 1 Wh (1000 mWh).
        """
    }
    
    private var wattsInfoText: String {
        """
        Watts (W) are a measure of power: how fast energy is being used right now.
        
        “Avg” is the app’s average estimated power (W) across its active minutes in the selected range.
        """
    }
    
    private var peakWattsInfoText: String {
        """
        “Peak” is the highest per-minute average power (W) observed for the app in the selected range.
        """
    }
    
    private var relativeInfoText: String {
        """
        Relative is an Activity Monitor-style “energy impact” score.
        
        It’s unitless (not watts) and is useful when system watts aren’t available. Higher means more impact compared to other apps in the selected range.
        """
    }
    
    private var minutesInfoText: String {
        """
        Minutes is how many distinct minutes the app had recorded activity in the selected range.
        """
    }
    
    private func formatEnergy(_ wh: Double) -> String {
        if wh >= 1 {
            return String(format: "%.2f Wh", wh)
        } else {
            return String(format: "%.1f mWh", wh * 1000)
        }
    }
    
    private func formatRelative(_ pct: Double) -> String {
        if pct >= 10 {
            return String(format: "%.0f%%", pct)
        }
        return String(format: "%.1f%%", pct)
    }
}

// MARK: - Sortable Header

private struct SortableHeader: View {
    let title: String
    let column: TopConsumersListView.SortColumn
    let width: CGFloat?
    let minWidth: CGFloat?
    let alignment: Alignment
    let infoText: String?
    
    @Binding var sortColumn: TopConsumersListView.SortColumn
    @Binding var sortDirection: TopConsumersListView.SortDirection
    
    @State private var showingInfo = false
    
    var body: some View {
        HStack(spacing: 4) {
            Button {
                if sortColumn == column {
                    sortDirection.toggle()
                } else {
                    sortColumn = column
                    // Default direction: app ascending; numeric columns descending.
                    sortDirection = (column == .app) ? .ascending : .descending
                }
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                    if sortColumn == column {
                        Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                            .imageScale(.small)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            
            if let infoText {
                Button {
                    showingInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("What does \(title) mean?")
                .popover(isPresented: $showingInfo) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(.headline)
                        Text(infoText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(width: 320)
                }
            }
        }
        .applyHeaderFrame(width: width, minWidth: minWidth, alignment: alignment)
    }
}

private extension View {
    func applyHeaderFrame(width: CGFloat?, minWidth: CGFloat?, alignment: Alignment) -> some View {
        var view = AnyView(self)
        if let minWidth {
            view = AnyView(view.frame(minWidth: minWidth, alignment: alignment))
        }
        if let width {
            view = AnyView(view.frame(width: width, alignment: alignment))
        }
        return view
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

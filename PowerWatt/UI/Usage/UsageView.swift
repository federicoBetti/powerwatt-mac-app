//
//  UsageView.swift
//  PowerWatt
//
//  Main Usage view with charts and top consumers
//

import SwiftUI
import Charts

/// Main view for power usage tracking
struct UsageView: View {
    @StateObject private var viewModel = UsageViewModel()
    @EnvironmentObject var telemetryManager: TelemetryManager
    
    @State private var showingAppDetail = false
    @State private var showInfoTooltip = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top bar with controls
                topBar
                
                if viewModel.isLoading && viewModel.minuteBuckets.isEmpty {
                    loadingView
                } else {
                    // Section 1: Total power chart
                    totalPowerSection
                    
                    // Section 2: Per-app energy chart
                    perAppEnergySection
                    
                    // Section 3: Top consumers list
                    topConsumersSection
                }
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear {
            viewModel.startAutoRefresh()
            telemetryManager.capture(event: "view_opened", properties: ["view_name": "usage"])
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
        .sheet(isPresented: $showingAppDetail) {
            if let app = viewModel.selectedApp {
                AppDetailView(
                    app: app,
                    buckets: viewModel.selectedAppBuckets,
                    viewModel: viewModel
                )
            }
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            // Time range selector
            HStack(spacing: 8) {
                Text("Range")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
                
                Picker("", selection: $viewModel.selectedTimeRange) {
                    ForEach(MinuteBucketAggregator.TimeRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }
            
            Spacer()
            
            // Info button
            Button {
                showInfoTooltip.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showInfoTooltip) {
                infoPopover
            }
            
            // Watts toggle (only if data available)
            if viewModel.hasWattsData {
                Toggle("Show Watts", isOn: $viewModel.showEstimatedWatts)
                    .toggleStyle(.switch)
                    .labelsHidden()
                
                Text(viewModel.showEstimatedWatts ? "Watts" : "Relative")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Info Popover
    
    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About Power Usage")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Total Watts: Measured or derived from battery sensors (may be unavailable while charging)")
                } icon: {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                }
                
                Label {
                    Text("Per-App Watts: Estimated allocation based on CPU, disk, and memory usage")
                } icon: {
                    Image(systemName: "chart.pie.fill")
                        .foregroundStyle(.blue)
                }
                
                Label {
                    Text("Relative Score: Activity Monitor-style energy impact")
                } icon: {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption)
            
            Divider()
            
            Text("Per-app watts are estimates based on CPU time, wakeups, and disk I/O. They are proportionally allocated from the total system power when available (often unavailable on AC while charging).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 320)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading usage data...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    // MARK: - Total Power Section
    
    private var totalPowerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Total System Power")
                    .font(.headline)
                
                Spacer()
                
                if !viewModel.totalPowerChartData.isEmpty && !viewModel.hasWattsData {
                    Label("Unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            TotalPowerChart(
                data: viewModel.totalPowerChartData,
                hasWattsData: viewModel.hasWattsData,
                isOnAC: viewModel.isOnAC
            )
            .frame(height: 180)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    // MARK: - Per-App Energy Section
    
    private var perAppEnergySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((viewModel.showEstimatedWatts && viewModel.hasWattsData) ? "Energy by App" : "Relative Impact by App")
                .font(.headline)
            
            AppStackedEnergyChart(
                data: viewModel.appStackedChartData,
                topApps: viewModel.topAppsForChart,
                showWatts: viewModel.showEstimatedWatts && viewModel.hasWattsData,
                getAppName: { viewModel.appDisplayName(for: $0) }
            )
            .frame(height: 200)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    // MARK: - Top Consumers Section
    
    private var topConsumersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Consumers")
                .font(.headline)
            
            if viewModel.appSummaries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("Per-app tracking requires disabling App Sandbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                TopConsumersListView(
                    summaries: viewModel.appSummaries,
                    showWatts: viewModel.showEstimatedWatts && viewModel.hasWattsData,
                    viewModel: viewModel,
                    onSelect: { summary in
                        viewModel.selectedApp = summary
                        Task {
                            await viewModel.loadAppDetail(bundleId: summary.bundleId)
                            showingAppDetail = true
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    UsageView()
        .environmentObject(TelemetryManager.shared)
        .frame(width: 600, height: 800)
}

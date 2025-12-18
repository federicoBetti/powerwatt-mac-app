import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var powerService: BatteryPowerService
    @EnvironmentObject var updaterManager: UpdaterManager
    @EnvironmentObject var usageManager: UsageManager
    @EnvironmentObject var telemetryManager: TelemetryManager
    
    @State private var showCoefficientsSheet = false
    
    private enum Layout {
        static let sliderWidth: CGFloat = 240
        static let valueWidth: CGFloat = 56
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Refresh every") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.refreshIntervalSeconds, in: 1...60, step: 1)
                            .frame(width: Layout.sliderWidth)
                        Text("\(Int(settings.refreshIntervalSeconds)) s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: Layout.valueWidth, alignment: .trailing)
                    }
                }
                .onChange(of: settings.refreshIntervalSeconds) { _, newValue in
                    powerService.startPolling(intervalSeconds: newValue)
                }

                Toggle(isOn: Binding<Bool>(
                    get: { LoginItemManager.isEnabled },
                    set: { newValue in
                        do {
                            if newValue {
                                try LoginItemManager.enable()
                            } else {
                                try LoginItemManager.disable()
                            }
                            telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "open_at_login", "new_value_bucketed": newValue ? "on" : "off"])
                            telemetryManager.capture(event: "feature_used", properties: ["feature_name": "open_at_login", "context": newValue ? "enabled" : "disabled"])
                        } catch {
                            let nsError = error as NSError
                            telemetryManager.capture(event: "error_nonfatal", properties: ["error_domain": nsError.domain, "error_code": nsError.code, "context": "open_at_login"])
                        }
                    }
                )) {
                    Text("Open at Login")
                }
            } header: {
                Text("General")
            }

            Section {
                Picker("Display mode", selection: $settings.displayMode) {
                    ForEach(AppSettings.DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .onChange(of: settings.displayMode) { _, newValue in
                    telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "display_mode", "new_value_bucketed": newValue.title])
                }
                Picker("Label style", selection: $settings.labelStyle) {
                    ForEach(AppSettings.LabelStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .onChange(of: settings.labelStyle) { _, newValue in
                    telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "label_style", "new_value_bucketed": newValue.title])
                }

                LabeledContent("Decimal places") {
                    Stepper(value: $settings.decimalPlaces, in: 0...2) {
                        Text("\(settings.decimalPlaces)")
                            .monospacedDigit()
                            .frame(width: 20, alignment: .trailing)
                    }
                }
                .onChange(of: settings.decimalPlaces) { _, newValue in
                    telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "decimal_places", "new_value_bucketed": "\(newValue)"])
                }

                Toggle("Colored indicators", isOn: $settings.coloredIndicators)
                    .onChange(of: settings.coloredIndicators) { _, newValue in
                        telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "colored_indicators", "new_value_bucketed": newValue ? "on" : "off"])
                    }
                Toggle("Show battery percent in menu", isOn: $settings.showBatteryPercentInMenu)
                    .onChange(of: settings.showBatteryPercentInMenu) { _, newValue in
                        telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "show_battery_percent", "new_value_bucketed": newValue ? "on" : "off"])
                    }

            } header: {
                Text("Menu Bar")
            }
            
            Section {
                Toggle("Enable usage tracking", isOn: $settings.usageTrackingEnabled)
                    .onChange(of: settings.usageTrackingEnabled) { _, newValue in
                        telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "usage_tracking_enabled", "new_value_bucketed": newValue ? "on" : "off"])
                        if newValue {
                            usageManager.start()
                        } else {
                            usageManager.stop()
                        }
                    }
                
                if settings.usageTrackingEnabled {
                    LabeledContent("Sampling interval") {
                        HStack(spacing: 10) {
                            Slider(value: $settings.usageSamplingIntervalSeconds, in: 2...10, step: 1)
                                .frame(width: Layout.sliderWidth)
                            Text("\(Int(settings.usageSamplingIntervalSeconds)) s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: Layout.valueWidth, alignment: .trailing)
                        }
                    }
                    .onChange(of: settings.usageSamplingIntervalSeconds) { _, newValue in
                        telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "usage_sampling_interval", "new_value_bucketed": "\(Int(newValue))"])
                    }
                    
                    Picker("Data retention", selection: $settings.usageRetentionPeriod) {
                        ForEach(AppSettings.UsageRetentionPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .onChange(of: settings.usageRetentionPeriod) { _, newValue in
                        telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "usage_retention_period", "new_value_bucketed": newValue.title])
                    }
                    
                    Toggle("Include background processes", isOn: $settings.usageIncludeBackgroundProcesses)
                        .onChange(of: settings.usageIncludeBackgroundProcesses) { _, newValue in
                            telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "usage_include_background", "new_value_bucketed": newValue ? "on" : "off"])
                        }
                    
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(usageManager.isRunning ? .green : .red)
                                .font(.caption2)
                            Text(usageManager.isRunning ? "Running" : "Stopped")
                        }
                    }
                }
            } header: {
                Text("Usage Tracking")
            } footer: {
                Text("Tracks per-app energy usage over time. All data is stored locally.")
            }

            Section {
                Toggle("Automatically check for updates", isOn: Binding(get: {
                    updaterManager.automaticallyChecksForUpdates
                }, set: { newValue in
                    updaterManager.automaticallyChecksForUpdates = newValue
                    telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "auto_check_updates", "new_value_bucketed": newValue ? "on" : "off"])
                }))
            } header: {
                Text("Updates")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Updates are installed via Sparkle from the official appcast.")
                    Text("For updates to work, PowerWatt must be installed in /Applications (not run from the DMG).")
                }
            }

            Section {
                Toggle("Share anonymous usage stats", isOn: Binding(get: {
                    settings.telemetryEnabled
                }, set: { newValue in
                    telemetryManager.setEnabled(newValue)
                }))
                Button("Learn more") {
                    telemetryManager.openPrivacyPage()
                }
                .buttonStyle(.link)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Anonymous usage stats are optional and help prioritize improvements. Off by default.")
            }

            Section {
                LabeledContent("Smoothing window") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.smoothingWindowSeconds, in: 0...30, step: 1)
                            .frame(width: Layout.sliderWidth)
                        Text(settings.smoothingWindowSeconds == 0 ? "Off" : "\(Int(settings.smoothingWindowSeconds)) s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: Layout.valueWidth, alignment: .trailing)
                    }
                }
                .onChange(of: settings.smoothingWindowSeconds) { _, newValue in
                    let bucket = newValue == 0 ? "off" : "\(Int(newValue))"
                    telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "smoothing_window_seconds", "new_value_bucketed": bucket])
                }
                
                if let capacity = powerService.batteryCapacityWh {
                    LabeledContent("Battery capacity") {
                        HStack(spacing: 8) {
                            Text(String(format: "%.1f Wh", capacity))
                                .monospacedDigit()
                            Button(action: {
                                // Show info about battery capacity
                                let alert = NSAlert()
                                alert.messageText = "Battery Capacity"
                                alert.informativeText = "This shows your Mac's total battery capacity in Watt-hours (Wh). This is the maximum energy your battery can store when fully charged. A typical MacBook Pro has between 58-100 Wh depending on the model."
                                alert.alertStyle = .informational
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                            }) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("More information about battery capacity")
                        }
                    }
                }
                
                // Energy coefficients debugging
                Button("Configure Energy Weights…") {
                    showCoefficientsSheet = true
                }
                .buttonStyle(.link)
            } header: {
                Text("Advanced")
            } footer: {
                Text("Averages power readings over a short window to reduce flicker.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 440)
        .onAppear {
            telemetryManager.capture(event: "view_opened", properties: ["view_name": "preferences"])
        }
        .sheet(isPresented: $showCoefficientsSheet) {
            EnergyCoefficientsSheet()
                .environmentObject(settings)
        }
    }
}

// MARK: - Energy Coefficients Sheet

private struct EnergyCoefficientsSheet: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Energy Impact Weights")
                .font(.headline)
            
            Text("These weights determine how CPU, wakeups, disk, and network activity contribute to the energy impact score. The sum should equal 1.0.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Toggle("Use custom weights", isOn: $settings.useCustomCoefficients)
            
            if settings.useCustomCoefficients {
                VStack(spacing: 12) {
                    weightSlider(label: "CPU", value: $settings.cpuWeight)
                    weightSlider(label: "Wakeups", value: $settings.wakeupsWeight)
                    weightSlider(label: "Disk I/O", value: $settings.diskWeight)
                    weightSlider(label: "Network", value: $settings.networkWeight)
                }
                .padding()
                .background(Color(.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                let sum = settings.cpuWeight + settings.wakeupsWeight + settings.diskWeight + settings.networkWeight
                HStack {
                    Text("Sum:")
                    Text(String(format: "%.2f", sum))
                        .monospacedDigit()
                        .foregroundStyle(abs(sum - 1.0) < 0.01 ? .green : .red)
                }
                .font(.caption)
                
                Button("Reset to Defaults") {
                    settings.cpuWeight = 0.70
                    settings.wakeupsWeight = 0.10
                    settings.diskWeight = 0.15
                    settings.networkWeight = 0.05
                }
                .font(.caption)
            }
            
            Divider()
            
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(width: 350)
    }
    
    private func weightSlider(label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .frame(width: 70, alignment: .leading)
            Slider(value: value, in: 0...1, step: 0.05)
            Text(String(format: "%.2f", value.wrappedValue))
                .monospacedDigit()
                .frame(width: 40)
        }
    }
}

#Preview {
    PreferencesView()
        .environmentObject(AppSettings.shared)
        .environmentObject(BatteryPowerService())
        .environmentObject(UpdaterManager())
        .environmentObject(UsageManager.shared)
        .environmentObject(TelemetryManager.shared)
}



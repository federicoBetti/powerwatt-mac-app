import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var powerService: BatteryPowerService
    @EnvironmentObject var updaterManager: UpdaterManager
    @EnvironmentObject var telemetryManager: TelemetryManager

    var body: some View {
        Form {
            Section("General") {
                HStack {
                    Text("Refresh every")
                    Slider(value: $settings.refreshIntervalSeconds, in: 1...60, step: 1)
                        .frame(maxWidth: 240)
                    Text("\(Int(settings.refreshIntervalSeconds)) s").monospacedDigit()
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
            }

            Section("Menu Bar") {
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

                Stepper(value: $settings.decimalPlaces, in: 0...2) {
                    Text("Decimal places: \(settings.decimalPlaces)")
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

            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(get: {
                    updaterManager.automaticallyChecksForUpdates
                }, set: { newValue in
                    updaterManager.automaticallyChecksForUpdates = newValue
                    telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "auto_check_updates", "new_value_bucketed": newValue ? "on" : "off"])
                }))
                Text("Updates are installed via Sparkle from the official appcast.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("For updates to work, PowerWatt must be installed in /Applications (not run from the DMG).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle("Share anonymous usage stats", isOn: Binding(get: {
                    settings.telemetryEnabled
                }, set: { newValue in
                    telemetryManager.setEnabled(newValue)
                }))
                Button("Learn more") {
                    telemetryManager.openPrivacyPage()
                }
                .buttonStyle(.link)
                Text("Anonymous usage stats are optional and help prioritize improvements. Off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced") {
                HStack {
                    Text("Smoothing window")
                    Slider(value: $settings.smoothingWindowSeconds, in: 0...30, step: 1)
                        .frame(maxWidth: 240)
                    Text(settings.smoothingWindowSeconds == 0 ? "Off" : "\(Int(settings.smoothingWindowSeconds)) s")
                        .monospacedDigit()
                }
                .onChange(of: settings.smoothingWindowSeconds) { _, newValue in
                    let bucket = newValue == 0 ? "off" : "\(Int(newValue))"
                    telemetryManager.capture(event: "setting_changed", properties: ["setting_name": "smoothing_window_seconds", "new_value_bucketed": bucket])
                }
                Text("Averages power readings over a short window to reduce flicker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let capacity = powerService.batteryCapacityWh {
                    HStack {
                        Text("Battery capacity")
                            .foregroundStyle(.secondary)
                        Spacer()
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
        }
        .padding(16)
        .frame(minHeight: 400)
        .onAppear {
            telemetryManager.capture(event: "view_opened", properties: ["view_name": "preferences"])
        }
    }
}

#Preview {
    PreferencesView()
        .environmentObject(AppSettings.shared)
        .environmentObject(BatteryPowerService())
        .environmentObject(UpdaterManager())
}



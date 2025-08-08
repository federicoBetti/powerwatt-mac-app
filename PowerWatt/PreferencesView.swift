import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var powerService: BatteryPowerService

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
                        if newValue { _ = try? LoginItemManager.enable() } else { _ = try? LoginItemManager.disable() }
                    }
                )) {
                    Text("Open at Login")
                }
            }

            Section("Menu Bar") {
                Picker("Label style", selection: $settings.labelStyle) {
                    ForEach(AppSettings.LabelStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                Stepper(value: $settings.decimalPlaces, in: 0...2) {
                    Text("Decimal places: \(settings.decimalPlaces)")
                }

                Toggle("Colored indicators", isOn: $settings.coloredIndicators)
                Toggle("Show battery percent in menu", isOn: $settings.showBatteryPercentInMenu)
                Toggle("Show both IN and OUT when charging", isOn: $settings.showBothWhenCharging)
            }

            Section("Advanced") {
                HStack {
                    Text("Smoothing window")
                    Slider(value: $settings.smoothingWindowSeconds, in: 0...30, step: 1)
                        .frame(maxWidth: 240)
                    Text(settings.smoothingWindowSeconds == 0 ? "Off" : "\(Int(settings.smoothingWindowSeconds)) s")
                        .monospacedDigit()
                }
                Text("Averages power readings over a short window to reduce flicker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

#Preview {
    PreferencesView()
        .environmentObject(AppSettings.shared)
        .environmentObject(BatteryPowerService())
}



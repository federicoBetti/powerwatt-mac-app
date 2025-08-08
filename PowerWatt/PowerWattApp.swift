//
//  PowerWattApp.swift
//  PowerWatt
//
//  Created by federico betti on 08/08/25.
//

import SwiftUI
import AppKit
import ServiceManagement

@main
struct PowerWattApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var powerService = BatteryPowerService()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(settings)
                .environmentObject(powerService)
        } label: {
            MenuBarLabelView()
                .environmentObject(powerService)
                .environmentObject(settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .environmentObject(settings)
                .environmentObject(powerService)
                .frame(width: 420)
        }
    }
}

private struct MenuBarLabelView: View {
    @EnvironmentObject var powerService: BatteryPowerService
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 4) {
            labelContent
            if settings.showBatteryPercentInMenu, let percent = powerService.batteryPercent {
                Text("\(percent)%").foregroundStyle(.secondary)
            }
        }
        .onAppear {
            powerService.startPolling(intervalSeconds: AppSettings.shared.refreshIntervalSeconds)
        }
    }

    private var labelContent: some View {
        let decimals = max(0, min(2, settings.decimalPlaces))
        let inW = powerService.inWatts
        let outW = powerService.outWatts
        let useColor = settings.coloredIndicators

        func wattsString(_ w: Double?) -> String {
            guard let w else { return "--.- W" as String }
            return String(format: "%0.*f W", decimals, w)
        }

        return Group {
            switch settings.labelStyle {
            case .iconAndWatts:
                if settings.displayMode == .netOnly {
                    // Net = IN - OUT when charging; else -OUT when discharging
                    let net: Double? = {
                        if powerService.isCharging {
                            if let inW, let outW { return inW - outW }
                            return inW ?? 0
                        } else {
                            return outW.map { -$0 } ?? nil
                        }
                    }()
                    HStack(spacing: 4) {
                        Image(systemName: net.map { $0 >= 0 } ?? false ? "bolt.fill" : "bolt.slash.fill")
                            .foregroundStyle(useColor ? (net ?? 0 >= 0 ? .green : .red) : .primary)
                        Text(wattsString(net?.magnitude))
                            .monospacedDigit()
                    }
                } else if powerService.isCharging, (inW ?? 0) > 0.05 {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").foregroundStyle(useColor ? .green : .primary)
                        Text("IN \(wattsString(inW))").monospacedDigit()
                        if let outWatts = outW, outWatts > 0.05 {
                            Text("|")
                            Image(systemName: "bolt.slash.fill").foregroundStyle(useColor ? .red : .primary)
                            Text(wattsString(outWatts)).monospacedDigit()
                        }
                    }
                } else if let inWatts = inW, inWatts > 0.05 {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").foregroundStyle(useColor ? .green : .primary)
                        Text(wattsString(inWatts)).monospacedDigit()
                    }
                } else if let outWatts = outW, outWatts > 0.05 {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.slash.fill").foregroundStyle(useColor ? .red : .primary)
                        Text(wattsString(outWatts)).monospacedDigit()
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt").foregroundStyle(.secondary)
                        Text(wattsString(nil)).monospacedDigit()
                    }
                }
            case .wattsOnly:
                if settings.displayMode == .netOnly {
                    let net: Double? = {
                        if powerService.isCharging {
                            if let inW, let outW { return inW - outW }
                            return inW ?? 0
                        } else {
                            return outW.map { -$0 } ?? nil
                        }
                    }()
                    Text(wattsString(net?.magnitude)).monospacedDigit()
                } else if powerService.isCharging, (inW ?? 0) > 0.05 {
                    HStack(spacing: 4) {
                        Text("IN \(wattsString(inW))").monospacedDigit()
                        if let outWatts = outW, outWatts > 0.05 {
                            Text("|")
                            Text(wattsString(outWatts)).monospacedDigit()
                        }
                    }
                } else if let inWatts = inW, inWatts > 0.05 {
                    Text(wattsString(inWatts)).monospacedDigit()
                } else if let outWatts = outW, outWatts > 0.05 {
                    Text(wattsString(outWatts)).monospacedDigit()
                } else {
                    Text(wattsString(nil)).monospacedDigit()
                }
            case .prefixAndWatts:
                if settings.displayMode == .netOnly {
                    let net: Double? = {
                        if powerService.isCharging {
                            if let inW, let outW { return inW - outW }
                            return inW ?? 0
                        } else {
                            return outW.map { -$0 } ?? nil
                        }
                    }()
                    HStack(spacing: 2) {
                        Text(net.map { $0 >= 0 } ?? false ? "NET " : "NET ")
                            .foregroundStyle(useColor ? (net ?? 0 >= 0 ? .green : .red) : .primary)
                        Text(wattsString(net?.magnitude)).monospacedDigit()
                    }
                } else if powerService.isCharging, (inW ?? 0) > 0.05 {
                    HStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Text("IN ").foregroundStyle(useColor ? .green : .primary)
                            Text(wattsString(inW)).monospacedDigit()
                        }
                        if let outWatts = outW, outWatts > 0.05 {
                            Text("|")
                            HStack(spacing: 2) {
                                Text("OUT ").foregroundStyle(useColor ? .red : .primary)
                                Text(wattsString(outWatts)).monospacedDigit()
                            }
                        }
                    }
                } else if let inWatts = inW, inWatts > 0.05 {
                    HStack(spacing: 2) {
                        Text("IN ").foregroundStyle(useColor ? .green : .primary)
                        Text(wattsString(inWatts)).monospacedDigit()
                    }
                } else if let outWatts = outW, outWatts > 0.05 {
                    HStack(spacing: 2) {
                        Text("OUT ").foregroundStyle(useColor ? .red : .primary)
                        Text(wattsString(outWatts)).monospacedDigit()
                    }
                } else {
                    Text("--.- W").monospacedDigit()
                }
            }
        }
    }
}

private struct MenuContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var powerService: BatteryPowerService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                HStack {
                    Text("Status:")
                        .foregroundStyle(.secondary)
                    Text(powerService.isCharging ? "Charging" : "On Battery")
                }
                HStack {
                    Text("Power:")
                        .foregroundStyle(.secondary)
                    if let inW = powerService.inWatts, inW > 0.05 {
                        Text("IN \(String(format: "%.1f", inW)) W")
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    } else if let outW = powerService.outWatts, outW > 0.05 {
                        Text("OUT \(String(format: "%.1f", outW)) W")
                            .foregroundStyle(.red)
                            .monospacedDigit()
                    } else {
                        Text("--.- W").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                HStack {
                    Text("Battery:")
                        .foregroundStyle(.secondary)
                    if let percent = powerService.batteryPercent {
                        Text("\(percent)%").monospacedDigit()
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading) {
                Text("Refresh interval")
                    .foregroundStyle(.secondary)
                HStack {
                    Slider(value: $settings.refreshIntervalSeconds, in: 1...60, step: 1) {
                        Text("Refresh interval")
                    } minimumValueLabel: {
                        Text("1s")
                    } maximumValueLabel: {
                        Text("60s")
                    }
                    .frame(width: 180)
                    Text("\(Int(settings.refreshIntervalSeconds))s")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                .onChange(of: settings.refreshIntervalSeconds) { _, newValue in
                    powerService.startPolling(intervalSeconds: newValue)
                }
            }

            Toggle(isOn: Binding<Bool>(
                get: { LoginItemManager.isEnabled },
                set: { newValue in
                    if newValue { _ = try? LoginItemManager.enable() } else { _ = try? LoginItemManager.disable() }
                }
            )) {
                Text("Open at Login")
            }

            Divider()

            Button("Preferences…") {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
            Button("Quit PowerWatt") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(minWidth: 300)
        .onAppear {
            powerService.startPolling(intervalSeconds: settings.refreshIntervalSeconds)
        }
    }
}

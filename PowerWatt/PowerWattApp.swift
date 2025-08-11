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
                .frame(width: 480, height: 500)
        }
    }
}

private func openSettingsWindow() {
    #if canImport(AppKit)
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference") {
        // Fallback noop; we'll try native below
        _ = url
    }
    if #available(macOS 13.0, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
    #endif
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
            powerService.startPolling(intervalSeconds: settings.refreshIntervalSeconds)
        }
        .onChange(of: settings.refreshIntervalSeconds) { _, newValue in
            powerService.startPolling(intervalSeconds: newValue)
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
                        let isPositive = (net ?? 0) >= 0
                        Image(systemName: isPositive ? "bolt.fill" : "bolt.slash.fill")
                            .foregroundStyle(useColor ? (isPositive ? .green : .red) : .primary)
                        Text(wattsString(net?.magnitude))
                            .foregroundStyle(useColor ? (isPositive ? .green : .red) : .primary)
                            .monospacedDigit()
                    }
                } else if powerService.isCharging {
                    // Separate mode while charging: always show both IN and OUT (contracted)
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").foregroundStyle(useColor ? .green : .primary)
                        Text(wattsString(inW))
                            .foregroundStyle(useColor ? .green : .primary)
                            .monospacedDigit()
                        Text("|")
                        Image(systemName: "bolt.slash.fill").foregroundStyle(useColor ? .red : .primary)
                        Text(wattsString(outW))
                            .foregroundStyle(useColor ? .red : .primary)
                            .monospacedDigit()
                    }
                } else if let inWatts = inW, inWatts > 0.05 {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").foregroundStyle(useColor ? .green : .primary)
                        Text(wattsString(inWatts))
                            .foregroundStyle(useColor ? .green : .primary)
                            .monospacedDigit()
                    }
                } else if let outWatts = outW, outWatts > 0.05 {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.slash.fill").foregroundStyle(useColor ? .red : .primary)
                        Text(wattsString(outWatts))
                            .foregroundStyle(useColor ? .red : .primary)
                            .monospacedDigit()
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
                    Text(wattsString(net?.magnitude))
                        .foregroundStyle(useColor ? ((net ?? 0) >= 0 ? .green : .red) : .primary)
                        .monospacedDigit()
                } else if powerService.isCharging {
                    HStack(spacing: 4) {
                        Text(wattsString(inW))
                            .foregroundStyle(useColor ? .green : .primary)
                            .monospacedDigit()
                        Text("|")
                        Text(wattsString(outW))
                            .foregroundStyle(useColor ? .red : .primary)
                            .monospacedDigit()
                    }
                } else if let inWatts = inW, inWatts > 0.05 {
                    Text(wattsString(inWatts))
                        .foregroundStyle(useColor ? .green : .primary)
                        .monospacedDigit()
                } else if let outWatts = outW, outWatts > 0.05 {
                    Text(wattsString(outWatts))
                        .foregroundStyle(useColor ? .red : .primary)
                        .monospacedDigit()
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
                        let isPositive = (net ?? 0) >= 0
                        Text("NET ")
                            .foregroundStyle(useColor ? (isPositive ? .green : .red) : .primary)
                        Text(wattsString(net?.magnitude))
                            .foregroundStyle(useColor ? (isPositive ? .green : .red) : .primary)
                            .monospacedDigit()
                    }
                } else if powerService.isCharging {
                    HStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Text("IN ").foregroundStyle(useColor ? .green : .primary)
                            Text(wattsString(inW))
                                .foregroundStyle(useColor ? .green : .primary)
                                .monospacedDigit()
                        }
                        Text("|")
                        HStack(spacing: 2) {
                            Text("OUT ").foregroundStyle(useColor ? .red : .primary)
                            Text(wattsString(outW))
                                .foregroundStyle(useColor ? .red : .primary)
                                .monospacedDigit()
                        }
                    }
                } else if let inWatts = inW, inWatts > 0.05 {
                    HStack(spacing: 2) {
                        Text("IN ").foregroundStyle(useColor ? .green : .primary)
                        Text(wattsString(inWatts))
                            .foregroundStyle(useColor ? .green : .primary)
                            .monospacedDigit()
                    }
                } else if let outWatts = outW, outWatts > 0.05 {
                    HStack(spacing: 2) {
                        Text("OUT ").foregroundStyle(useColor ? .red : .primary)
                        Text(wattsString(outWatts))
                            .foregroundStyle(useColor ? .red : .primary)
                            .monospacedDigit()
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

            if #available(macOS 14.0, *) {
                SettingsLink {
                    Text("Preferences…")
                }
            } else {
                Button("Preferences…") {
                    openSettingsWindow()
                }
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


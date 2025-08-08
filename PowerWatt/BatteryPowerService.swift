import Foundation
import IOKit
import IOKit.ps

final class BatteryPowerService: ObservableObject {
    @Published private(set) var inWatts: Double?
    @Published private(set) var outWatts: Double?
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var batteryPercent: Int?

    private var timer: Timer?
    private var readings: [(timestamp: TimeInterval, inW: Double?, outW: Double?)] = []

    func startPolling(intervalSeconds: Double) {
        timer?.invalidate()
        let clamped = max(0.5, intervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: clamped, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer!, forMode: .common)
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSmartBattery")
        let masterPort = kIOMainPortDefault
        let result = IOServiceGetMatchingServices(masterPort, matching, &iterator)
        guard result == KERN_SUCCESS else { return }

        defer { IOObjectRelease(iterator) }

        let service: io_object_t = IOIteratorNext(iterator)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var propertiesRef: Unmanaged<CFMutableDictionary>?
        let propsResult = IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0)
        guard propsResult == KERN_SUCCESS, let props = propertiesRef?.takeRetainedValue() as? [String: Any] else { return }

        let amperageMilli = props["Amperage"] as? Int // mA (neg when discharging)
        let voltageMilli = props["Voltage"] as? Int // mV
        let isChargingNow = props["IsCharging"] as? Bool ?? false
        let currentCapacity = props["CurrentCapacity"] as? Int
        let maxCapacity = props["MaxCapacity"] as? Int

        var inW: Double?
        var outW: Double?

        if let mA = amperageMilli, let mV = voltageMilli {
            let powerWatts = (Double(abs(mA)) * Double(mV)) / 1_000_000.0
            if mA >= 0 || isChargingNow {
                inW = powerWatts
            } else {
                outW = powerWatts
            }
        }

        let percent: Int?
        if let cur = currentCapacity, let max = maxCapacity, max > 0 {
            percent = Int((Double(cur) / Double(max)) * 100.0)
        } else {
            percent = nil
        }

        smoothAndPublish(inW: inW, outW: outW, isCharging: isChargingNow, batteryPercent: percent)
    }

    private func smoothAndPublish(inW: Double?, outW: Double?, isCharging: Bool, batteryPercent: Int?) {
        let now = Date().timeIntervalSince1970
        readings.append((timestamp: now, inW: inW, outW: outW))

        let windowSeconds = AppSettings.shared.smoothingWindowSeconds
        if windowSeconds > 0 {
            let cutoff = now - windowSeconds
            readings.removeAll { $0.timestamp < cutoff }
        } else {
            readings.removeAll(keepingCapacity: true)
            readings.append((timestamp: now, inW: inW, outW: outW))
        }

        func average(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sum = values.reduce(0, +)
            return sum / Double(values.count)
        }

        let avgIn = average(readings.compactMap { $0.inW })
        let avgOut = average(readings.compactMap { $0.outW })

        DispatchQueue.main.async {
            self.inWatts = avgIn ?? inW
            self.outWatts = avgOut ?? outW
            self.isCharging = isCharging
            self.batteryPercent = batteryPercent
        }
    }
}



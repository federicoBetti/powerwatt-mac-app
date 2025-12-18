//
//  TotalPowerService.swift
//  PowerWatt
//
//  Service for extracting total system power consumption
//

import Foundation
import IOKit
import Combine

/// Service that reads total system power from IORegistry or derives it from battery
final class TotalPowerService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var latestSample: TotalPowerSample?
    @Published private(set) var isRunning: Bool = false
    
    // MARK: - Private Properties
    
    private var timer: Timer?
    private var sampleSubject = PassthroughSubject<TotalPowerSample, Never>()
    
    /// Publisher for samples
    var samplePublisher: AnyPublisher<TotalPowerSample, Never> {
        sampleSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Sampling Control
    
    /// Start sampling at the specified interval
    func startSampling(intervalSeconds: Double) {
        stopSampling()
        isRunning = true
        
        let interval = max(1.0, intervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.collectSample()
        }
        RunLoop.main.add(timer!, forMode: .common)
        
        // Collect initial sample
        collectSample()
    }
    
    /// Stop sampling
    func stopSampling() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
    
    /// Collect a single sample
    func collectSample() {
        let sample = readTotalPower()
        DispatchQueue.main.async {
            self.latestSample = sample
        }
        sampleSubject.send(sample)
    }
    
    // MARK: - Power Reading
    
    /// Read total system power from available sources
    private func readTotalPower() -> TotalPowerSample {
        let timestamp = Date()
        
        // Try to get IORegistry properties
        guard let props = getSmartBatteryProperties() else {
            return TotalPowerSample(
                timestamp: timestamp,
                totalWatts: nil,
                adapterWatts: nil,
                isOnAC: false,
                batteryPercent: nil,
                source: .unavailable,
                batteryVoltage: nil,
                batteryCurrent: nil
            )
        }
        
        let isCharging = props["IsCharging"] as? Bool ?? false
        let externalConnected = props["ExternalConnected"] as? Bool ?? false
        let isOnAC = isCharging || externalConnected
        
        // Battery percentage
        let batteryPercent: Double?
        if let current = props["CurrentCapacity"] as? Int,
           let max = props["MaxCapacity"] as? Int, max > 0 {
            batteryPercent = Double(current) / Double(max) * 100.0
        } else {
            batteryPercent = nil
        }
        
        // Battery voltage and current
        let voltageMilli = props["Voltage"] as? Int ?? 0
        let amperageMilli = props["Amperage"] as? Int ?? 0
        let batteryVoltage = Double(voltageMilli) / 1000.0
        let batteryCurrent = Double(abs(amperageMilli)) / 1000.0
        
        // Try IORegistry SystemPower first (FR1 priority 1)
        if let systemPowerWatts = readSystemPowerFromIORegistry(props: props) {
            let adapterWatts = readAdapterPowerFromIORegistry(props: props)
            
            // Sanity check
            if systemPowerWatts >= 0 && systemPowerWatts <= 200 {
                return TotalPowerSample(
                    timestamp: timestamp,
                    totalWatts: systemPowerWatts,
                    adapterWatts: adapterWatts,
                    isOnAC: isOnAC,
                    batteryPercent: batteryPercent,
                    source: .ioRegistrySystemPower,
                    batteryVoltage: batteryVoltage,
                    batteryCurrent: batteryCurrent
                )
            }
        }
        
        // Fallback to battery-derived watts (FR1 priority 2)
        // Reliable when discharging (amperage is negative). We don't strictly require isOnAC == false
        // because some systems may report ExternalConnected inconsistently.
        if amperageMilli < 0 {
            let batteryWatts = batteryVoltage * batteryCurrent
            
            // Sanity check
            if batteryWatts >= 0 && batteryWatts <= 200 {
                return TotalPowerSample(
                    timestamp: timestamp,
                    totalWatts: batteryWatts,
                    adapterWatts: nil,
                    isOnAC: isOnAC,
                    batteryPercent: batteryPercent,
                    source: .batteryDerived,
                    batteryVoltage: batteryVoltage,
                    batteryCurrent: batteryCurrent
                )
            }
        }
        
        // Unavailable - can't determine total watts reliably
        return TotalPowerSample(
            timestamp: timestamp,
            totalWatts: nil,
            adapterWatts: nil,
            isOnAC: isOnAC,
            batteryPercent: batteryPercent,
            source: .unavailable,
            batteryVoltage: batteryVoltage,
            batteryCurrent: batteryCurrent
        )
    }
    
    // MARK: - IORegistry Reading
    
    /// Get AppleSmartBattery properties
    private func getSmartBatteryProperties() -> [String: Any]? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSmartBattery")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        
        var propsRef: Unmanaged<CFMutableDictionary>?
        let propsResult = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
        guard propsResult == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        
        return props
    }
    
    /// Read SystemPower from IORegistry with robust decoding
    private func readSystemPowerFromIORegistry(props: [String: Any]) -> Double? {
        // Try various possible keys
        let possibleKeys = ["SystemPower", "SystemPowerDrain", "InstantAmperage"]
        
        for key in possibleKeys {
            if let value = props[key] {
                if let watts = decodeIORegistryValue(value) {
                    return watts
                }
            }
        }
        
        return nil
    }
    
    /// Read AdapterPower from IORegistry
    private func readAdapterPowerFromIORegistry(props: [String: Any]) -> Double? {
        let possibleKeys = ["AdapterPower", "Wattage", "AdapterDetails"]
        
        for key in possibleKeys {
            if let value = props[key] {
                // AdapterDetails is often a dictionary
                if let details = value as? [String: Any] {
                    if let watts = details["Watts"] as? Int {
                        return Double(watts)
                    }
                    if let watts = details["Wattage"] as? Int {
                        return Double(watts)
                    }
                }
                if let watts = decodeIORegistryValue(value) {
                    return watts
                }
            }
        }
        
        return nil
    }
    
    /// Decode IORegistry value with various possible formats
    /// Handles: Data (IEEE754 float bits), NSNumber, Int, Double
    private func decodeIORegistryValue(_ value: Any) -> Double? {
        // Direct numeric types
        if let doubleVal = value as? Double {
            return doubleVal
        }
        
        if let intVal = value as? Int {
            // Check if it looks like IEEE754 float bits
            if intVal > 0x3F800000 && intVal < 0x44000000 {
                // Likely a float stored as int bits
                let floatVal = Float(bitPattern: UInt32(intVal))
                return Double(floatVal)
            }
            return Double(intVal)
        }
        
        if let nsNumber = value as? NSNumber {
            return nsNumber.doubleValue
        }
        
        // Data type - decode as IEEE754 float bits
        if let data = value as? Data, data.count >= 4 {
            let uint32Val = data.withUnsafeBytes { ptr in
                ptr.load(as: UInt32.self)
            }
            let floatVal = Float(bitPattern: uint32Val)
            
            // Sanity check
            if floatVal.isFinite && floatVal >= 0 && floatVal <= 500 {
                return Double(floatVal)
            }
        }
        
        return nil
    }
}

// MARK: - Convenience Extensions

extension TotalPowerService {
    /// Current total watts (convenience accessor)
    var currentTotalWatts: Double? {
        latestSample?.totalWatts
    }
    
    /// Whether current sample has valid watts
    var hasValidWatts: Bool {
        latestSample?.hasValidWatts ?? false
    }
    
    /// Current power source
    var currentSource: TotalPowerSource {
        latestSample?.source ?? .unavailable
    }
}

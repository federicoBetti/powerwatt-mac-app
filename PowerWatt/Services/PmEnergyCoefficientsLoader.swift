//
//  PmEnergyCoefficientsLoader.swift
//  PowerWatt
//
//  Loads energy impact coefficients from /usr/share/pmenergy/ if available
//

import Foundation

/// Loader for system energy impact coefficients from pmenergy plists
final class PmEnergyCoefficientsLoader {
    
    /// Path to system coefficient files
    private static let pmenergyPath = "/usr/share/pmenergy"
    
    /// Cached coefficients
    private var cachedCoefficients: EnergyCoefficients?
    private var lastLoadTime: Date?
    private var lastModificationDate: Date?
    
    /// Whether coefficients were loaded from system files
    private(set) var loadedFromSystem: Bool = false
    
    /// Cache duration before checking for updates
    private let cacheDuration: TimeInterval = 3600 // 1 hour
    
    // MARK: - Public Interface
    
    /// Load coefficients, using cache if valid
    func loadCoefficients() -> EnergyCoefficients {
        // Check if cache is valid
        if let cached = cachedCoefficients,
           let loadTime = lastLoadTime,
           Date().timeIntervalSince(loadTime) < cacheDuration {
            // Check if files have been modified
            if !hasFilesChanged() {
                return cached
            }
        }
        
        // Try to load from system
        if let systemCoeffs = loadFromSystem() {
            cachedCoefficients = systemCoeffs
            lastLoadTime = Date()
            loadedFromSystem = true
            return systemCoeffs
        }
        
        // Fall back to defaults
        let defaults = EnergyCoefficients.default
        cachedCoefficients = defaults
        lastLoadTime = Date()
        loadedFromSystem = false
        return defaults
    }
    
    /// Force reload coefficients
    func reloadCoefficients() -> EnergyCoefficients {
        cachedCoefficients = nil
        lastLoadTime = nil
        return loadCoefficients()
    }
    
    // MARK: - System Loading
    
    /// Try to load coefficients from system plist files
    private func loadFromSystem() -> EnergyCoefficients? {
        let fileManager = FileManager.default
        let pmPath = Self.pmenergyPath
        
        // Check if directory exists
        guard fileManager.fileExists(atPath: pmPath) else {
            return nil
        }
        
        // Look for coefficient files
        let possibleFiles = [
            "coefficients.plist",
            "energymodel.plist",
            "weights.plist"
        ]
        
        for fileName in possibleFiles {
            let filePath = (pmPath as NSString).appendingPathComponent(fileName)
            if let coeffs = loadCoefficientsFromPlist(atPath: filePath) {
                updateModificationDate(for: filePath)
                return coeffs
            }
        }
        
        // Try to scan directory for any plist files
        if let files = try? fileManager.contentsOfDirectory(atPath: pmPath) {
            for file in files where file.hasSuffix(".plist") {
                let filePath = (pmPath as NSString).appendingPathComponent(file)
                if let coeffs = loadCoefficientsFromPlist(atPath: filePath) {
                    updateModificationDate(for: filePath)
                    return coeffs
                }
            }
        }
        
        return nil
    }
    
    /// Load coefficients from a specific plist file
    private func loadCoefficientsFromPlist(atPath path: String) -> EnergyCoefficients? {
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        
        // Try to parse as plist
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }
        
        // Extract coefficients with various possible key names
        var coeffs = EnergyCoefficients()
        var foundAny = false
        
        // CPU weight
        if let cpuWeight = extractWeight(from: plist, keys: ["cpu_weight", "cpuWeight", "cpu", "CPU"]) {
            coeffs.cpuWeight = cpuWeight
            foundAny = true
        }
        
        // Wakeups weight
        if let wakeupWeight = extractWeight(from: plist, keys: ["wakeups_weight", "wakeupsWeight", "wakeups", "interrupt_wakeups"]) {
            coeffs.wakeupsWeight = wakeupWeight
            foundAny = true
        }
        
        // Disk weight
        if let diskWeight = extractWeight(from: plist, keys: ["disk_weight", "diskWeight", "disk", "diskio"]) {
            coeffs.diskWeight = diskWeight
            foundAny = true
        }
        
        // Network weight
        if let networkWeight = extractWeight(from: plist, keys: ["network_weight", "networkWeight", "network", "net"]) {
            coeffs.networkWeight = networkWeight
            foundAny = true
        }
        
        // Only return if we found at least one coefficient and it's valid
        guard foundAny && coeffs.isValid else {
            return nil
        }
        
        return coeffs
    }
    
    /// Extract a weight value from plist with multiple possible key names
    private func extractWeight(from dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dict[key] {
                if let doubleVal = value as? Double {
                    return doubleVal
                }
                if let intVal = value as? Int {
                    return Double(intVal)
                }
                if let nsNumber = value as? NSNumber {
                    return nsNumber.doubleValue
                }
            }
        }
        return nil
    }
    
    // MARK: - File Change Detection
    
    /// Check if coefficient files have changed since last load
    private func hasFilesChanged() -> Bool {
        guard let lastMod = lastModificationDate else { return true }
        
        let fileManager = FileManager.default
        let pmPath = Self.pmenergyPath
        
        guard let files = try? fileManager.contentsOfDirectory(atPath: pmPath) else {
            return false
        }
        
        for file in files where file.hasSuffix(".plist") {
            let filePath = (pmPath as NSString).appendingPathComponent(file)
            if let attrs = try? fileManager.attributesOfItem(atPath: filePath),
               let modDate = attrs[.modificationDate] as? Date {
                if modDate > lastMod {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Update stored modification date
    private func updateModificationDate(for path: String) {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let modDate = attrs[.modificationDate] as? Date {
            lastModificationDate = modDate
        }
    }
}

// MARK: - Debugging Extension

extension PmEnergyCoefficientsLoader {
    /// Debug description of current state
    var debugDescription: String {
        let source = loadedFromSystem ? "System" : "Defaults"
        let coeffs = cachedCoefficients ?? EnergyCoefficients.default
        return "PmEnergyCoefficientsLoader(source: \(source), coefficients: \(coeffs))"
    }
}

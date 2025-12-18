//
//  ProcessMetricsService.swift
//  PowerWatt
//
//  Service for collecting per-process resource metrics using libproc
//

import Foundation
import AppKit
import Combine
import Darwin

/// Service that collects per-process metrics (CPU, memory, disk I/O, etc.)
final class ProcessMetricsService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var latestSamples: [ProcessMetricsSample] = []
    @Published private(set) var isRunning: Bool = false
    
    // MARK: - Private Properties
    
    private var timer: Timer?
    private var previousUsage: [pid_t: ProcessResourceUsage] = [:]
    private var appIconCache: [String: NSImage] = [:]
    private var sampleSubject = PassthroughSubject<[ProcessMetricsSample], Never>()
    
    /// Publisher for samples
    var samplePublisher: AnyPublisher<[ProcessMetricsSample], Never> {
        sampleSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Configuration
    
    /// Include non-app background processes
    var includeBackgroundProcesses: Bool = false
    
    /// Minimum activity threshold (skip processes with less than this CPU time delta)
    var minActivityThreshold: Double = 0.0001
    
    // MARK: - Sampling Control
    
    /// Start collecting metrics at the specified interval
    func startSampling(intervalSeconds: Double) {
        stopSampling()
        isRunning = true
        previousUsage.removeAll()
        
        let interval = max(2.0, min(10.0, intervalSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.collectSamples()
        }
        RunLoop.main.add(timer!, forMode: .common)
        
        // Collect initial baseline
        collectBaseline()
    }
    
    /// Stop collecting metrics
    func stopSampling() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
    
    // MARK: - Sample Collection
    
    /// Collect baseline usage (first sample, no deltas yet)
    private func collectBaseline() {
        let apps = getRunningApps()
        var newUsage: [pid_t: ProcessResourceUsage] = [:]
        
        for app in apps {
            if let usage = getProcessResourceUsage(pid: app.pid) {
                newUsage[app.pid] = usage
            }
        }
        
        previousUsage = newUsage
    }
    
    /// Collect metric samples with deltas
    private func collectSamples() {
        let timestamp = Date()
        let apps = getRunningApps()
        
        var samples: [ProcessMetricsSample] = []
        var newUsage: [pid_t: ProcessResourceUsage] = [:]
        
        for app in apps {
            guard let currentUsage = getProcessResourceUsage(pid: app.pid) else {
                continue
            }
            
            newUsage[app.pid] = currentUsage
            
            // Calculate deltas if we have previous data
            if let prevUsage = previousUsage[app.pid] {
                let cpuDelta = currentUsage.totalCpuTimeSeconds - prevUsage.totalCpuTimeSeconds
                
                // Skip if below activity threshold
                guard cpuDelta >= minActivityThreshold ||
                      currentUsage.wakeups > prevUsage.wakeups ||
                      currentUsage.diskBytesRead > prevUsage.diskBytesRead ||
                      currentUsage.diskBytesWritten > prevUsage.diskBytesWritten else {
                    continue
                }
                
                let wakeupsDelta = Int(currentUsage.wakeups) - Int(prevUsage.wakeups)
                let diskReadDelta = Int64(currentUsage.diskBytesRead) - Int64(prevUsage.diskBytesRead)
                let diskWriteDelta = Int64(currentUsage.diskBytesWritten) - Int64(prevUsage.diskBytesWritten)
                
                var netInDelta: Int64? = nil
                var netOutDelta: Int64? = nil
                
                if let currIn = currentUsage.networkBytesIn,
                   let prevIn = prevUsage.networkBytesIn {
                    netInDelta = Int64(currIn) - Int64(prevIn)
                }
                if let currOut = currentUsage.networkBytesOut,
                   let prevOut = prevUsage.networkBytesOut {
                    netOutDelta = Int64(currOut) - Int64(prevOut)
                }
                
                // Clamp negative deltas to 0 (can happen with counter wraps or process restarts)
                let sample = ProcessMetricsSample(
                    timestamp: timestamp,
                    pid: app.pid,
                    bundleId: app.bundleId,
                    appName: app.name,
                    cpuTimeDeltaSec: max(0, cpuDelta),
                    wakeupsDelta: max(0, wakeupsDelta),
                    diskReadBytesDelta: max(0, diskReadDelta),
                    diskWriteBytesDelta: max(0, diskWriteDelta),
                    netInBytesDelta: netInDelta.map { max(0, $0) },
                    netOutBytesDelta: netOutDelta.map { max(0, $0) },
                    icon: app.icon,
                    isApp: app.isApp
                )
                
                samples.append(sample)
            }
        }
        
        // Update previous usage, removing dead processes
        previousUsage = newUsage
        
        // Publish results
        DispatchQueue.main.async {
            self.latestSamples = samples
        }
        sampleSubject.send(samples)
    }
    
    // MARK: - Process Enumeration
    
    /// Get list of running applications
    private func getRunningApps() -> [RunningAppInfo] {
        var apps: [RunningAppInfo] = []
        
        // Get user-facing apps from NSWorkspace
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            // Skip ourselves and system processes
            if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                continue
            }
            
            let bundleId = app.bundleIdentifier
            let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
            
            // Get or cache icon
            let icon: NSImage?
            if let bid = bundleId, let cached = appIconCache[bid] {
                icon = cached
            } else if let appIcon = app.icon {
                icon = appIcon
                if let bid = bundleId {
                    appIconCache[bid] = appIcon
                }
            } else {
                icon = nil
            }
            
            apps.append(RunningAppInfo(
                pid: app.processIdentifier,
                bundleId: bundleId,
                name: name,
                icon: icon,
                isApp: true
            ))
        }
        
        // Optionally include background processes
        if includeBackgroundProcesses {
            let bgProcesses = getBackgroundProcesses(excludePids: Set(apps.map(\.pid)))
            apps.append(contentsOf: bgProcesses)
        }
        
        return apps
    }
    
    /// Get background (non-app) processes
    private func getBackgroundProcesses(excludePids: Set<pid_t>) -> [RunningAppInfo] {
        var processes: [RunningAppInfo] = []
        
        // Get all PIDs using proc_listallpids
        var pids = [pid_t](repeating: 0, count: 2048)
        let byteCount = pw_proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        let pidCount = Int(byteCount) / MemoryLayout<pid_t>.size
        
        for i in 0..<pidCount {
            let pid = pids[i]
            
            // Skip excluded PIDs
            if excludePids.contains(pid) || pid <= 0 {
                continue
            }
            
            // Get process name
            var nameBuffer = [CChar](repeating: 0, count: 1024)
            let nameLen = pw_proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            
            guard nameLen > 0 else { continue }
            
            let name = String(cString: nameBuffer)
            
            // Skip system processes we don't care about
            let skipPrefixes = ["kernel", "launchd", "syslog", "notifyd", "mds", "distnoted"]
            if skipPrefixes.contains(where: { name.lowercased().hasPrefix($0) }) {
                continue
            }
            
            processes.append(RunningAppInfo(
                pid: pid,
                bundleId: nil,
                name: name,
                icon: nil,
                isApp: false
            ))
        }
        
        return processes
    }
    
    // MARK: - Resource Usage
    
    /// Get resource usage for a process using proc_pid_rusage
    private func getProcessResourceUsage(pid: pid_t) -> ProcessResourceUsage? {
        var rusage = rusage_info_v4()
        let result = withUnsafeMutableBytes(of: &rusage) { buffer in
            pw_proc_pid_rusage(pid, RUSAGE_INFO_V4, buffer.baseAddress)
        }
        
        guard result == 0 else { return nil }
        
        return ProcessResourceUsage(
            pid: pid,
            userTime: rusage.ri_user_time,
            systemTime: rusage.ri_system_time,
            wakeups: rusage.ri_interrupt_wkups + rusage.ri_pkg_idle_wkups,
            diskBytesRead: rusage.ri_diskio_bytesread,
            diskBytesWritten: rusage.ri_diskio_byteswritten,
            networkBytesIn: nil,  // Not available in rusage_info
            networkBytesOut: nil
        )
    }
}

// MARK: - libproc Declarations

// These are bridged from sys/resource.h and libproc.h
@_silgen_name("proc_listallpids")
private func pw_proc_listallpids(_ buffer: UnsafeMutablePointer<pid_t>?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_name")
private func pw_proc_name(_ pid: pid_t, _ buffer: UnsafeMutablePointer<CChar>?, _ buffersize: UInt32) -> Int32

@_silgen_name("proc_pid_rusage")
private func pw_proc_pid_rusage(_ pid: pid_t, _ flavor: Int32, _ buffer: UnsafeMutableRawPointer?) -> Int32

private let RUSAGE_INFO_V4: Int32 = 4

// MARK: - Convenience Extensions

extension ProcessMetricsService {
    /// Get samples grouped by bundle ID
    func samplesByApp() -> [String: [ProcessMetricsSample]] {
        var grouped: [String: [ProcessMetricsSample]] = [:]
        
        for sample in latestSamples {
            let key = sample.bundleId ?? "unknown.\(sample.pid)"
            grouped[key, default: []].append(sample)
        }
        
        return grouped
    }
    
    /// Get aggregated metrics per app
    func aggregatedByApp() -> [(bundleId: String, appName: String?, cpuTime: Double, wakeups: Int, diskBytes: Int64)] {
        let grouped = samplesByApp()
        
        return grouped.map { (bundleId, samples) in
            let cpuTime = samples.map(\.cpuTimeDeltaSec).reduce(0, +)
            let wakeups = samples.map(\.wakeupsDelta).reduce(0, +)
            let diskBytes = samples.map(\.totalDiskBytes).reduce(0, +)
            let appName = samples.first?.appName
            
            return (bundleId: bundleId, appName: appName, cpuTime: cpuTime, wakeups: wakeups, diskBytes: diskBytes)
        }.sorted { $0.cpuTime > $1.cpuTime }
    }
}

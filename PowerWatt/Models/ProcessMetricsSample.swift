//
//  ProcessMetricsSample.swift
//  PowerWatt
//
//  Per-process metrics sample model
//

import Foundation

/// Represents metrics collected for a single process at a point in time
struct ProcessMetricsSample: Identifiable {
    /// Unique identifier for this sample
    var id: String { "\(timestamp.timeIntervalSince1970)-\(pid)" }
    
    /// Timestamp of the sample
    let timestamp: Date
    
    /// Process ID
    let pid: pid_t
    
    /// Bundle identifier (for apps)
    let bundleId: String?
    
    /// Application/process name
    let appName: String?
    
    /// CPU time delta in seconds (user + system) since last sample
    let cpuTimeDeltaSec: Double
    
    /// Number of wakeups since last sample
    let wakeupsDelta: Int
    
    /// Bytes read from disk since last sample
    let diskReadBytesDelta: Int64
    
    /// Bytes written to disk since last sample
    let diskWriteBytesDelta: Int64
    
    /// Network bytes received since last sample (optional)
    let netInBytesDelta: Int64?
    
    /// Network bytes sent since last sample (optional)
    let netOutBytesDelta: Int64?
    
    /// Application icon (cached)
    var icon: NSImage?
    
    /// Whether this is a user-facing app (vs background process)
    let isApp: Bool
    
    /// Total disk bytes (read + write)
    var totalDiskBytes: Int64 {
        diskReadBytesDelta + diskWriteBytesDelta
    }
    
    /// Total network bytes (in + out)
    var totalNetworkBytes: Int64 {
        (netInBytesDelta ?? 0) + (netOutBytesDelta ?? 0)
    }
}

/// Raw process resource usage data from libproc
struct ProcessResourceUsage {
    let pid: pid_t
    let userTime: UInt64        // User CPU time in nanoseconds
    let systemTime: UInt64      // System CPU time in nanoseconds
    let wakeups: UInt64         // Interrupt wakeups
    let diskBytesRead: UInt64   // Bytes read from disk
    let diskBytesWritten: UInt64 // Bytes written to disk
    let networkBytesIn: UInt64? // Network bytes received
    let networkBytesOut: UInt64? // Network bytes sent
    
    /// Total CPU time in seconds
    var totalCpuTimeSeconds: Double {
        Double(userTime + systemTime) / 1_000_000_000.0
    }
}

/// Information about a running application
struct RunningAppInfo {
    let pid: pid_t
    let bundleId: String?
    let name: String
    let icon: NSImage?
    let isApp: Bool
}

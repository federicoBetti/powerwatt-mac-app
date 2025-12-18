//
//  UsageStore.swift
//  PowerWatt
//
//  SQLite storage for usage data with 24-hour retention
//

import Foundation
import SQLite3

/// SQLite-based storage for usage data
final class UsageStore {
    
    // MARK: - Types
    
    /// Minute bucket for total power
    struct MinuteBucket {
        let tsMinute: Int64        // Unix timestamp floored to minute
        let totalMWh: Double       // Total energy in mWh
        let totalWattsAvg: Double? // Average watts (nil if unavailable)
        let isOnAC: Bool
        let batteryPercent: Double?
    }
    
    /// Minute bucket for per-app power
    struct AppMinuteBucket {
        let tsMinute: Int64
        let bundleId: String
        let appName: String?
        let mWh: Double            // Energy in mWh
        let wattsAvg: Double?      // Average watts (nil if unavailable)
        let relativeImpactSum: Double // Sum of relative impact scores
        let samplesCount: Int
    }
    
    /// Retention period options
    enum RetentionPeriod: Int, CaseIterable {
        case hours6 = 6
        case hours24 = 24
        case days7 = 168  // 7 * 24
        
        var seconds: Int64 {
            Int64(rawValue) * 3600
        }
        
        var title: String {
            switch self {
            case .hours6: return "6 hours"
            case .hours24: return "24 hours"
            case .days7: return "7 days"
            }
        }
    }
    
    // MARK: - Properties
    
    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.powerwatt.usagestore", qos: .utility)
    
    /// Retention period (default 24 hours)
    var retentionPeriod: RetentionPeriod = .hours24
    
    /// Singleton instance
    static let shared = UsageStore()
    
    // MARK: - Initialization
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("PowerWatt", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        dbPath = appDir.appendingPathComponent("usage.sqlite").path
        
        openDatabase()
        createTables()
        
        // Run cleanup on init
        performCleanup()
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Database Management
    
    private func openDatabase() {
        let result = sqlite3_open(dbPath, &db)
        if result != SQLITE_OK {
            print("UsageStore: Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        // Enable WAL mode for better concurrency
        executeSQL("PRAGMA journal_mode=WAL")
        executeSQL("PRAGMA synchronous=NORMAL")
    }
    
    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    private func createTables() {
        // Total power minute buckets
        let createMinuteBuckets = """
            CREATE TABLE IF NOT EXISTS minute_buckets (
                ts_minute INTEGER PRIMARY KEY,
                total_mWh REAL NOT NULL DEFAULT 0,
                total_watts_avg REAL,
                is_on_ac INTEGER NOT NULL DEFAULT 0,
                battery_pct REAL
            )
        """
        
        // Per-app minute buckets
        let createAppMinuteBuckets = """
            CREATE TABLE IF NOT EXISTS app_minute_buckets (
                ts_minute INTEGER NOT NULL,
                bundle_id TEXT NOT NULL,
                app_name TEXT,
                mWh REAL NOT NULL DEFAULT 0,
                watts_avg REAL,
                relative_impact_sum REAL NOT NULL DEFAULT 0,
                samples_count INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (ts_minute, bundle_id)
            )
        """
        
        // Indexes
        let createBundleIdIndex = """
            CREATE INDEX IF NOT EXISTS idx_app_buckets_bundle_id 
            ON app_minute_buckets(bundle_id)
        """
        
        let createTsIndex = """
            CREATE INDEX IF NOT EXISTS idx_app_buckets_ts 
            ON app_minute_buckets(ts_minute)
        """
        
        executeSQL(createMinuteBuckets)
        executeSQL(createAppMinuteBuckets)
        executeSQL(createBundleIdIndex)
        executeSQL(createTsIndex)
    }
    
    @discardableResult
    private func executeSQL(_ sql: String) -> Bool {
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        
        if result != SQLITE_OK {
            if let msg = errMsg {
                print("UsageStore SQL error: \(String(cString: msg))")
                sqlite3_free(msg)
            }
            return false
        }
        return true
    }
    
    // MARK: - Insert/Update
    
    /// Insert or update a minute bucket for total power
    func upsertMinuteBucket(
        tsMinute: Int64,
        totalMWh: Double,
        totalWattsAvg: Double?,
        isOnAC: Bool,
        batteryPercent: Double?
    ) {
        queue.async { [weak self] in
            self?.doUpsertMinuteBucket(
                tsMinute: tsMinute,
                totalMWh: totalMWh,
                totalWattsAvg: totalWattsAvg,
                isOnAC: isOnAC,
                batteryPercent: batteryPercent
            )
        }
    }
    
    private func doUpsertMinuteBucket(
        tsMinute: Int64,
        totalMWh: Double,
        totalWattsAvg: Double?,
        isOnAC: Bool,
        batteryPercent: Double?
    ) {
        let sql = """
            INSERT INTO minute_buckets (ts_minute, total_mWh, total_watts_avg, is_on_ac, battery_pct)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(ts_minute) DO UPDATE SET
                total_mWh = total_mWh + excluded.total_mWh,
                total_watts_avg = COALESCE(
                    (total_watts_avg * samples_count + excluded.total_watts_avg) / (samples_count + 1),
                    excluded.total_watts_avg
                ),
                is_on_ac = excluded.is_on_ac,
                battery_pct = excluded.battery_pct
        """
        
        // Note: This simplified upsert adds mWh and updates latest values
        // A proper implementation would track sample counts for averaging
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, tsMinute)
        sqlite3_bind_double(stmt, 2, totalMWh)
        
        if let watts = totalWattsAvg {
            sqlite3_bind_double(stmt, 3, watts)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        
        sqlite3_bind_int(stmt, 4, isOnAC ? 1 : 0)
        
        if let pct = batteryPercent {
            sqlite3_bind_double(stmt, 5, pct)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        
        sqlite3_step(stmt)
    }
    
    /// Insert or update an app minute bucket
    func upsertAppMinuteBucket(
        tsMinute: Int64,
        bundleId: String,
        appName: String?,
        mWh: Double,
        wattsAvg: Double?,
        relativeImpact: Double
    ) {
        queue.async { [weak self] in
            self?.doUpsertAppMinuteBucket(
                tsMinute: tsMinute,
                bundleId: bundleId,
                appName: appName,
                mWh: mWh,
                wattsAvg: wattsAvg,
                relativeImpact: relativeImpact
            )
        }
    }
    
    private func doUpsertAppMinuteBucket(
        tsMinute: Int64,
        bundleId: String,
        appName: String?,
        mWh: Double,
        wattsAvg: Double?,
        relativeImpact: Double
    ) {
        let sql = """
            INSERT INTO app_minute_buckets (ts_minute, bundle_id, app_name, mWh, watts_avg, relative_impact_sum, samples_count)
            VALUES (?, ?, ?, ?, ?, ?, 1)
            ON CONFLICT(ts_minute, bundle_id) DO UPDATE SET
                app_name = COALESCE(excluded.app_name, app_name),
                mWh = mWh + excluded.mWh,
                watts_avg = CASE
                    WHEN watts_avg IS NULL THEN excluded.watts_avg
                    WHEN excluded.watts_avg IS NULL THEN watts_avg
                    ELSE (watts_avg * samples_count + excluded.watts_avg) / (samples_count + 1)
                END,
                relative_impact_sum = relative_impact_sum + excluded.relative_impact_sum,
                samples_count = samples_count + 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, tsMinute)
        sqlite3_bind_text(stmt, 2, bundleId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        if let name = appName {
            sqlite3_bind_text(stmt, 3, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        
        sqlite3_bind_double(stmt, 4, mWh)
        
        if let watts = wattsAvg {
            sqlite3_bind_double(stmt, 5, watts)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        
        sqlite3_bind_double(stmt, 6, relativeImpact)
        
        sqlite3_step(stmt)
    }
    
    // MARK: - Query
    
    /// Get minute buckets for a time range
    func getMinuteBuckets(from startTs: Int64, to endTs: Int64, completion: @escaping ([MinuteBucket]) -> Void) {
        queue.async { [weak self] in
            let buckets = self?.doGetMinuteBuckets(from: startTs, to: endTs) ?? []
            DispatchQueue.main.async {
                completion(buckets)
            }
        }
    }
    
    private func doGetMinuteBuckets(from startTs: Int64, to endTs: Int64) -> [MinuteBucket] {
        let sql = """
            SELECT ts_minute, total_mWh, total_watts_avg, is_on_ac, battery_pct
            FROM minute_buckets
            WHERE ts_minute >= ? AND ts_minute <= ?
            ORDER BY ts_minute ASC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, startTs)
        sqlite3_bind_int64(stmt, 2, endTs)
        
        var buckets: [MinuteBucket] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tsMinute = sqlite3_column_int64(stmt, 0)
            let totalMWh = sqlite3_column_double(stmt, 1)
            let totalWattsAvg: Double? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? sqlite3_column_double(stmt, 2) : nil
            let isOnAC = sqlite3_column_int(stmt, 3) != 0
            let batteryPct: Double? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? sqlite3_column_double(stmt, 4) : nil
            
            buckets.append(MinuteBucket(
                tsMinute: tsMinute,
                totalMWh: totalMWh,
                totalWattsAvg: totalWattsAvg,
                isOnAC: isOnAC,
                batteryPercent: batteryPct
            ))
        }
        
        return buckets
    }
    
    /// Get app minute buckets for a time range
    func getAppMinuteBuckets(from startTs: Int64, to endTs: Int64, completion: @escaping ([AppMinuteBucket]) -> Void) {
        queue.async { [weak self] in
            let buckets = self?.doGetAppMinuteBuckets(from: startTs, to: endTs) ?? []
            DispatchQueue.main.async {
                completion(buckets)
            }
        }
    }
    
    private func doGetAppMinuteBuckets(from startTs: Int64, to endTs: Int64) -> [AppMinuteBucket] {
        let sql = """
            SELECT ts_minute, bundle_id, app_name, mWh, watts_avg, relative_impact_sum, samples_count
            FROM app_minute_buckets
            WHERE ts_minute >= ? AND ts_minute <= ?
            ORDER BY ts_minute ASC, mWh DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, startTs)
        sqlite3_bind_int64(stmt, 2, endTs)
        
        var buckets: [AppMinuteBucket] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tsMinute = sqlite3_column_int64(stmt, 0)
            let bundleId = String(cString: sqlite3_column_text(stmt, 1))
            let appName: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ?
                String(cString: sqlite3_column_text(stmt, 2)) : nil
            let mWh = sqlite3_column_double(stmt, 3)
            let wattsAvg: Double? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? sqlite3_column_double(stmt, 4) : nil
            let relativeImpactSum = sqlite3_column_double(stmt, 5)
            let samplesCount = Int(sqlite3_column_int(stmt, 6))
            
            buckets.append(AppMinuteBucket(
                tsMinute: tsMinute,
                bundleId: bundleId,
                appName: appName,
                mWh: mWh,
                wattsAvg: wattsAvg,
                relativeImpactSum: relativeImpactSum,
                samplesCount: samplesCount
            ))
        }
        
        return buckets
    }
    
    /// Get app minute buckets for a specific app
    func getAppMinuteBuckets(bundleId: String, from startTs: Int64, to endTs: Int64, completion: @escaping ([AppMinuteBucket]) -> Void) {
        queue.async { [weak self] in
            let buckets = self?.doGetAppMinuteBuckets(bundleId: bundleId, from: startTs, to: endTs) ?? []
            DispatchQueue.main.async {
                completion(buckets)
            }
        }
    }
    
    private func doGetAppMinuteBuckets(bundleId: String, from startTs: Int64, to endTs: Int64) -> [AppMinuteBucket] {
        let sql = """
            SELECT ts_minute, bundle_id, app_name, mWh, watts_avg, relative_impact_sum, samples_count
            FROM app_minute_buckets
            WHERE bundle_id = ? AND ts_minute >= ? AND ts_minute <= ?
            ORDER BY ts_minute ASC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, bundleId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int64(stmt, 2, startTs)
        sqlite3_bind_int64(stmt, 3, endTs)
        
        var buckets: [AppMinuteBucket] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tsMinute = sqlite3_column_int64(stmt, 0)
            let bundleId = String(cString: sqlite3_column_text(stmt, 1))
            let appName: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL ?
                String(cString: sqlite3_column_text(stmt, 2)) : nil
            let mWh = sqlite3_column_double(stmt, 3)
            let wattsAvg: Double? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? sqlite3_column_double(stmt, 4) : nil
            let relativeImpactSum = sqlite3_column_double(stmt, 5)
            let samplesCount = Int(sqlite3_column_int(stmt, 6))
            
            buckets.append(AppMinuteBucket(
                tsMinute: tsMinute,
                bundleId: bundleId,
                appName: appName,
                mWh: mWh,
                wattsAvg: wattsAvg,
                relativeImpactSum: relativeImpactSum,
                samplesCount: samplesCount
            ))
        }
        
        return buckets
    }
    
    /// Get aggregated app summaries for a time range
    func getAppSummaries(from startTs: Int64, to endTs: Int64, completion: @escaping ([AppPowerSummary]) -> Void) {
        queue.async { [weak self] in
            let summaries = self?.doGetAppSummaries(from: startTs, to: endTs) ?? []
            DispatchQueue.main.async {
                completion(summaries)
            }
        }
    }
    
    private func doGetAppSummaries(from startTs: Int64, to endTs: Int64) -> [AppPowerSummary] {
        let sql = """
            SELECT 
                bundle_id,
                MAX(app_name) as app_name,
                SUM(mWh) / 1000.0 as energy_wh,
                AVG(watts_avg) as avg_watts,
                MAX(watts_avg) as peak_watts,
                COUNT(DISTINCT ts_minute) as active_minutes,
                SUM(relative_impact_sum) as total_relative
            FROM app_minute_buckets
            WHERE ts_minute >= ? AND ts_minute <= ?
            GROUP BY bundle_id
            ORDER BY energy_wh DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, startTs)
        sqlite3_bind_int64(stmt, 2, endTs)
        
        var summaries: [AppPowerSummary] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let bundleId = String(cString: sqlite3_column_text(stmt, 0))
            let appName: String? = sqlite3_column_type(stmt, 1) != SQLITE_NULL ?
                String(cString: sqlite3_column_text(stmt, 1)) : nil
            let energyWh = sqlite3_column_double(stmt, 2)
            let avgWatts: Double? = sqlite3_column_type(stmt, 3) != SQLITE_NULL ? sqlite3_column_double(stmt, 3) : nil
            let peakWatts: Double? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? sqlite3_column_double(stmt, 4) : nil
            let activeMinutes = Int(sqlite3_column_int(stmt, 5))
            let totalRelative = sqlite3_column_double(stmt, 6)
            
            summaries.append(AppPowerSummary(
                bundleId: bundleId,
                appName: appName,
                energyWh: energyWh,
                avgWatts: avgWatts,
                peakWatts: peakWatts,
                activeMinutes: activeMinutes,
                totalRelativeScore: totalRelative
            ))
        }
        
        return summaries
    }
    
    // MARK: - Cleanup
    
    /// Perform cleanup of old data
    func performCleanup() {
        queue.async { [weak self] in
            self?.doPerformCleanup()
        }
    }
    
    private func doPerformCleanup() {
        let cutoff = Int64(Date().timeIntervalSince1970) - retentionPeriod.seconds
        
        executeSQL("DELETE FROM minute_buckets WHERE ts_minute < \(cutoff)")
        executeSQL("DELETE FROM app_minute_buckets WHERE ts_minute < \(cutoff)")
        
        // Vacuum periodically (expensive, so don't do every time)
        // executeSQL("VACUUM")
    }
}

// MARK: - Synchronous Query Extensions

extension UsageStore {
    /// Get minute buckets synchronously (for testing/debugging)
    func getMinuteBucketsSync(from startTs: Int64, to endTs: Int64) -> [MinuteBucket] {
        var result: [MinuteBucket] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        getMinuteBuckets(from: startTs, to: endTs) { buckets in
            result = buckets
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
    
    /// Get app summaries synchronously
    func getAppSummariesSync(from startTs: Int64, to endTs: Int64) -> [AppPowerSummary] {
        var result: [AppPowerSummary] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        getAppSummaries(from: startTs, to: endTs) { summaries in
            result = summaries
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
}

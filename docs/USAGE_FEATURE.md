# Usage Feature Documentation

This document explains the power usage tracking feature in PowerWatt, including how data is collected, stored, and displayed.

## Overview

The Usage feature provides visibility into:
1. **Total system power** consumption over time (when available)
2. **Per-app energy** consumption over the last 24 hours
3. **Top energy consumers** ranked by usage

## Architecture

### Data Collection Pipeline

```
TotalPowerService ────────┐
                          │
ProcessMetricsService ────┼──► PowerAttributionService ──► MinuteBucketAggregator ──► UsageStore (SQLite)
                          │
EnergyImpactService ──────┘
```

### Services

#### TotalPowerService
Extracts total system power in watts using these sources (in priority order):
1. **IORegistry SystemPower** - Direct system power reading from AppleSmartBattery
2. **Battery-derived watts** - Calculated as `voltage × current` when discharging on battery
3. **Unavailable** - When neither source provides reliable data

Note: On AC power at 100% battery, total watts may be unavailable on some systems.

#### ProcessMetricsService
Collects per-process metrics using `proc_pid_rusage`:
- CPU time (user + system)
- Interrupt wakeups
- Disk I/O (bytes read/written)
- Network I/O (when available)

Processes are enumerated via `NSWorkspace.shared.runningApplications` for user-facing apps, with an optional toggle to include background processes.

#### EnergyImpactService
Computes energy impact scores using weighted feature shares:

```
score(app) = cpuWeight × cpuShare + wakeupsWeight × wakeupsShare + diskWeight × diskShare + networkWeight × networkShare
```

Default coefficients:
- CPU: 0.70
- Wakeups: 0.10
- Disk: 0.15
- Network: 0.05

The service attempts to load system coefficients from `/usr/share/pmenergy/` and falls back to defaults if unavailable.

#### PowerAttributionService
Combines total power with energy impact scores:
```
estimatedWatts(app) = totalWatts × normalizedScore(app)
```

When `totalWatts` is unavailable, only relative scores are provided.

### Storage

#### SQLite Schema

**minute_buckets** - Total power per minute
| Column | Type | Description |
|--------|------|-------------|
| ts_minute | INTEGER | Unix timestamp (floored to minute) |
| total_mWh | REAL | Total energy in milliwatt-hours |
| total_watts_avg | REAL | Average watts (nullable) |
| is_on_ac | INTEGER | Whether on AC power |
| battery_pct | REAL | Battery percentage (nullable) |

**app_minute_buckets** - Per-app power per minute
| Column | Type | Description |
|--------|------|-------------|
| ts_minute | INTEGER | Unix timestamp |
| bundle_id | TEXT | App bundle identifier |
| app_name | TEXT | Display name |
| mWh | REAL | Energy in milliwatt-hours |
| watts_avg | REAL | Average watts (nullable) |
| relative_impact_sum | REAL | Cumulative relative score |
| samples_count | INTEGER | Number of samples aggregated |

#### Retention
Data retention is configurable:
- 6 hours
- 24 hours (default)
- 7 days

Cleanup runs on app launch and periodically during operation.

## UI Components

### UsageView
Main view with:
- Time range selector (15m, 1h, 6h, 24h)
- Watts/Relative toggle
- Total power line chart
- Per-app stacked energy chart
- Top consumers table

### Charts
- **TotalPowerChart**: Line chart with area fill showing total system power
- **AppStackedEnergyChart**: Stacked area chart for top N apps + "Others"
- **AppDetailView**: Drilldown view with per-app power and energy charts

## Limitations

### Total Watts Availability
- May be unavailable on AC power at 100% battery
- Depends on hardware and macOS version
- Some Macs don't expose SystemPower in IORegistry

### Per-App Attribution
- Estimates based on CPU, disk, and wakeups activity
- Does not include GPU power attribution
- Network power attribution is best-effort
- Attribution is proportional, not absolute

### Privacy
- All data stored locally
- No per-app data transmitted via telemetry
- Only aggregate statistics shared (if telemetry enabled):
  - Number of tracked apps
  - Total watts coverage percentage
  - View opened events

## Configuration

### Sampling Interval
Configurable from 2-10 seconds. Lower values provide more granular data but may increase CPU usage.

### Energy Weights
Advanced users can customize the energy impact weights in Preferences → Advanced → Configure Energy Weights.

### Background Processes
Optionally include non-app processes in tracking. This may increase resource usage.

## Performance

### CPU Overhead
Target: <1% average CPU on idle systems

Controls:
- Configurable sampling interval (2-10s)
- Optional background process filtering
- Minute bucket aggregation to minimize storage writes

### Storage
Approximate sizes:
- 24h retention: ~1-5 MB
- 7 day retention: ~10-30 MB

## Troubleshooting

### "Total watts unavailable"
This means the system couldn't provide reliable total power data. Possible causes:
- On AC power at 100% battery
- Hardware doesn't expose SystemPower
- IORegistry read failed

The app will still show relative energy impact scores.

### Missing apps in charts
Apps must have measurable activity (CPU, disk, or wakeups) to appear. Idle apps with no activity won't be tracked.

### High CPU usage
Try increasing the sampling interval in Preferences → Usage Tracking → Sampling interval.

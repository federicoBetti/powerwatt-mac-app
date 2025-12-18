# Validation Guide

This document provides steps to validate the Usage feature against Activity Monitor and test various scenarios.

## Comparing with Activity Monitor

### Setup
1. Open PowerWatt and navigate to Power Usage (via menu bar → Power Usage…)
2. Open Activity Monitor and select the Energy tab
3. Set both to similar time ranges (Activity Monitor shows last 12 hours)

### Test Scenario 1: CPU-Heavy App
1. Start a CPU-intensive task (e.g., video encoding, compilation)
2. Wait 2-3 minutes for data to accumulate
3. Compare rankings:
   - PowerWatt: Check Top Consumers list
   - Activity Monitor: Check Energy Impact column

**Expected Result**: The CPU-heavy app should appear in top 3 in both tools.

### Test Scenario 2: Disk-Heavy Operation
1. Copy a large file (e.g., several GB)
2. Wait for the operation to complete
3. Compare which apps show high energy usage

**Expected Result**: Finder or the copying application should show elevated energy impact in both tools.

### Test Scenario 3: Mixed Workload
1. Open several apps: browser with multiple tabs, IDE, terminal
2. Perform normal work for 10-15 minutes
3. Compare the ranking of top 5 apps

**Expected Result**: Rankings should be broadly similar, though not identical due to different measurement methodologies.

## Total Watts Behavior

### Test Case 1: On Battery (Discharging)
1. Disconnect from power adapter
2. Wait for battery to start discharging
3. Check Power Usage view

**Expected Result**:
- Total watts should be displayed (non-nil)
- Source should show "Battery Derived" or "System Power (IORegistry)"
- Values should be plausible (typically 5-50W for normal use)

### Test Case 2: On AC (Charging)
1. Connect power adapter
2. Ensure battery is below 100%
3. Check Power Usage view

**Expected Result**:
- Total watts may or may not be available (depends on hardware)
- If available, source should show "System Power (IORegistry)"
- Per-app watts may show as estimated or relative

### Test Case 3: On AC at 100%
1. Connect power adapter
2. Wait for battery to reach 100%
3. Check Power Usage view

**Expected Result**:
- Total watts may be unavailable
- UI should show "Total watts unavailable" message
- Per-app data should show relative scores instead

## Data Integrity

### Test Case 1: App Restart
1. Open Power Usage and note current data
2. Quit and restart PowerWatt
3. Reopen Power Usage

**Expected Result**:
- Historical data should be preserved
- Charts should still load
- No data loss from the restart

### Test Case 2: Retention Cleanup
1. Set retention to 6 hours
2. Wait for cleanup to run (or restart app)
3. Check that data older than 6 hours is removed

**Expected Result**:
- Only recent 6 hours of data visible
- Older data removed from charts and database

### Test Case 3: Sampling Under Load
1. Start multiple resource-intensive apps
2. Verify sampling continues
3. Check CPU usage of PowerWatt itself

**Expected Result**:
- PowerWatt should remain under 1% CPU average
- Sampling should continue without gaps
- UI should remain responsive

## Accuracy Validation

### Comparing Energy Values
While exact matches aren't expected, the following sanity checks apply:

1. **Order of magnitude**: Total watts should typically be 5-100W for normal laptop usage
2. **Sum consistency**: Sum of per-app estimated watts should approximately equal total watts
3. **Relative ranking**: High-activity apps should consistently rank higher than idle apps

### Known Differences from Activity Monitor
- Activity Monitor has access to private APIs with more detailed data
- Activity Monitor includes GPU power attribution
- PowerWatt's coefficients may differ from Apple's internal weights
- Timing and aggregation windows may differ

## Checklist

### Basic Functionality
- [ ] Power Usage window opens from menu
- [ ] Time range selector works (15m, 1h, 6h, 24h)
- [ ] Charts render correctly
- [ ] Top consumers list populates
- [ ] App detail view opens on click

### Data Quality
- [ ] Total watts shows when on battery
- [ ] Per-app scores sum to approximately 1.0
- [ ] Historical data persists across restarts
- [ ] Cleanup respects retention settings

### UI/UX
- [ ] Charts remain responsive with 24h of data
- [ ] App icons display correctly
- [ ] Reveal in Finder works
- [ ] Quit app works (graceful termination)

### Settings Integration
- [ ] Enable/disable tracking works
- [ ] Sampling interval changes take effect
- [ ] Retention period changes trigger cleanup
- [ ] Custom coefficients apply correctly

### Privacy
- [ ] No per-app data in telemetry events
- [ ] All data stored in local SQLite database
- [ ] Database location in Application Support

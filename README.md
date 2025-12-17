# PowerWatt - macOS Menu Bar Battery Power Monitor

A sleek menu bar app for macOS that displays real-time battery power consumption and charging status with customizable settings.

## Features

### 🔋 Real-time Power Monitoring
- **Display Mode**: Choose how power is shown in the menu bar
  - **Net Only (default)**: Shows net power. When charging, IN−OUT (positive = green). When discharging, −OUT (negative = red). Displayed as absolute watts with color indicating direction.
  - **Separate IN and OUT**: Shows IN and OUT side-by-side (IN only appears when charging), with icons and colors.
- **IN/OUT Wattage**: Uses IOKit readings to compute watts
- **Visual Indicators**: Color-coded icons (green for charging, red for discharging)
- **Battery Percentage**: Optional display next to the label

### ⚙️ Customizable Settings
- **Refresh Interval**: Adjustable from 1 to 60 seconds (**default: 2s**)
- **Label Styles**: Choose from three display formats:
  - Icon + Watts (default)
  - Watts Only
  - IN/OUT + Watts
- **Decimal Precision**: 0-2 decimal places for power values
- **Color Coding**: Toggle colored indicators on/off
- **Battery Percentage**: Show battery percentage in menu bar
- **Smoothing**: Time-based averaging to reduce flicker (0-30 seconds)
- **Display Mode**: Net Only or Separate IN/OUT
- **Battery Capacity**: Shows the detected battery capacity in Wh with info button (Preferences → Advanced)

### 🚀 System Integration
- **Menu Bar App**: No dock icon, runs in the background
- **Open at Login**: Automatic startup option
- **Settings Window**: Full preferences panel accessible from menu

## Installation

### Requirements
- macOS 15.2 or later
- Xcode 16.2+ (for building from source)

### Build from Source
```bash
git clone git@github.com:federicoBetti/powerwatt-mac-app.git
cd powerwatt-mac-app
open PowerWatt.xcodeproj
```

1. Open the project in Xcode
2. Select "PowerWatt" scheme and "My Mac" destination
3. Press ⌘+R to build and run

### Distribution
For distribution, build a Release version and codesign the app. Place in `/Applications` for best "Open at Login" compatibility.

## GitHub Pages (download site)

This repository is set up to serve a public download page (and Sparkle appcast) from the `/docs` folder.

### Enable GitHub Pages (one-time)
1. Open the repo on GitHub → **Settings** → **Pages**.
2. Under **Build and deployment**, choose **Deploy from a branch**.
3. Select branch **main** and folder **/docs**, then save.

### Expected URLs
- Site: `https://federicoBetti.github.io/powerwatt-mac-app/`
- Appcast: `https://federicoBetti.github.io/powerwatt-mac-app/appcast.xml`

## fbetti.com download page (next steps)

This work happens outside the repo, but keeping the checklist here makes it harder to forget:

- [ ] Create a public-facing Download page on `fbetti.com`.
- [ ] Point the main call-to-action button to `https://github.com/federicoBetti/powerwatt-mac-app/releases/latest/download/PowerWatt.dmg`.
- [ ] Mirror the same install instructions and privacy summary that appear on `docs/index.html` / `docs/privacy.html`.
- [ ] (Optional) Embed a “Latest version” badge fed by the GitHub Releases API so visitors can see the current tag.

## Usage

### Menu Bar Display
The app appears as a bolt icon in your menu bar:
- **Net Only**: Single value with color indicating direction (charging positive, discharging negative)
- **Charging (Separate)**: `⚡ IN 12.3 W | ⚡ 8.7 W`
- **Discharging (Separate)**: `⚡ 8.7 W`
- **No Power**: `⚡ --.- W`

### Menu Options
Click the menu bar icon to access:
- Current power status and battery percentage
- Preferences window (opens full settings)
- Quit option

### Settings
Open Preferences to configure:
- **General**: Refresh interval and login behavior
- **Menu Bar**: Display mode, label style, decimal precision, colors, battery percentage, and display options
- **Advanced**: Smoothing window settings and battery capacity with helpful info button

## Technical Details

### Power Measurement
Uses IOKit to read `AppleSmartBattery` data:
- Voltage (mV) and Current (mA) from system battery
- Calculates power as `(voltage × current) / 1,000,000`
- Handles both positive (charging) and negative (discharging) current
- Battery capacity (Wh) estimated from `MaxCapacity/DesignCapacity` and battery voltage

### Architecture
- **SwiftUI**: Modern UI framework for menu bar and settings
- **IOKit**: Low-level system access for battery data
- **ServiceManagement**: Login item management (macOS 13+)
- **UserDefaults**: Persistent settings storage

### Files Structure
```
PowerWatt/
├── PowerWattApp.swift          # Main app with menu bar extra
├── BatteryPowerService.swift   # Power monitoring service
├── AppSettings.swift           # Settings management
├── PreferencesView.swift       # Settings UI
├── LoginItemManager.swift      # Login item handling
└── ContentView.swift           # (Legacy, unused)
```

## Development

### Building
The project uses Xcode's file system synchronization, so all Swift files in the PowerWatt directory are automatically included.

### Key Components
- **MenuBarExtra**: SwiftUI's menu bar integration
- **ObservableObject**: Reactive data binding for settings and power data
- **Timer**: Configurable polling for power updates
- **Smoothing Algorithm**: Rolling time window for stable readings
- **SettingsLink**: Modern preferences integration (macOS 14+)

## License

This project is open source. Feel free to contribute or fork for your own use.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Recent Updates

### Latest Improvements
- ✅ **Enhanced Preferences**: Larger settings window with better layout
- ✅ **Info Button**: Helpful information about battery capacity
- ✅ **Responsive Settings**: Menu bar updates immediately when settings change
- ✅ **Cleaner Menu**: Removed duplicate settings from dropdown menu
- ✅ **Modern Integration**: Uses SettingsLink for better macOS integration

## Issues

If you encounter any issues:
- Check that your Mac has a battery (not desktop-only)
- Ensure the app has necessary permissions
- For "Open at Login" issues, try a Release build in `/Applications`
- Settings changes should apply immediately - if not, try restarting the app

---

*Built with ❤️ for macOS users who want to monitor their power consumption.*

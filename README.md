# PowerWatt - macOS Menu Bar Battery Power Monitor

A sleek menu bar app for macOS that displays real-time battery power consumption and charging status with customizable settings.

## Features

### 🔋 Real-time Power Monitoring
- **IN/OUT Wattage**: Shows power being drawn from or supplied to the battery
- **Smart Display**: Shows both IN and OUT when charging, only OUT when discharging
- **Visual Indicators**: Color-coded icons (green for charging, red for discharging)
- **Battery Percentage**: Optional display of current battery level

### ⚙️ Customizable Settings
- **Refresh Interval**: Adjustable from 1 to 60 seconds (default: 5s)
- **Label Styles**: Choose from three display formats:
  - Icon + Watts (default)
  - Watts Only
  - IN/OUT + Watts
- **Decimal Precision**: 0-2 decimal places for power values
- **Color Coding**: Toggle colored indicators on/off
- **Smoothing**: Time-based averaging to reduce display flicker

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
git clone git@github.com:federicoBetti/powerwatt-mac.git
cd powerwatt-mac
open PowerWatt.xcodeproj
```

1. Open the project in Xcode
2. Select "PowerWatt" scheme and "My Mac" destination
3. Press ⌘+R to build and run

### Distribution
For distribution, build a Release version and codesign the app. Place in `/Applications` for best "Open at Login" compatibility.

## Usage

### Menu Bar Display
The app appears as a bolt icon in your menu bar:
- **Charging**: Shows both IN and OUT values with icons
  - `⚡ IN 12.3 W | ⚡ 8.7 W`
- **Discharging**: Shows only OUT value
  - `⚡ 8.7 W`
- **No Power**: Shows `⚡ --.- W`

### Menu Options
Click the menu bar icon to access:
- Current power status and battery percentage
- Quick refresh interval adjustment
- "Open at Login" toggle
- Preferences window
- Quit option

### Settings
Open Preferences to configure:
- **General**: Refresh interval and login behavior
- **Menu Bar**: Display style, precision, colors, and battery percentage
- **Advanced**: Smoothing window settings

## Technical Details

### Power Measurement
Uses IOKit to read `AppleSmartBattery` data:
- Voltage (mV) and Current (mA) from system battery
- Calculates power as `(voltage × current) / 1,000,000`
- Handles both positive (charging) and negative (discharging) current

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

## License

This project is open source. Feel free to contribute or fork for your own use.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Issues

If you encounter any issues:
- Check that your Mac has a battery (not desktop-only)
- Ensure the app has necessary permissions
- For "Open at Login" issues, try a Release build in `/Applications`

---

*Built with ❤️ for macOS users who want to monitor their power consumption.*

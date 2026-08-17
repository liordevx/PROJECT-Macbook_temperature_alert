# macOS CPU Temperature Monitor & Alert App

A native, ultra-lightweight macOS Menu Bar application built with **SwiftUI** and **Swift Charts** that monitors CPU temperature in real time, displays historical temperature trends, and delivers native system notifications when high temperature thresholds are crossed.

---

## 🌟 Features
- **Live Menu Bar Status**: Displays current CPU temperature and a dynamic status icon (thermometer / flame) right in the macOS menu bar.
- **Interactive Popover & Chart**: Clicking the menu bar item opens a clean SwiftUI popover featuring a real-time temperature graph built using `Swift Charts`.
- **Pure Swift IOHID Integration**: Interacts directly with undocumented Apple private frameworks (`IOHIDEventSystemClient`) to query CPU hardware sensors without requiring external C bridge headers or native binary dependencies.
- **Smart Notifications**: Sends native macOS `UNUserNotificationCenter` time-sensitive alerts when CPU temperature reaches or exceeds 80°C, with built-in cooldown logic (5-minute buffer) to prevent notification spam.
- **Zero Dock Footprint**: Configured programmatically with `NSApplication.ActivationPolicy.accessory` to run purely as a background agent without cluttering the macOS Dock.
- **Resource Efficient**: Consumes ~0.0% CPU and ~35MB Memory with zero disk I/O.

---

## 🏗️ Architecture & How It Works

```
  [Apple IOHID Sensors]
           │
           ▼ (Every 20s via C-Bindings `@_silgen_name`)
  [TemperatureMonitor] ──▶ (Notification Engine) ──▶ macOS Notification Center (>= 80°C)
           │
           ▼ (ObservableObject State)
   [SwiftUI MenuBarExtra] ──▶ [Swift Charts UI Popover]
```

### 1. Hardware Sensor Access (`IOHID` C-Bindings)
macOS does not provide a public API for reading CPU sensor temperatures. The app uses low-level `@_silgen_name` attributes in Swift to bind directly to private Apple `CoreFoundation` / `IOHID` APIs:
- `IOHIDEventSystemClientCreate`
- `IOHIDEventSystemClientCopyServices`
- `IOHIDServiceClientCopyEvent`
- `IOHIDEventGetFloatValue`

The sensor events are filtered for temperature types (`kIOHIDEventTypeTemperature = 15`, `kIOHIDEventFieldTemperature = 983040`) across all system thermal sensors to extract the maximum current CPU core temperature.

### 2. State & Monitoring (`TemperatureMonitor`)
- An `ObservableObject` singleton initializes a timer to poll the CPU sensors every 20 seconds.
- Memory management is explicitly handled with `Unmanaged.release()` on CoreFoundation event pointers to guarantee zero memory leaks.
- A rolling history array (`history`) stores up to 30 data points to fuel the interactive UI chart.

### 3. User Interface (`SwiftUI` & `Swift Charts`)
- **`MenuBarExtra`**: Replaces standard application windows with a native system menu bar item.
- **`ContentView`**: Houses a `Chart` component configured with `LineMark` and `AreaMark` gradient fills. The Y-axis scale (`yDomain`) dynamically calculates lower and upper bounds based on active history to keep graph curves centered and legible.

---

## 🛠️ How It Was Built
1. **Initial Concept & Prototyping**: Explored C-language sensor reading (`temperature_reader.c`) and Python `ctypes` polling (`main.py`).
2. **Swift Native Porting**: Translated private C-bindings into pure Swift (`@_silgen_name`) to eliminate external framework dependencies and complex Xcode bridging header setups.
3. **SwiftUI MenuBarExtra**: Implemented modern macOS SwiftUI menu bar popovers.
4. **App Icon & Asset Generation**: Generated custom app icon assets (vibrant red flame design) and configured `.appiconset` for all macOS resolutions (16x16 up to 1024x1024).
5. **Optimization**: Configured `.accessory` activation policy for zero Dock presence and added a 5-minute notification cooldown buffer.

---

## 🚀 Installation & Usage

### Running Standalone (.app)
1. Copy `temperature_alert.app` to your `/Applications` directory.
2. Double-click to launch.
3. (Optional) Add to **System Settings -> General -> Login Items** to start automatically upon Mac startup.

### Building from Source (Xcode)
1. Open `temperature_alert/temperature_alert.xcodeproj` in Xcode.
2. Select the `temperature_alert` scheme and target **My Mac**.
3. Press `Cmd + R` to build and run.

---
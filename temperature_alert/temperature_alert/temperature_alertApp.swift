import SwiftUI

@main
struct temperature_alertApp: App {
    @StateObject private var monitor = TemperatureMonitor()
    
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
    
    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            HStack {
                Image(systemName: monitor.currentTemperature >= 80.0 ? "flame.fill" : "thermometer")
                Text(String(format: "%.0f°", monitor.currentTemperature))
            }
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI
import Charts
import CoreFoundation
import UserNotifications

// MARK: - Private IOHID Bindings (Pure Swift)
let kIOHIDEventTypeTemperature: Int64 = 15
let kIOHIDEventFieldTemperature: Int32 = 983040

@_silgen_name("IOHIDEventSystemClientCreate")
func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> OpaquePointer?

@_silgen_name("IOHIDEventSystemClientCopyServices")
func IOHIDEventSystemClientCopyServices(_ client: OpaquePointer, _ matching: CFDictionary?) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyEvent")
func IOHIDServiceClientCopyEvent(_ service: OpaquePointer, _ type: Int64, _ options: Int32, _ sender: Int64) -> OpaquePointer?

@_silgen_name("IOHIDEventGetFloatValue")
func IOHIDEventGetFloatValue(_ event: OpaquePointer, _ field: Int32) -> Double

// MARK: - Notification Delegate
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Ensure notification shows even if the app is considered "active"
        completionHandler([.banner, .sound, .badge])
    }
}

// MARK: - Temperature Data Model
struct TemperatureDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let temperature: Double
}

// MARK: - Temperature Monitor
class TemperatureMonitor: ObservableObject {
    @Published var currentTemperature: Double = 0.0
    @Published var history: [TemperatureDataPoint] = []
    
    private var timer: Timer?
    private var client: OpaquePointer?
    private var lastAlertTime: Date?
    
    // 30 points * 2 seconds = 60 seconds of history
    let maxHistoryItems = 30
    
    // Notification delegate reference to keep it alive
    private let notifDelegate = NotificationDelegate()
    
    init() {
        self.client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        
        // Request notification permissions
        UNUserNotificationCenter.current().delegate = notifDelegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted.")
            }
        }
        
        startMonitoring()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func startMonitoring() {
        // Initial read
        updateTemperature()
        
        // Timer to read every 20 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            self?.updateTemperature()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    private func updateTemperature() {
        guard let client = client else { return }
        guard let servicesArray = IOHIDEventSystemClientCopyServices(client, nil) else { return }
        
        let count = CFArrayGetCount(servicesArray)
        var maxTemp = 0.0
        
        for i in 0..<count {
            guard let serviceRaw = CFArrayGetValueAtIndex(servicesArray, i) else { continue }
            let servicePtr = OpaquePointer(serviceRaw)
            
            if let event = IOHIDServiceClientCopyEvent(servicePtr, kIOHIDEventTypeTemperature, 0, 0) {
                let temp = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperature)
                if temp > maxTemp && temp < 120.0 {
                    maxTemp = temp
                }
                Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(event)).release()
            }
        }
        
        if maxTemp > 0 {
            DispatchQueue.main.async {
                self.currentTemperature = maxTemp
                self.history.append(TemperatureDataPoint(timestamp: Date(), temperature: maxTemp))
                
                if self.history.count > self.maxHistoryItems {
                    self.history.removeFirst()
                }
                
                // Trigger notification if >= 80.0 and at least 300 seconds (5 mins) passed since last alert
                if maxTemp >= 80.0 {
                    let now = Date()
                    if self.lastAlertTime == nil || now.timeIntervalSince(self.lastAlertTime!) > 300 {
                        self.lastAlertTime = now
                        self.sendNotification(temp: maxTemp)
                    }
                }
            }
        }
    }
    
    private func sendNotification(temp: Double) {
        let content = UNMutableNotificationContent()
        content.title = "אזהרת התחממות ⚠️"
        content.body = String(format: "ה-MacBook הגיע ל-%.1f°C! 🔥", temp)
        content.sound = .default
        
        if #available(macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - UI
struct ContentView: View {
    @ObservedObject var monitor: TemperatureMonitor
    
    private var yDomain: ClosedRange<Double> {
        let temps = monitor.history.map { $0.temperature }
        guard let minT = temps.min(), let maxT = temps.max() else {
            return 30.0...90.0
        }
        let lower = max(0, minT - 3.0)
        let upper = maxT + 3.0
        // Ensure range has at least 5 degrees span
        if upper - lower < 5.0 {
            return (lower - 2.5)...(upper + 2.5)
        }
        return lower...upper
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CPU Temperature")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundColor(.secondary)
            }
            
            HStack(alignment: .center) {
                Text(String(format: "%.1f°C", monitor.currentTemperature))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(monitor.currentTemperature >= 80.0 ? .red : .primary)
                
                if monitor.currentTemperature >= 80.0 {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.red)
                }
            }
            
            if monitor.history.isEmpty {
                ProgressView()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(monitor.history) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Temperature", point.temperature)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.orange.gradient)
                        
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            yStart: .value("Baseline", yDomain.lowerBound),
                            yEnd: .value("Temperature", point.temperature)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.orange.opacity(0.25), .clear]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3))
                }
                .frame(height: 200)
            }
        }
        .padding(16)
        .padding(.bottom, 6)
        .frame(width: 310, height: 320)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let dummyMonitor = TemperatureMonitor()
        ContentView(monitor: dummyMonitor)
    }
}

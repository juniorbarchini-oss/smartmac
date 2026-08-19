import SwiftUI
import AppKit

// MARK: - App Theme Option Enum
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Smartctl Output Model
struct SmartctlOutput: Decodable {
    let modelName: String?
    let serialNumber: String?
    let firmwareVersion: String?
    let smartStatus: SmartStatus?
    let nvmeSmartHealthInformationLog: NVMESmartHealthLog?
    let device: DeviceInfo?
    
    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case serialNumber = "serial_number"
        case firmwareVersion = "firmware_version"
        case smartStatus = "smart_status"
        case nvmeSmartHealthInformationLog = "nvme_smart_health_information_log"
        case device
    }
}

struct DeviceInfo: Decodable {
    let name: String
    let protocolName: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case protocolName = "protocol"
    }
}

struct SmartStatus: Decodable {
    let passed: Bool
}

struct NVMESmartHealthLog: Decodable {
    let criticalWarning: Int
    let temperature: Int
    let availableSpare: Int
    let percentageUsed: Int
    let dataUnitsRead: Int
    let dataUnitsWritten: Int
    let powerCycles: Int
    let powerOnHours: Int
    let unsafeShutdowns: Int
    let mediaErrors: Int
    
    enum CodingKeys: String, CodingKey {
        case criticalWarning = "critical_warning"
        case temperature
        case availableSpare = "available_spare"
        case percentageUsed = "percentage_used"
        case dataUnitsRead = "data_units_read"
        case dataUnitsWritten = "data_units_written"
        case powerCycles = "power_cycles"
        case powerOnHours = "power_on_hours"
        case unsafeShutdowns = "unsafe_shutdowns"
        case mediaErrors = "media_errors"
    }
}

// MARK: - Disk Info Model (Representable on UI)
struct StorageDevice: Identifiable, Hashable {
    let id = UUID()
    let path: String // e.g. /dev/disk0
    let name: String
    let size: String
    let isRemote: Bool
    let address: String?
}

// MARK: - Local SMART Executor
class DiskScanManager: ObservableObject {
    @Published var isScanning = false
    @Published var scanError: String?
    @Published var activeScanResult: SmartctlOutput?
    @Published var detectedDisks: [StorageDevice] = []
    
    private let smartctlPath = "/opt/homebrew/bin/smartctl"
    
    init() {
        refreshDiskList()
    }
    
    func refreshDiskList() {
        let fileManager = FileManager.default
        do {
            let devContents = try fileManager.contentsOfDirectory(atPath: "/dev")
            let diskRegex = try NSRegularExpression(pattern: "^disk\\d+$")
            let physicalDisks = devContents.filter { item in
                let range = NSRange(location: 0, length: item.utf16.count)
                return diskRegex.firstMatch(in: item, options: [], range: range) != nil
            }.map { "/dev/\($0)" }.sorted()
            
            self.detectedDisks = physicalDisks.map { path in
                let isMain = path == "/dev/disk0"
                return StorageDevice(
                    path: path,
                    name: isMain ? "Macintosh SSD (\(path))" : "External USB Drive (\(path))",
                    size: isMain ? "Internal Health Check" : "External Health Check",
                    isRemote: false,
                    address: nil
                )
            }
        } catch {
            self.detectedDisks = [StorageDevice(path: "/dev/disk0", name: "Macintosh SSD (/dev/disk0)", size: "Internal Health Check", isRemote: false, address: nil)]
        }
    }
    
    func checkSmartctlAvailability() -> Bool {
        return FileManager.default.fileExists(atPath: smartctlPath)
    }
    
    @MainActor
    func runScan(on devicePath: String) async {
        isScanning = true
        scanError = nil
        activeScanResult = nil
        
        guard checkSmartctlAvailability() else {
            isScanning = false
            scanError = "smartctl binary not found. Please install it using Homebrew:\nbrew install smartmontools"
            return
        }
        
        let task = Task.detached(priority: .userInitiated) { () -> Result<SmartctlOutput, Error> in
            let process = Process()
            let pipe = Pipe()
            let errPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: self.smartctlPath)
            process.arguments = ["--all", "--json", devicePath]
            process.standardOutput = pipe
            process.standardError = errPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                // Print raw output to console for debug
                if let rawJSON = String(data: data, encoding: .utf8) {
                    print("--- Raw smartctl response ---\n", rawJSON)
                }
                
                let decoder = JSONDecoder()
                let decoded = try decoder.decode(SmartctlOutput.self, from: data)
                return .success(decoded)
            } catch {
                return .failure(error)
            }
        }
        
        let result = await task.value
        isScanning = false
        
        switch result {
        case .success(let output):
            self.activeScanResult = output
        case .failure(let error):
            self.scanError = "Failed to parse SMART data: \(error.localizedDescription)"
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @AppStorage("selectedTheme") private var selectedTheme: AppTheme = .system
    @StateObject private var scanManager = DiskScanManager()
    @State private var selectedDevice: StorageDevice?
    @State private var showSettings = false
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedDevice) {
                Section("Local Storage") {
                    ForEach(scanManager.detectedDisks, id: \.self) { device in
                        NavigationLink(value: device) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.headline)
                                    Text(device.path)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: device.path == "/dev/disk0" ? "internaldrive" : "externaldrive")
                                    .imageScale(.large)
                                    .foregroundColor(device.path == "/dev/disk0" ? .blue : .purple)
                            }
                        }
                    }
                }
                
                Section("Network Hosts (SSH Mock)") {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Synology NAS")
                                .font(.headline)
                            Text("192.168.1.100")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "server.rack")
                            .imageScale(.large)
                            .foregroundColor(.gray)
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("SmartMac")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .help("Application Settings")
                    
                    Spacer()
                    
                    Button(action: {
                        scanManager.refreshDiskList()
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding()
                }
            }
        } detail: {
            if let device = selectedDevice {
                DiskDetailView(device: device, scanManager: scanManager)
            } else {
                VStack(spacing: 15) {
                    Image(systemName: "opticaldisk")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Select a Storage Device to scan")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(selectedTheme: $selectedTheme)
        }
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}

// MARK: - Disk Detail View Component
struct DiskDetailView: View {
    let device: StorageDevice
    @ObservedObject var scanManager: DiskScanManager
    @State private var selectedTab = "overview"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Disk Header
            HStack(spacing: 15) {
                Image(systemName: device.path == "/dev/disk0" ? "internaldrive" : "externaldrive")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(scanManager.activeScanResult?.modelName ?? device.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        if let passed = scanManager.activeScanResult?.smartStatus?.passed {
                            Text(passed ? "HEALTHY" : "FAILING")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(passed ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                .foregroundColor(passed ? .green : .red)
                                .cornerRadius(5)
                        }
                    }
                    Text("Protocol: \(scanManager.activeScanResult?.device?.protocolName ?? "Unknown") | Serial: \(scanManager.activeScanResult?.serialNumber ?? "N/A")")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                if scanManager.isScanning {
                    ProgressView()
                        .padding(.trailing, 10)
                } else {
                    Button(action: {
                        Task {
                            await scanManager.runScan(on: device.path)
                        }
                    }) {
                        Label("Scan Now", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if let error = scanManager.scanError {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Diagnostic Error", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding()
            }
            
            Picker("", selection: $selectedTab) {
                Text("Overview").tag("overview")
                Text("Detailed Metrics").tag("metrics")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let result = scanManager.activeScanResult {
                        if selectedTab == "overview" {
                            RealOverviewTab(result: result)
                        } else {
                            RealMetricsTab(result: result)
                        }
                    } else {
                        VStack(spacing: 15) {
                            Image(systemName: "gauge.medium")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Press 'Scan Now' to retrieve real S.M.A.R.T. health data.")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding()
            }
            
            Spacer()
        }
    }
}

// MARK: - Real Overview Tab (Displays Decoded JSON values)
struct RealOverviewTab: View {
    let result: SmartctlOutput
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("General Health Check")
                .font(.title2)
                .fontWeight(.bold)
            
            Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 15) {
                if let log = result.nvmeSmartHealthInformationLog {
                    GridRow {
                        Text("Temperature:")
                            .fontWeight(.semibold)
                        HStack {
                            Text("\(log.temperature) °C")
                                .foregroundColor(log.temperature > 50 ? .red : (log.temperature > 40 ? .orange : .primary))
                            Image(systemName: "thermometer.medium")
                                .foregroundColor(log.temperature > 45 ? .red : .blue)
                        }
                    }
                    
                    GridRow {
                        Text("Remaining Life (Health):")
                            .fontWeight(.semibold)
                        let healthPct = 100 - log.percentageUsed
                        VStack(alignment: .leading, spacing: 5) {
                            ProgressView(value: Double(healthPct), total: 100)
                                .tint(healthPct < 20 ? .red : (healthPct < 50 ? .orange : .green))
                            Text("\(healthPct)% Remaining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    GridRow {
                        Text("Power Cycles:")
                            .fontWeight(.semibold)
                        Text("\(log.powerCycles)")
                    }
                    
                    GridRow {
                        Text("Power On Hours:")
                            .fontWeight(.semibold)
                        Text("\(log.powerOnHours) hours (~ \(log.powerOnHours / 24) days)")
                    }
                    
                    GridRow {
                        Text("Data Units Written:")
                            .fontWeight(.semibold)
                        // smartctl reports data units written in 512 byte blocks * 1000.
                        // bytes = dataUnitsWritten * 1000 * 512
                        let bytesWritten = Double(log.dataUnitsWritten) * 1000 * 512
                        let tbWritten = bytesWritten / (1024 * 1024 * 1024 * 1024)
                        Text(String(format: "%.2f TB Written", tbWritten))
                    }
                    
                    GridRow {
                        Text("Data Units Read:")
                            .fontWeight(.semibold)
                        let bytesRead = Double(log.dataUnitsRead) * 1000 * 512
                        let tbRead = bytesRead / (1024 * 1024 * 1024 * 1024)
                        Text(String(format: "%.2f TB Read", tbRead))
                    }
                } else {
                    GridRow {
                        Text("SMART Status:")
                            .fontWeight(.semibold)
                        Text(result.smartStatus?.passed == true ? "PASSED" : "FAILED")
                            .foregroundColor(result.smartStatus?.passed == true ? .green : .red)
                    }
                    Text("This drive protocol does not support NVMe standardized metrics. Check detailed logs for custom vendor attributes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }
}

// MARK: - Real Metrics Tab
struct RealMetricsTab: View {
    let result: SmartctlOutput
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hardware S.M.A.R.T. Log Values")
                .font(.title2)
                .fontWeight(.bold)
            
            if let log = result.nvmeSmartHealthInformationLog {
                List {
                    MetricRow(name: "Critical Warnings", value: "\(log.criticalWarning)", status: log.criticalWarning == 0 ? "Normal" : "WARNING", isWarning: log.criticalWarning > 0)
                    MetricRow(name: "Available Spare Space", value: "\(log.availableSpare)%", status: log.availableSpare > 10 ? "OK" : "CRITICAL", isWarning: log.availableSpare <= 10)
                    MetricRow(name: "Unsafe Shutdowns", value: "\(log.unsafeShutdowns)", status: "Informational", isWarning: false)
                    MetricRow(name: "Media and Data Integrity Errors", value: "\(log.mediaErrors)", status: log.mediaErrors == 0 ? "Normal" : "CRITICAL", isWarning: log.mediaErrors > 0)
                }
                .frame(height: 250)
                .cornerRadius(10)
            } else {
                Text("No NVMe specific health log entries parsed for this device format.")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct MetricRow: View {
    let name: String
    let value: String
    let status: String
    let isWarning: Bool
    
    var body: some View {
        HStack {
            Text(name)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
            Text(status)
                .fontWeight(.semibold)
                .foregroundColor(isWarning ? .red : .green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isWarning ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Settings View (Sheet)
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedTheme: AppTheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SmartMac Settings")
                .font(.title)
                .fontWeight(.bold)
            
            Form {
                Picker("Appearance Theme:", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(RadioGroupPickerStyle())
                .padding(.vertical, 5)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
    }
}

// MARK: - App Entrypoint
@main
struct SmartMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 850, minHeight: 600)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

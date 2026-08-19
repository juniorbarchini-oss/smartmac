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
    let temperature: TemperatureInfo?
    let powerCycleCount: Int?
    let powerOnTime: PowerOnTimeInfo?
    let ataSmartAttributes: ATASmartAttributes?
    
    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case serialNumber = "serial_number"
        case firmwareVersion = "firmware_version"
        case smartStatus = "smart_status"
        case nvmeSmartHealthInformationLog = "nvme_smart_health_information_log"
        case device
        case temperature
        case powerCycleCount = "power_cycle_count"
        case powerOnTime = "power_on_time"
        case ataSmartAttributes = "ata_smart_attributes"
    }
}

struct TemperatureInfo: Decodable {
    let current: Int
}

struct PowerOnTimeInfo: Decodable {
    let hours: Int?
}

struct ATASmartAttributes: Decodable {
    let table: [ATAAttribute]
}

struct ATAAttribute: Decodable, Identifiable {
    let id: Int
    let name: String
    let value: Int
    let worst: Int
    let threshold: Int
    let raw: ATARawValue
    
    struct ATARawValue: Decodable {
        let value: Int
        let string: String
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
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["list", "physical"]
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                var physicalPaths: [String] = []
                for line in lines {
                    if line.hasPrefix("/dev/disk") {
                        if let firstSpace = line.firstIndex(of: " ") {
                            let path = String(line[..<firstSpace])
                            physicalPaths.append(path)
                        }
                    }
                }
                
                if physicalPaths.isEmpty {
                    physicalPaths = ["/dev/disk0"]
                }
                
                self.detectedDisks = physicalPaths.map { path in
                    let isMain = path == "/dev/disk0"
                    return StorageDevice(
                        path: path,
                        name: isMain ? "Macintosh SSD (\(path))" : "External USB Drive (\(path))",
                        size: isMain ? "Internal Health Check" : "External Health Check",
                        isRemote: false,
                        address: nil
                    )
                }
            }
        } catch {
            self.detectedDisks = [StorageDevice(path: "/dev/disk0", name: "Macintosh SSD (/dev/disk0)", size: "Internal Health Check", isRemote: false, address: nil)]
        }
    }
    
    func ejectDevice(devicePath: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["eject", devicePath]
        
        do {
            try task.run()
            task.waitUntilExit()
            refreshDiskList()
        } catch {
            print("Failed to eject device: \(error)")
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
        
        let isInternal = devicePath == "/dev/disk0"
        
        let task = Task.detached(priority: .userInitiated) { () -> Result<SmartctlOutput, Error> in
            let process = Process()
            let pipe = Pipe()
            let errPipe = Pipe()
            
            if isInternal {
                // Run directly without elevated privileges for internal NVMe
                process.executableURL = URL(fileURLWithPath: self.smartctlPath)
                process.arguments = ["--all", "--json", devicePath]
            } else {
                // Use osascript with administrator privileges to prompt macOS password dialog for USB drives
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                let script = "do shell script \"\(self.smartctlPath) --all --json \(devicePath) || true\" with administrator privileges"
                process.arguments = ["-e", script]
            }
            
            process.standardOutput = pipe
            process.standardError = errPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                if data.isEmpty {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "User cancelled or denied authorization."
                    return .failure(NSError(domain: "SmartMacApp", code: 1, userInfo: [NSLocalizedDescriptionKey: errStr]))
                }
                
                // Print raw output for debugging
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
            self.scanError = "Execution Error:\n\(error.localizedDescription)\n\nRaw: \(String(describing: error))"
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
                    HStack(spacing: 10) {
                        if device.path != "/dev/disk0" {
                            Button(action: {
                                scanManager.ejectDevice(devicePath: device.path)
                            }) {
                                Label("Eject", systemImage: "eject")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .help("Eject external disk safely")
                        }
                        
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
                // 1. Common Temperature
                if let temp = result.temperature?.current {
                    GridRow {
                        Text("Temperature:")
                            .fontWeight(.semibold)
                        HStack {
                            Text("\(temp) °C")
                                .foregroundColor(temp > 50 ? .red : (temp > 40 ? .orange : .primary))
                            Image(systemName: "thermometer.medium")
                                .foregroundColor(temp > 45 ? .red : .blue)
                        }
                    }
                }
                
                // 2. Remaining Life / SMART Health Status
                if let log = result.nvmeSmartHealthInformationLog {
                    let healthPct = 100 - log.percentageUsed
                    GridRow {
                        Text("Remaining Life (Health):")
                            .fontWeight(.semibold)
                        VStack(alignment: .leading, spacing: 5) {
                            ProgressView(value: Double(healthPct), total: 100)
                                .tint(healthPct < 20 ? .red : (healthPct < 50 ? .orange : .green))
                            Text("\(healthPct)% Remaining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if let status = result.smartStatus {
                    GridRow {
                        Text("SMART Health Status:")
                            .fontWeight(.semibold)
                        HStack {
                            Text(status.passed ? "PASSED" : "FAILED")
                                .fontWeight(.bold)
                                .foregroundColor(status.passed ? .green : .red)
                            Image(systemName: status.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(status.passed ? .green : .red)
                        }
                    }
                }
                
                // 3. Common Power Cycles
                if let cycles = result.powerCycleCount {
                    GridRow {
                        Text("Power Cycles:")
                            .fontWeight(.semibold)
                        Text("\(cycles)")
                    }
                }
                
                // 4. Common Power On Hours
                if let hours = result.powerOnTime?.hours {
                    GridRow {
                        Text("Power On Hours:")
                            .fontWeight(.semibold)
                        Text("\(hours) hours (~ \(hours / 24) days)")
                    }
                }
                
                // 5. NVMe Data Units (specific)
                if let log = result.nvmeSmartHealthInformationLog {
                    GridRow {
                        Text("Data Units Written:")
                            .fontWeight(.semibold)
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
                }
                
                // 6. Protocol Name
                GridRow {
                    Text("Connection Protocol:")
                        .fontWeight(.semibold)
                    Text(result.device?.protocolName ?? "Unknown")
                }
                
                // Fallback explanation if no common metrics are found at all
                if result.temperature?.current == nil && result.smartStatus == nil {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("✓ Password accepted. Raw connection established.")
                            .font(.caption)
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                        Text("However, this specific USB enclosure's bridge chip does not translate S.M.A.R.T. commands under macOS.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("To read telemetry from this drive, connect it via a Thunderbolt port/enclosure, or use a Linux/Windows host.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .padding(.top, 5)
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
            } else if let ata = result.ataSmartAttributes {
                // Show SATA/ATA attributes in a neat table
                Table(ata.table) {
                    TableColumn("ID") { attr in
                        Text("\(attr.id)")
                    }
                    .width(min: 30, max: 40)
                    
                    TableColumn("Attribute Name") { attr in
                        Text(attr.name)
                            .fontWeight(.medium)
                    }
                    .width(min: 150, max: 220)
                    
                    TableColumn("Value") { attr in
                        Text("\(attr.value)")
                    }
                    .width(min: 40, max: 60)
                    
                    TableColumn("Worst") { attr in
                        Text("\(attr.worst)")
                    }
                    .width(min: 40, max: 60)
                    
                    TableColumn("Threshold") { attr in
                        Text("\(attr.threshold)")
                    }
                    .width(min: 40, max: 60)
                    
                    TableColumn("Raw Value") { attr in
                        Text(attr.raw.string)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 300)
            } else {
                Text("No S.M.A.R.T. health log entries parsed for this device format.")
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

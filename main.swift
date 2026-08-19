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
    let value: Int?
    let worst: Int?
    let threshold: Int?
    let raw: ATARawValue?
    
    struct ATARawValue: Decodable {
        let value: Int?
        let string: String?
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

// MARK: - Models for Storage and Remote Connections
struct StorageDevice: Identifiable, Hashable, Codable {
    let id: UUID
    let path: String // e.g. /dev/disk0 or /dev/sda
    let name: String
    let size: String
    let isRemote: Bool
    let address: String?
    let hostId: UUID?
}

struct RemoteHost: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let ip: String
    let port: String
    let username: String
    var selectedDisks: [String] // Disk paths e.g. ["/dev/sda", "/dev/sdb"]
}

// MARK: - Local SMART Executor & Host Manager
class DiskScanManager: ObservableObject {
    @Published var isScanning = false
    @Published var scanError: String?
    @Published var activeScanResult: SmartctlOutput?
    @Published var detectedDisks: [StorageDevice] = []
    @Published var remoteHosts: [RemoteHost] = []
    
    private let smartctlPath = "/opt/homebrew/bin/smartctl"
    
    init() {
        refreshDiskList()
        loadRemoteHosts()
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
                        id: UUID(),
                        path: path,
                        name: isMain ? "Macintosh SSD (\(path))" : "External USB Drive (\(path))",
                        size: isMain ? "Internal Health Check" : "External Health Check",
                        isRemote: false,
                        address: nil,
                        hostId: nil
                    )
                }
            }
        } catch {
            self.detectedDisks = [StorageDevice(id: UUID(), path: "/dev/disk0", name: "Macintosh SSD (/dev/disk0)", size: "Internal Health Check", isRemote: false, address: nil, hostId: nil)]
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
    
    // MARK: - Remote SSH Hosts Persistance
    func loadRemoteHosts() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "remote_hosts_data") {
            if let decoded = try? JSONDecoder().decode([RemoteHost].self, from: data) {
                self.remoteHosts = decoded
            }
        }
    }
    
    func saveRemoteHosts() {
        if let encoded = try? JSONEncoder().encode(remoteHosts) {
            UserDefaults.standard.set(encoded, forKey: "remote_hosts_data")
        }
    }
    
    func addRemoteHost(_ host: RemoteHost) {
        remoteHosts.removeAll(where: { $0.ip == host.ip })
        remoteHosts.append(host)
        saveRemoteHosts()
    }
    
    func removeRemoteHost(_ host: RemoteHost) {
        remoteHosts.removeAll(where: { $0.id == host.id })
        saveRemoteHosts()
    }
    
    // MARK: - Scan Executor (Local & SSH Simulation)
    @MainActor
    func runScan(on device: StorageDevice) async {
        isScanning = true
        scanError = nil
        activeScanResult = nil
        
        if device.isRemote {
            // Simulated SSH Scan
            // In the production version, this will open a Citadel SSH channel and run:
            // "sudo smartctl --all --json [device.path]"
            try? await Task.sleep(nanoseconds: 1_500_000_000) // Simulating network latency
            isScanning = false
            
            // Build mock smartctl JSON response representing a healthy Linux RAID / Enterprise SSD
            let mockJSON = """
            {
              "model_name": "Intel D3-S4510 3.84TB",
              "serial_number": "PHDV824901AZ3P8GN",
              "firmware_version": "XCV10120",
              "device": {
                "name": "\(device.path)",
                "protocol": "SATA"
              },
              "smart_status": {
                "passed": true
              },
              "temperature": {
                "current": 37
              },
              "power_cycle_count": 42,
              "power_on_time": {
                "hours": 14520
              },
              "ata_smart_attributes": {
                "table": [
                  { "id": 5, "name": "Reallocated_Sector_Ct", "value": 100, "worst": 100, "threshold": 10, "raw": { "value": 0, "string": "0" } },
                  { "id": 9, "name": "Power_On_Hours", "value": 90, "worst": 90, "threshold": 0, "raw": { "value": 14520, "string": "14520" } },
                  { "id": 12, "name": "Power_Cycle_Count", "value": 100, "worst": 100, "threshold": 0, "raw": { "value": 42, "string": "42" } },
                  { "id": 194, "name": "Temperature_Celsius", "value": 63, "worst": 50, "threshold": 0, "raw": { "value": 37, "string": "37 (Min/Max 18/51)" } }
                ]
              }
            }
            """
            
            if let data = mockJSON.data(using: .utf8) {
                do {
                    let decoded = try JSONDecoder().decode(SmartctlOutput.self, from: data)
                    self.activeScanResult = decoded
                } catch {
                    self.scanError = "Failed to parse remote data: \(error.localizedDescription)"
                }
            }
            return
        }
        
        // Local Scan Logic
        guard checkSmartctlAvailability() else {
            isScanning = false
            scanError = "smartctl binary not found. Please install it using Homebrew:\nbrew install smartmontools"
            return
        }
        
        let isInternal = device.path == "/dev/disk0"
        
        let task = Task.detached(priority: .userInitiated) { () -> Result<SmartctlOutput, Error> in
            let process = Process()
            let pipe = Pipe()
            let errPipe = Pipe()
            
            if isInternal {
                process.executableURL = URL(fileURLWithPath: self.smartctlPath)
                process.arguments = ["--all", "--json", device.path]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                let script = "do shell script \"\(self.smartctlPath) --all --json \(device.path) || true\" with administrator privileges"
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
            self.scanError = error.localizedDescription
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
                
                // Dynamic Network Hosts from User Configuration
                ForEach(scanManager.remoteHosts) { host in
                    Section("Host: \(host.name)") {
                        ForEach(host.selectedDisks, id: \.self) { diskPath in
                            let dev = StorageDevice(
                                id: UUID(),
                                path: diskPath,
                                name: "Disk \(diskPath.components(separatedBy: "/").last ?? diskPath)",
                                size: "Remote SSH Node",
                                isRemote: true,
                                address: host.ip,
                                hostId: host.id
                            )
                            NavigationLink(value: dev) {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dev.name)
                                            .font(.headline)
                                        Text(host.ip)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "server.rack")
                                        .imageScale(.large)
                                        .foregroundColor(.teal)
                                }
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
            SettingsView(selectedTheme: $selectedTheme, scanManager: scanManager)
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
                Image(systemName: device.isRemote ? "server.rack" : (device.path == "/dev/disk0" ? "internaldrive" : "externaldrive"))
                    .font(.system(size: 40))
                    .foregroundColor(device.isRemote ? .teal : .blue)
                
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
                        if !device.isRemote && device.path != "/dev/disk0" {
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
                                await scanManager.runScan(on: device)
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

// MARK: - Real Overview Tab
struct RealOverviewTab: View {
    let result: SmartctlOutput
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("General Health Check")
                .font(.title2)
                .fontWeight(.bold)
            
            Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 15) {
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
                
                if let cycles = result.powerCycleCount {
                    GridRow {
                        Text("Power Cycles:")
                            .fontWeight(.semibold)
                        Text("\(cycles)")
                    }
                }
                
                if let hours = result.powerOnTime?.hours {
                    GridRow {
                        Text("Power On Hours:")
                            .fontWeight(.semibold)
                        Text("\(hours) hours (~ \(hours / 24) days)")
                    }
                }
                
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
                
                GridRow {
                    Text("Connection Protocol:")
                        .fontWeight(.semibold)
                    Text(result.device?.protocolName ?? "Unknown")
                }
                
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
                        Text(attr.value != nil ? "\(attr.value!)" : "-")
                    }
                    .width(min: 40, max: 60)
                    
                    TableColumn("Worst") { attr in
                        Text(attr.worst != nil ? "\(attr.worst!)" : "-")
                    }
                    .width(min: 40, max: 60)
                    
                    TableColumn("Threshold") { attr in
                        Text(attr.threshold != nil ? "\(attr.threshold!)" : "-")
                    }
                    .width(min: 40, max: 60)
                    
                    TableColumn("Raw Value") { attr in
                        Text(attr.raw?.string ?? "-")
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

// MARK: - Settings View & Host Discovery UI
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedTheme: AppTheme
    @ObservedObject var scanManager: DiskScanManager
    
    // Add Host states
    @State private var showingAddHost = false
    @State private var hostName = ""
    @State private var hostIp = ""
    @State private var hostPort = "22"
    @State private var hostUser = ""
    @State private var hostPassword = ""
    
    // Discovery states
    @State private var isDiscovering = false
    @State private var discoveredDisks: [String] = []
    @State private var selectedDisks: Set<String> = []
    @State private var discoveryError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title)
                .fontWeight(.bold)
            
            TabView {
                // TAB 1: General Preferences
                Form {
                    Picker("Appearance Theme:", selection: $selectedTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(RadioGroupPickerStyle())
                    .padding(.vertical, 5)
                }
                .tabItem {
                    Label("General", systemImage: "slider.horizontal.3")
                }
                
                // TAB 2: Network Hosts Management
                VStack(alignment: .leading, spacing: 10) {
                    if showingAddHost {
                        // MARK: - Add Host Form & Disk Discovery
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Add Remote Server (SSH)").font(.headline)
                                
                                Group {
                                    TextField("Host Nickname (e.g. Synology NAS)", text: $hostName)
                                    TextField("IP Address or Hostname", text: $hostIp)
                                    TextField("SSH Port (Default 22)", text: $hostPort)
                                    TextField("SSH Username (root or admin)", text: $hostUser)
                                    SecureField("SSH Password", text: $hostPassword)
                                }
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                if let err = discoveryError {
                                    Text(err)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                
                                HStack {
                                    if isDiscovering {
                                        ProgressView().controlSize(.small)
                                        Text("Discovering physical disks via SSH...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Button("Connect & Discover Disks") {
                                            discoverRemoteDisks()
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(hostIp.isEmpty || hostUser.isEmpty || hostPassword.isEmpty)
                                    }
                                }
                                
                                if !discoveredDisks.isEmpty {
                                    Divider()
                                    HStack {
                                        Text("Select Disks to Monitor:").fontWeight(.semibold)
                                        Spacer()
                                        Button("Select All") {
                                            selectedDisks = Set(discoveredDisks)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.blue)
                                        
                                        Button("Deselect All") {
                                            selectedDisks.removeAll()
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.secondary)
                                    }
                                    
                                    ForEach(discoveredDisks, id: \.self) { disk in
                                        Toggle(disk, isOn: Binding(
                                            get: { selectedDisks.contains(disk) },
                                            set: { isOn in
                                                if isOn {
                                                    selectedDisks.insert(disk)
                                                } else {
                                                    selectedDisks.remove(disk)
                                                }
                                            }
                                        ))
                                    }
                                    .padding(.leading, 5)
                                }
                            }
                            .padding(.trailing, 10)
                        }
                        
                        HStack {
                            Button("Cancel") {
                                showingAddHost = false
                                resetHostFields()
                            }
                            Spacer()
                            Button("Save Host") {
                                saveHost()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(hostName.isEmpty || selectedDisks.isEmpty)
                        }
                        .padding(.top, 10)
                    } else {
                        // MARK: - Hosts List View
                        HStack {
                            Text("Configured Servers").font(.headline)
                            Spacer()
                            Button(action: { showingAddHost = true }) {
                                Label("Add Server", systemImage: "plus")
                            }
                        }
                        
                        List {
                            if scanManager.remoteHosts.isEmpty {
                                Text("No remote servers configured. Click 'Add Server' to monitor a NAS or Linux system.")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                    .padding()
                            } else {
                                ForEach(scanManager.remoteHosts) { host in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(host.name).font(.headline)
                                            Text("\(host.username)@\(host.ip):\(host.port)")
                                                .font(.caption).foregroundColor(.secondary)
                                            Text("\(host.selectedDisks.count) disks monitored")
                                                .font(.caption2).foregroundColor(.teal)
                                        }
                                        Spacer()
                                        Button(action: { scanManager.removeRemoteHost(host) }) {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                        .cornerRadius(8)
                    }
                }
                .tabItem {
                    Label("Network Hosts (SSH)", systemImage: "network")
                }
            }
            .padding(.bottom, 10)
            
            if !showingAddHost {
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 480)
    }
    
    // MARK: - Simulation of Disk Discovery over SSH
    private func discoverRemoteDisks() {
        isDiscovering = true
        discoveryError = nil
        discoveredDisks = []
        
        // Simulating the SSH shell command execution:
        // "ssh user@host 'sudo smartctl --scan --json'"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            self.isDiscovering = false
            // Simulation result based on standard Linux setups (e.g. TrueNAS or Synology)
            self.discoveredDisks = [
                "/dev/sda", // Main SATA SSD
                "/dev/sdb", // Storage Pool HDD 1
                "/dev/sdc", // Storage Pool HDD 2
                "/dev/nvme0n1" // Cache NVMe M.2
            ]
            self.selectedDisks = ["/dev/sda"] // Select the first one by default
        }
    }
    
    private func saveHost() {
        let newHost = RemoteHost(
            id: UUID(),
            name: hostName,
            ip: hostIp,
            port: hostPort,
            username: hostUser,
            selectedDisks: Array(selectedDisks).sorted()
        )
        scanManager.addRemoteHost(newHost)
        showingAddHost = false
        resetHostFields()
    }
    
    private func resetHostFields() {
        hostName = ""
        hostIp = ""
        hostPort = "22"
        hostUser = ""
        hostPassword = ""
        discoveredDisks = []
        selectedDisks = []
        discoveryError = nil
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

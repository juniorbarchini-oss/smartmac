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
    let userCapacity: UserCapacityInfo?
    let rotationRate: Int?
    
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
        case userCapacity = "user_capacity"
        case rotationRate = "rotation_rate"
    }
}

struct UserCapacityInfo: Decodable {
    let bytes: Int64?
}

enum HealthStatus: String {
    case healthy = "Healthy"
    case warning = "Warning"
    case critical = "Critical"
    case failing = "Failing"
}

struct DiskDiagnosis {
    let status: HealthStatus
    let message: String
    let criticalCount: Int
    let reallocatedSectors: Int
    let pendingSectors: Int
    let crcErrors: Int
    
    var iconName: String {
        switch status {
        case .healthy: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.shield.fill"
        case .critical, .failing: return "xmark.shield.fill"
        }
    }
    
    var color: Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical, .failing: return .red
        }
    }
    
    var title: String {
        switch status {
        case .healthy: return "Disk Status: Healthy"
        case .warning: return "Disk Status: Warning / Degrading"
        case .critical: return "Disk Status: Critical Alert"
        case .failing: return "Disk Status: Critical Alert / Imminent Failure"
        }
    }
    
    var backgroundColor: Color {
        switch status {
        case .healthy: return Color.green.opacity(0.1)
        case .warning: return Color.orange.opacity(0.1)
        case .critical, .failing: return Color.red.opacity(0.1)
        }
    }
    
    var strokeColor: Color {
        switch status {
        case .healthy: return Color.green.opacity(0.3)
        case .warning: return Color.orange.opacity(0.3)
        case .critical, .failing: return Color.red.opacity(0.3)
        }
    }
}

extension SmartctlOutput {
    var deviceTypeDescription: String {
        let proto = device?.protocolName?.uppercased() ?? ""
        let model = modelName?.uppercased() ?? ""
        
        if proto == "NVME" {
            return "Solid State Drive (NVMe M.2)"
        }
        
        let isSSD = model.contains("SSD") || model.contains("SOLID STATE") || proto.contains("SSD")
        
        if let rate = rotationRate {
            if rate == 0 {
                return isSSD ? "Solid State Drive (SATA SSD)" : "Solid State Drive (SSD)"
            } else if rate > 0 {
                return "Mechanical Hard Drive (HDD, \(rate) RPM)"
            }
        }
        
        if isSSD {
            return "Solid State Drive (SATA SSD)"
        }
        return proto.isEmpty ? "Unknown Type" : "Drive (\(proto))"
    }
    
    var formattedCapacity: String {
        if let bytes = userCapacity?.bytes {
            let tb = Double(bytes) / 1_000_000_000_000.0
            if tb >= 0.9 {
                return String(format: "%.2f TB", tb)
            }
            let gb = Double(bytes) / 1_000_000_000.0
            return String(format: "%.0f GB", gb)
        }
        
        // Fallback for macOS local system disk (/dev/disk0)
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let space = attrs[.systemSize] as? Int64 {
            let tb = Double(space) / 1_000_000_000_000.0
            if tb >= 0.9 {
                return String(format: "%.2f TB", tb)
            }
            let gb = Double(space) / 1_000_000_000.0
            return String(format: "%.0f GB", gb)
        }
        
        return "Unknown Size"
    }
    
    func runDiagnosis() -> DiskDiagnosis {
        var status = HealthStatus.healthy
        var message = "The disk is functioning within normal hardware parameters. No anomalies detected."
        var criticalCount = 0
        var reallocatedSectors = 0
        var pendingSectors = 0
        var crcErrors = 0
        
        // 1. Diagnosis for NVMe
        if let nvme = nvmeSmartHealthInformationLog {
            if nvme.mediaErrors > 0 {
                status = .critical
                message = "CRITICAL ALERT: Detected \(nvme.mediaErrors) data integrity and physical media errors. Your files are at risk of corruption. Back up immediately!"
                criticalCount += nvme.mediaErrors
            }
            if nvme.criticalWarning > 0 {
                status = .failing
                message = "IMMINENT FAILURE: NVMe controller reports critical hardware warnings (Code: \(nvme.criticalWarning)). The drive is failing or in write-protection read-only mode."
                criticalCount += 1
            }
            if nvme.percentageUsed >= 95 {
                if status != .failing && status != .critical {
                    status = .warning
                }
                message = "Drive Wearout: Life used is \(nvme.percentageUsed)%. The drive is approaching the end of its operational lifespan."
            }
            
            return DiskDiagnosis(
                status: status,
                message: message,
                criticalCount: criticalCount,
                reallocatedSectors: 0,
                pendingSectors: nvme.mediaErrors,
                crcErrors: 0
            )
        }
        
        // 2. Diagnosis for SATA/ATA
        if let table = ataSmartAttributes?.table {
            for attr in table {
                switch attr.id {
                case 5:
                    reallocatedSectors = attr.raw?.value ?? 0
                case 197:
                    pendingSectors = attr.raw?.value ?? 0
                case 198:
                    criticalCount += attr.raw?.value ?? 0
                case 199:
                    crcErrors = attr.raw?.value ?? 0
                default:
                    break
                }
            }
            
            if pendingSectors > 0 || criticalCount > 0 {
                status = .failing
                message = "IMMINENT PHYSICAL FAILURE: The disk has \(pendingSectors) pending sectors to reallocate and \(criticalCount) uncorrectable sectors. There are active read/write failures on the physical disk surface! Back up and replace immediately."
            } else if reallocatedSectors > 0 {
                if reallocatedSectors > 50 {
                    status = .critical
                    message = "CRITICAL ALERT: The disk has reallocated \(reallocatedSectors) bad sectors. Physical degradation is high and bad sectors continue to spread. Urgent replacement recommended."
                } else {
                    status = .warning
                    message = "WARNING: The disk has \(reallocatedSectors) reallocated bad sectors. The hardware has started physically degrading, but has successfully isolated the damaged sectors for now. Monitor closely."
                }
            } else if crcErrors > 50 {
                status = .warning
                message = "Interface Alert: Detected \(crcErrors) checksum (CRC) errors in data transfer. This indicates the SATA data cable might be damaged, the connector is loose, or power is unstable."
            }
            
            if let passed = smartStatus?.passed, !passed {
                status = .failing
                message = "FIRMWARE SELF-TEST (SMART): IMMINENT FAILURE DETECTED! The drive's own firmware has declared that the unit is about to fail. Back up your data and power off the machine."
            }
        }
        
        return DiskDiagnosis(
            status: status,
            message: message,
            criticalCount: criticalCount,
            reallocatedSectors: reallocatedSectors,
            pendingSectors: pendingSectors,
            crcErrors: crcErrors
        )
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
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case value
        case worst
        case threshold = "thresh"
        case raw
    }
    
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
    var id: String {
        return "\(hostId?.uuidString ?? "local")-\(path)"
    }
    let path: String
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
    let password: String
    var selectedDisks: [String]
}

// MARK: - Local SMART Executor & Host Manager
class DiskScanManager: ObservableObject {
    @Published var isScanning = false
    @Published var scanError: String?
    @Published var scanResults: [String: SmartctlOutput] = [:]
    @Published var detectedDisks: [StorageDevice] = []
    @Published var remoteHosts: [RemoteHost] = []
    @Published var allDevices: [StorageDevice] = []
    
    private let smartctlPath = "/opt/homebrew/bin/smartctl"
    
    init() {
        refreshDiskList()
        loadRemoteHosts()
        updateAllDevices()
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
                        address: nil,
                        hostId: nil
                    )
                }
            }
        } catch {
            self.detectedDisks = [StorageDevice(path: "/dev/disk0", name: "Macintosh SSD (/dev/disk0)", size: "Internal Health Check", isRemote: false, address: nil, hostId: nil)]
        }
        updateAllDevices()
    }
    
    func updateAllDevices() {
        var devices = detectedDisks
        
        for host in remoteHosts {
            for diskPath in host.selectedDisks {
                let dev = StorageDevice(
                    path: diskPath,
                    name: "Disk \(diskPath.components(separatedBy: "/").last ?? diskPath)",
                    size: "Remote SSH Node",
                    isRemote: true,
                    address: host.ip,
                    hostId: host.id
                )
                devices.append(dev)
            }
        }
        
        self.allDevices = devices
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
        if let data = defaults.data(forKey: "remote_hosts_data_v2") {
            if let decoded = try? JSONDecoder().decode([RemoteHost].self, from: data) {
                self.remoteHosts = decoded
                updateAllDevices()
            }
        }
    }
    
    func saveRemoteHosts() {
        if let encoded = try? JSONEncoder().encode(remoteHosts) {
            UserDefaults.standard.set(encoded, forKey: "remote_hosts_data_v2")
        }
    }
    
    func addRemoteHost(_ host: RemoteHost) {
        remoteHosts.removeAll(where: { $0.ip == host.ip })
        remoteHosts.append(host)
        saveRemoteHosts()
        updateAllDevices()
    }
    
    func removeRemoteHost(_ host: RemoteHost) {
        remoteHosts.removeAll(where: { $0.id == host.id })
        saveRemoteHosts()
        updateAllDevices()
    }
    
    // MARK: - Real SSH Commands Executor using Expect
    func runSSHSmartctlScan(host: RemoteHost, devicePath: String) async -> Result<SmartctlOutput, Error> {
        let task = Task.detached(priority: .userInitiated) { () -> Result<SmartctlOutput, Error> in
            let process = Process()
            let pipe = Pipe()
            let errPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
            let port = host.port.isEmpty ? "22" : host.port
            let expectScript = """
            set timeout 45
            spawn ssh -o StrictHostKeyChecking=no -p \(port) \(host.username)@\(host.ip) "sudo -S smartctl --all --json \(devicePath)"
            expect {
                "ssword" {
                    send "\(host.password)\\r"
                    exp_continue
                }
                "Permission denied" {
                    exit 1
                }
                timeout {
                    exit 2
                }
                eof
            }
            """
            process.arguments = ["-c", expectScript]
            
            process.standardOutput = pipe
            process.standardError = errPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                
                // Intentamos decodificar el JSON de stdout primero. Si es exitoso, devolvemos success.
                // Esto es crucial porque smartctl sale con códigos distintos de 0 si detecta advertencias de salud en el disco.
                if let rawOutput = String(data: data, encoding: .utf8) {
                    if let jsonStart = rawOutput.firstIndex(of: "{") {
                        let jsonStr = String(rawOutput[jsonStart...])
                        if let jsonData = jsonStr.data(using: .utf8) {
                            let decoder = JSONDecoder()
                            if let decoded = try? decoder.decode(SmartctlOutput.self, from: jsonData) {
                                return .success(decoded)
                            }
                        }
                    }
                }
                
                // Si la decodificación del JSON falló, validamos el estado de terminación del proceso
                if process.terminationStatus != 0 {
                    var errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    if errStr.isEmpty {
                        if process.terminationStatus == 2 {
                            errStr = "Connection Timeout (45s expired): The remote disk is taking too long to respond. This usually indicates severe hardware blockages, bad physical sectors, or I/O retries on the SATA controller of the server."
                        } else if process.terminationStatus == 1 {
                            errStr = "SSH Permission Denied: Invalid credentials or insufficient sudo privileges on the remote host."
                        } else {
                            errStr = "SSH execution terminated with exit code \(process.terminationStatus)."
                        }
                    }
                    return .failure(NSError(domain: "SmartMacApp", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errStr]))
                }
                
                return .failure(NSError(domain: "SmartMacApp", code: 3, userInfo: [NSLocalizedDescriptionKey: "Did not receive structured JSON data from remote smartctl."]))
            } catch {
                return .failure(error)
            }
        }
        return await task.value
    }
    
    func discoverRemoteDisksReal(ip: String, port: String, user: String, pass: String) async -> Result<[String], Error> {
        let task = Task.detached(priority: .userInitiated) { () -> Result<[String], Error> in
            let process = Process()
            let pipe = Pipe()
            let errPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
            let portArg = port.isEmpty ? "22" : port
            let expectScript = """
            set timeout 15
            spawn ssh -o StrictHostKeyChecking=no -p \(portArg) \(user)@\(ip) "sudo -S smartctl --scan --json || smartctl --scan --json || lsblk -d -o NAME -n || true"
            expect {
                "ssword" {
                    send "\(pass)\\r"
                    exp_continue
                }
                "Permission denied" {
                    exit 1
                }
                timeout {
                    exit 2
                }
                eof
            }
            """
            process.arguments = ["-c", expectScript]
            
            process.standardOutput = pipe
            process.standardError = errPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                if process.terminationStatus != 0 {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "Authentication or SSH connection failed."
                    return .failure(NSError(domain: "SmartMacApp", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errStr]))
                }
                
                if let rawOutput = String(data: data, encoding: .utf8) {
                    print("--- Raw SSH Discover Output ---\n", rawOutput)
                    
                    if let jsonStart = rawOutput.firstIndex(of: "{") {
                        let jsonStr = String(rawOutput[jsonStart...])
                        struct ScanResponse: Decodable {
                            struct Device: Decodable {
                                let name: String
                            }
                            let devices: [Device]?
                        }
                        if let jsonData = jsonStr.data(using: .utf8),
                           let decoded = try? JSONDecoder().decode(ScanResponse.self, from: jsonData),
                           let devs = decoded.devices {
                            return .success(devs.map { $0.name })
                        }
                    }
                    
                    let lines = rawOutput.components(separatedBy: .newlines)
                    var paths: [String] = []
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("/dev/disk") || trimmed.hasPrefix("/dev/sd") || trimmed.hasPrefix("/dev/nvme") {
                            if let firstSpace = trimmed.firstIndex(of: " ") {
                                paths.append(String(trimmed[..<firstSpace]))
                            } else {
                                paths.append(trimmed)
                            }
                        } else if trimmed.hasPrefix("sd") || trimmed.hasPrefix("nvme") {
                            paths.append("/dev/\(trimmed)")
                        }
                    }
                    if !paths.isEmpty {
                        return .success(Array(Set(paths)).sorted())
                    }
                }
                
                return .failure(NSError(domain: "SmartMacApp", code: 3, userInfo: [NSLocalizedDescriptionKey: "No physical disks discovered on remote server. Ensure smartctl or lsblk is installed."]))
            } catch {
                return .failure(error)
            }
        }
        return await task.value
    }
    
    // MARK: - Scan Executor
    @MainActor
    func runScan(on device: StorageDevice) async {
        isScanning = true
        scanError = nil
        
        let deviceKey = "\(device.hostId?.uuidString ?? "local")-\(device.path)"
        
        if device.isRemote, let hostId = device.hostId, let host = remoteHosts.first(where: { $0.id == hostId }) {
            // Real SSH Scan
            let result = await runSSHSmartctlScan(host: host, devicePath: device.path)
            isScanning = false
            
            switch result {
            case .success(let output):
                self.scanResults[deviceKey] = output
            case .failure(let error):
                self.scanError = "SSH Scan Failed: \(error.localizedDescription)"
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
            self.scanResults[deviceKey] = output
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
    
    private var deviceKey: String {
        return "\(device.hostId?.uuidString ?? "local")-\(device.path)"
    }
    
    private var scanResult: SmartctlOutput? {
        return scanManager.scanResults[deviceKey]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Disk Header (Always fixed at the top)
            HStack(spacing: 15) {
                Image(systemName: device.isRemote ? "server.rack" : (device.path == "/dev/disk0" ? "internaldrive" : "externaldrive"))
                    .font(.system(size: 40))
                    .foregroundColor(device.isRemote ? .teal : .blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(scanResult?.modelName ?? device.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        if let result = scanResult {
                            let diagnosis = result.runDiagnosis()
                            Text(diagnosis.status.rawValue.uppercased())
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(diagnosis.strokeColor)
                                .foregroundColor(diagnosis.color)
                                .cornerRadius(5)
                        }
                    }
                    Text("Device Path: \(device.path) | Connection: \(device.isRemote ? "Remote SSH" : "Local Direct")")
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
            
            // Tab Selector (Fixed below the header)
            if scanResult != nil {
                Picker("", selection: $selectedTab) {
                    Text("Overview").tag("overview")
                    Text("Detailed Metrics").tag("metrics")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            
            // Diagnostic Errors (Fixed block)
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
                .padding(.horizontal)
                .padding(.top, 5)
            }
            
            // Scrollable Content (Adapts dynamically to window size)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let result = scanResult {
                        // 1. Rich Hardware Info Grid
                        HStack(spacing: 30) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CAPACITY")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(result.formattedCapacity)
                                    .font(.title3)
                                    .fontWeight(.bold)
                            }
                            
                            Divider().frame(height: 35)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("DRIVE TYPE")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(result.deviceTypeDescription)
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            
                            Divider().frame(height: 35)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SERIAL NUMBER")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(result.serialNumber ?? "N/A")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider().frame(height: 35)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("FIRMWARE")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(result.firmwareVersion ?? "N/A")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        
                        // 2. Heuristic Health Diagnosis Panel
                        let diagnosis = result.runDiagnosis()
                        HStack(alignment: .top, spacing: 15) {
                            Image(systemName: diagnosis.iconName)
                                .font(.system(size: 32))
                                .foregroundColor(diagnosis.color)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(diagnosis.title)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(diagnosis.color)
                                
                                Text(diagnosis.message)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(nil)
                                
                                if diagnosis.status != .healthy {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if diagnosis.reallocatedSectors > 0 {
                                            Text("• Reallocated Sectors: \(diagnosis.reallocatedSectors) (Bad physical sectors isolated by the disk)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if diagnosis.pendingSectors > 0 {
                                            Text("• Pending Sectors: \(diagnosis.pendingSectors) (Unstable sectors with active read/write failures)")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                                .fontWeight(.semibold)
                                        }
                                        if diagnosis.criticalCount > 0 {
                                            Text("• Uncorrectable Sectors (Offline): \(diagnosis.criticalCount) (Permanent physical damage on the surface)")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                                .fontWeight(.bold)
                                        }
                                        if diagnosis.crcErrors > 0 {
                                            Text("• Interface Errors (CRC): \(diagnosis.crcErrors) (Problems with the SATA cable, connector, or power)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(diagnosis.backgroundColor)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(diagnosis.strokeColor, lineWidth: 1)
                        )
                        
                        // 3. Tab Specific Metrics
                        if selectedTab == "overview" {
                            RealOverviewTab(result: result)
                        } else {
                            RealMetricsTab(result: result)
                        }
                    } else {
                        // Scan Prompt
                        VStack(spacing: 15) {
                            Image(systemName: "gauge.medium")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Press 'Scan Now' to retrieve real S.M.A.R.T. health data.")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 250)
                    }
                }
                .padding()
            }
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
                        Text("However, this specific USB enclosure's bridge chip does not translate S.M.A.T. commands under macOS.")
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
                        Text(attr.value.map { "\($0)" } ?? "-")
                    }
                    .width(min: 40, max: 60)
                    
                    TableColumn("Worst") { attr in
                        Text(attr.worst.map { "\($0)" } ?? "-")
                    }
                    .width(min: 40, max: 60)
                    
                    TableColumn("Threshold") { attr in
                        Text(attr.threshold.map { "\($0)" } ?? "-")
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
                                        .textSelection(.enabled)
                                }
                                
                                HStack {
                                    if isDiscovering {
                                        ProgressView().controlSize(.small)
                                        Text("Discovering physical disks via SSH...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Button("Connect & Discover Disks") {
                                            Task {
                                                await discoverRemoteDisks()
                                            }
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
    
    // MARK: - Real SSH Disk Discovery over network
    private func discoverRemoteDisks() async {
        isDiscovering = true
        discoveryError = nil
        discoveredDisks = []
        
        let result = await scanManager.discoverRemoteDisksReal(
            ip: hostIp,
            port: hostPort,
            user: hostUser,
            pass: hostPassword
        )
        
        isDiscovering = false
        
        switch result {
        case .success(let paths):
            self.discoveredDisks = paths
            self.selectedDisks = Set(paths) // Select all by default
        case .failure(let error):
            self.discoveryError = error.localizedDescription
        }
    }
    
    private func saveHost() {
        let newHost = RemoteHost(
            id: UUID(),
            name: hostName,
            ip: hostIp,
            port: hostPort,
            username: hostUser,
            password: hostPassword,
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

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
struct SmartSupportInfo: Decodable {
    let available: Bool?
    let enabled: Bool?
}

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
    let logicalBlockSize: Int?
    let physicalBlockSize: Int?
    let smartSupport: SmartSupportInfo?
    let nvmeTotalCapacity: Int64?
    
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
        case logicalBlockSize = "logical_block_size"
        case physicalBlockSize = "physical_block_size"
        case smartSupport = "smart_support"
        case nvmeTotalCapacity = "nvme_total_capacity"
    }
    
    var storageTechnology: String {
        let proto = device?.protocolName?.uppercased() ?? ""
        if proto.contains("NVME") {
            return "Solid State Drive (NVMe SSD)"
        }
        if let rate = rotationRate {
            if rate == 0 {
                return "Solid State Drive (SATA SSD)"
            } else {
                return "Mechanical Hard Disk Drive (HDD - \(rate) RPM)"
            }
        }
        if proto.contains("SATA") || proto.contains("ATA") {
            return "Solid State Drive (SATA SSD) / HDD"
        }
        return "Solid State / Flash Storage"
    }
}

struct SSDWearEstimation {
    let totalTBWritten: Double
    let standardTBW: Double
    let remainingTB: Double
    let dailyWriteAverageGB: Double
    let estimatedYearsRemaining: Double?
    let healthRating: String
}

extension SmartctlOutput {
    func estimateWear() -> SSDWearEstimation? {
        guard let log = nvmeSmartHealthInformationLog,
              let powerOnHours = log.powerOnHours, powerOnHours > 0,
              let dataUnitsWritten = log.dataUnitsWritten else {
            return nil
        }
        
        let bytesWritten = Double(dataUnitsWritten) * 1000 * 512
        let totalTBWritten = bytesWritten / (1024 * 1024 * 1024 * 1024)
        
        let capacityBytes = userCapacity?.bytes ?? nvmeTotalCapacity ?? 0
        let capacityGB = Double(capacityBytes) / (1000 * 1000 * 1000)
        
        var standardTBW: Double = 600.0
        if capacityGB <= 300 {
            standardTBW = 150.0
        } else if capacityGB <= 600 {
            standardTBW = 300.0
        } else if capacityGB <= 1200 {
            standardTBW = 600.0
        } else if capacityGB <= 2400 {
            standardTBW = 1200.0
        } else {
            standardTBW = 2400.0
        }
        
        let remainingTB = max(0, standardTBW - totalTBWritten)
        let daysUsed = Double(powerOnHours) / 24.0
        let safeDaysUsed = max(0.1, daysUsed)
        let dailyWriteAverageTB = totalTBWritten / safeDaysUsed
        let dailyWriteAverageGB = dailyWriteAverageTB * 1024.0
        
        let pctUsed = log.percentageUsed ?? 0
        var estimatedYearsRemaining: Double? = nil
        if dailyWriteAverageTB > 0 {
            let daysRemaining = remainingTB / dailyWriteAverageTB
            let rawYears = daysRemaining / 365.0
            
            // If the drive has low hours of usage or physical wear is low, 
            // the low years estimation is a result of initial write spikes.
            if powerOnHours < 1000 || (pctUsed < 5 && rawYears < 5.0) {
                estimatedYearsRemaining = nil
            } else {
                estimatedYearsRemaining = rawYears
            }
        }
        
        var healthRating = "Excellent"
        if pctUsed > 20 {
            healthRating = "Caution"
        } else if pctUsed > 10 {
            healthRating = "Fair"
        } else if pctUsed > 2 {
            healthRating = "Good"
        }
        
        return SSDWearEstimation(
            totalTBWritten: totalTBWritten,
            standardTBW: standardTBW,
            remainingTB: remainingTB,
            dailyWriteAverageGB: dailyWriteAverageGB,
            estimatedYearsRemaining: estimatedYearsRemaining,
            healthRating: healthRating
        )
    }
}

struct UserCapacityInfo: Decodable {
    let bytes: Int64?
    let blocks: Int64?
    let text: String?
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
            let mediaErr = nvme.mediaErrors ?? 0
            let critWarn = nvme.criticalWarning ?? 0
            let pctUsed = nvme.percentageUsed ?? 0
            
            if mediaErr > 0 {
                status = .critical
                message = "CRITICAL ALERT: Detected \(mediaErr) data integrity and physical media errors. Your files are at risk of corruption. Back up immediately!"
                criticalCount += mediaErr
            }
            if critWarn > 0 {
                status = .failing
                message = "IMMINENT FAILURE: NVMe controller reports critical hardware warnings (Code: \(critWarn)). The drive is failing or in write-protection read-only mode."
                criticalCount += 1
            }
            if pctUsed >= 95 {
                if status != .failing && status != .critical {
                    status = .warning
                }
                message = "Drive Wearout: Life used is \(pctUsed)%. The drive is approaching the end of its operational lifespan."
            }
            
            return DiskDiagnosis(
                status: status,
                message: message,
                criticalCount: criticalCount,
                reallocatedSectors: 0,
                pendingSectors: mediaErr,
                crcErrors: 0
            )
        }
        
        // 2. Diagnosis for SATA/ATA
        if let table = ataSmartAttributes?.table {
            for attr in table {
                if let id = attr.id {
                    switch id {
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
            
            if let passed = smartStatus?.passed, passed == false {
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
    let current: Int?
}

struct PowerOnTimeInfo: Decodable {
    let hours: Int?
}

struct ATASmartAttributes: Decodable {
    let table: [ATAAttribute]?
}

struct ATAAttribute: Decodable, Identifiable {
    let id: Int?
    let name: String?
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
    let name: String?
    let protocolName: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case protocolName = "protocol"
    }
}

struct SmartStatus: Decodable {
    let passed: Bool?
}

struct NVMESmartHealthLog: Decodable {
    let criticalWarning: Int?
    let temperature: Int?
    let availableSpare: Int?
    let percentageUsed: Int?
    let dataUnitsRead: Int?
    let dataUnitsWritten: Int?
    let powerCycles: Int?
    let powerOnHours: Int?
    let unsafeShutdowns: Int?
    let mediaErrors: Int?
    
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
    
    static let dashboard = StorageDevice(
        path: "dashboard",
        name: "Dashboard",
        size: "",
        isRemote: false,
        address: nil,
        hostId: nil
    )
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
    @Published var hostStatus: [UUID: Bool] = [:]
    
    private let smartctlPath = "/opt/homebrew/bin/smartctl"
    private var reachabilityTimer: Timer?
    
    init() {
        refreshDiskList()
        loadRemoteHosts()
        updateAllDevices()
        setupVolumeNotifications()
        checkAllHostsReachability()
        startReachabilityTimer()
    }
    
    private func setupVolumeNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDiskList()
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delay refresh by 1.5 seconds to let the macOS kernel fully release the physical dev node descriptor
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self?.refreshDiskList()
            }
        }
    }
    
    func startReachabilityTimer() {
        reachabilityTimer?.invalidate()
        reachabilityTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAllHostsReachability()
        }
    }
    
    func verifyReachability(ip: String, port: String) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        let portArg = port.isEmpty ? "22" : port
        task.arguments = ["-zv", "-w", "2", ip, portArg]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    func checkAllHostsReachability() {
        for host in remoteHosts {
            Task {
                let reachable = await verifyReachability(ip: host.ip, port: host.port)
                await MainActor.run {
                    self.hostStatus[host.id] = reachable
                }
            }
        }
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
        // Optimistic update: remove from detectedDisks immediately so it vanishes from UI
        self.detectedDisks.removeAll(where: { $0.path == devicePath })
        self.updateAllDevices()
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["eject", devicePath]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Safety refresh after delay to sync with system state
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.refreshDiskList()
            }
        } catch {
            print("Failed to eject device: \(error)")
            self.refreshDiskList()
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
        checkAllHostsReachability()
    }
    
    func removeRemoteHost(_ host: RemoteHost) {
        remoteHosts.removeAll(where: { $0.id == host.id })
        saveRemoteHosts()
        updateAllDevices()
        checkAllHostsReachability()
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
    @State private var showExportSheet = false
    @State private var expandedHosts: Set<UUID> = []
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedDevice) {
                NavigationLink(value: StorageDevice.dashboard) {
                    Label("Dashboard", systemImage: "house.fill")
                        .font(.headline)
                }
                .padding(.vertical, 4)
                
                Section("Devices") {
                    let localMachineName = Host.current().localizedName ?? "Local Mac"
                    DisclosureGroup(isExpanded: .constant(true)) {
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
                    } label: {
                        Label(localMachineName, systemImage: "laptopcomputer")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
                
                Section(header: HStack {
                    Text("Remote Hosts")
                    Spacer()
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "plus")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Add new remote server")
                }) {
                    if scanManager.remoteHosts.isEmpty {
                        Text("No remote servers")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 10)
                    } else {
                        ForEach(scanManager.remoteHosts) { host in
                            let isOnline = scanManager.hostStatus[host.id]
                            DisclosureGroup(isExpanded: Binding(
                                get: { expandedHosts.contains(host.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedHosts.insert(host.id)
                                    } else {
                                        expandedHosts.remove(host.id)
                                    }
                                }
                            )) {
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
                                                Text(dev.path)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        } icon: {
                                            Image(systemName: "opticaldisk")
                                                .imageScale(.large)
                                                .foregroundColor(.teal)
                                        }
                                    }
                                }
                                .padding(.leading, 10)
                            } label: {
                                HStack {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(host.name)
                                                .font(.headline)
                                            Text("\(host.username)@\(host.ip)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: "server.rack")
                                            .foregroundColor(.teal)
                                    }
                                    
                                    Spacer()
                                    
                                    // Status Dot (Green/Red/Loader)
                                    if let online = isOnline {
                                        Circle()
                                            .fill(online ? Color.green : Color.red)
                                            .frame(width: 8, height: 8)
                                            .help(online ? "Online" : "Offline")
                                    } else {
                                        ProgressView()
                                            .controlSize(.small)
                                            .scaleEffect(0.6)
                                            .frame(width: 10, height: 10)
                                    }
                                    
                                    // Disconnect Button
                                    Button(action: {
                                        scanManager.removeRemoteHost(host)
                                        if let selected = selectedDevice, selected.hostId == host.id {
                                            selectedDevice = nil
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Disconnect and remove host")
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
                    
                    Button(action: { showExportSheet.toggle() }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Export diagnostic reports")
                    
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
            if let device = selectedDevice, device.path != "dashboard" {
                DiskDetailView(device: device, scanManager: scanManager, selectedDevice: $selectedDevice)
            } else {
                WelcomeDashboardView(scanManager: scanManager)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(selectedTheme: $selectedTheme, scanManager: scanManager)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportReportSheet(scanManager: scanManager)
        }
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}

// MARK: - Disk Detail View Component
struct DiskDetailView: View {
    let device: StorageDevice
    @ObservedObject var scanManager: DiskScanManager
    @Binding var selectedDevice: StorageDevice?
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
                                selectedDevice = nil
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
                    let healthPct = 100 - (log.percentageUsed ?? 0)
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
                    let passed = status.passed ?? false
                    GridRow {
                        Text("SMART Health Status:")
                            .fontWeight(.semibold)
                        HStack {
                            Text(passed ? "PASSED" : "FAILED")
                                .fontWeight(.bold)
                                .foregroundColor(passed ? .green : .red)
                            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(passed ? .green : .red)
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
                        let bytesWritten = Double(log.dataUnitsWritten ?? 0) * 1000 * 512
                        let tbWritten = bytesWritten / (1024 * 1024 * 1024 * 1024)
                        Text(String(format: "%.2f TB Written", tbWritten))
                    }
                    GridRow {
                        Text("Data Units Read:")
                            .fontWeight(.semibold)
                        let bytesRead = Double(log.dataUnitsRead ?? 0) * 1000 * 512
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
            
            // 7. SSD Lifespan & Wear Projection Card
            if let wear = result.estimateWear() {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "hourglass.badge.plus")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text("SSD Lifespan & Wear Projection")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    
                    Divider()
                    
                    Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 10) {
                        GridRow {
                            Text("Total Bytes Written:")
                                .fontWeight(.semibold)
                            Text(String(format: "%.2f TB (Standard Lifetime: %.0f TBW)", wear.totalTBWritten, wear.standardTBW))
                        }
                        GridRow {
                            Text("Remaining Life Budget:")
                                .fontWeight(.semibold)
                            Text(String(format: "%.2f TB remaining", wear.remainingTB))
                        }
                        GridRow {
                            Text("Avg. Daily Write Speed:")
                                .fontWeight(.semibold)
                            Text(String(format: "%.2f GB / day", wear.dailyWriteAverageGB))
                        }
                        GridRow {
                            Text("Estimated Lifespan Remaining:")
                                .fontWeight(.semibold)
                            if let years = wear.estimatedYearsRemaining {
                                Text(String(format: "%.1f years", years))
                                    .fontWeight(.bold)
                                    .foregroundColor(years > 5 ? .green : (years > 2 ? .orange : .red))
                            } else {
                                Text("Calibrating (> 10 years expected)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        GridRow {
                            Text("SSD Wear Rating:")
                                .fontWeight(.semibold)
                            Text(wear.healthRating)
                                .fontWeight(.bold)
                                .foregroundColor(wear.healthRating == "Excellent" ? .green : (wear.healthRating == "Good" ? .blue : (wear.healthRating == "Fair" ? .orange : .red)))
                        }
                    }
                    .font(.body)
                    
                    if wear.dailyWriteAverageGB > 40.0 {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("High write activity detected. Consider closing memory-heavy background tasks to optimize Swap virtualization on macOS.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 5)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
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
                let critWarn = log.criticalWarning ?? 0
                let availSpare = log.availableSpare ?? 0
                let unsafeShutdowns = log.unsafeShutdowns ?? 0
                let mediaErrors = log.mediaErrors ?? 0
                
                List {
                    MetricRow(name: "Critical Warnings", value: "\(critWarn)", status: critWarn == 0 ? "Normal" : "WARNING", isWarning: critWarn > 0)
                    MetricRow(name: "Available Spare Space", value: "\(availSpare)%", status: availSpare > 10 ? "OK" : "CRITICAL", isWarning: availSpare <= 10)
                    MetricRow(name: "Unsafe Shutdowns", value: "\(unsafeShutdowns)", status: "Informational", isWarning: false)
                    MetricRow(name: "Media and Data Integrity Errors", value: "\(mediaErrors)", status: mediaErrors == 0 ? "Normal" : "CRITICAL", isWarning: mediaErrors > 0)
                }
                .frame(height: 250)
                .cornerRadius(10)
            } else if let ata = result.ataSmartAttributes, let table = ata.table {
                Table(table) {
                    TableColumn("ID") { attr in
                        Text("\(attr.id ?? 0)")
                    }
                    .width(min: 30, max: 40)
                    
                    TableColumn("Attribute Name") { attr in
                        Text(attr.name ?? "Unknown")
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
                
                // TAB 3: About App & Credits
                VStack(spacing: 15) {
                    Spacer()
                    
                    Image(systemName: "gauge.extension.shortcut.minimize")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("SmartMac")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Version 1.0.0")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("S.M.A.R.T. Diagnostics & Telemetry Dashboard")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        
                    Divider()
                        .frame(width: 200)
                        .padding(.vertical, 5)
                    
                    VStack(spacing: 4) {
                        Text("Designed & Programmed by")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Humberto Barchini (HB) & Antigravity (AGY)")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    
                    Text("© 2026. All rights reserved.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .tabItem {
                    Label("About", systemImage: "info.circle")
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

// MARK: - Welcome Dashboard View
struct WelcomeDashboardView: View {
    @ObservedObject var scanManager: DiskScanManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header / Branding
                VStack(spacing: 12) {
                    Image(systemName: "gauge.extension.shortcut.minimize")
                        .font(.system(size: 72))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.bottom, 5)
                    
                    Text("SmartMac")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    
                    Text("S.M.A.R.T. Telemetry")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }
                .padding(.top, 40)
                
                // Status / System Summary Cards
                let localMachineName = Host.current().localizedName ?? "Local Mac"
                HStack(spacing: 20) {
                    // Mac Name Card
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "laptopcomputer")
                            .font(.title)
                            .foregroundColor(.blue)
                        Text("Local System")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(localMachineName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding()
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    
                    // Local Storage Card
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "internaldrive.fill")
                            .font(.title)
                            .foregroundColor(.purple)
                        Text("Local Storage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(scanManager.detectedDisks.count) Physical \(scanManager.detectedDisks.count == 1 ? "Drive" : "Drives")")
                            .font(.headline)
                    }
                    .padding()
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    
                    // Remote Hosts Card
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "server.rack")
                            .font(.title)
                            .foregroundColor(.teal)
                        Text("Network Hosts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(scanManager.remoteHosts.count) SSH \(scanManager.remoteHosts.count == 1 ? "Host" : "Hosts")")
                            .font(.headline)
                    }
                    .padding()
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding(.horizontal)
                
                // Feature list / Quick Guide
                VStack(alignment: .leading, spacing: 18) {
                    Text("Features & Quick Guide")
                        .font(.headline)
                        .padding(.bottom, 5)
                    
                    HStack(alignment: .top, spacing: 15) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scan Physical Drives")
                                .fontWeight(.semibold)
                            Text("Select any local physical SSD or remote storage node from the sidebar to retrieve S.M.A.R.T. diagnostics, write logs, and lifespans.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 15) {
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.title)
                            .foregroundColor(.teal)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remote SSH Monitoring")
                                .fontWeight(.semibold)
                            Text("Easily check the status of remote systems (e.g. Linux servers, NAS) over secure SSH on Port 22. Online statuses check dynamically in background.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 15) {
                        Image(systemName: "usb.and.pc")
                            .font(.title)
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dynamic USB Support")
                                .fontWeight(.semibold)
                            Text("Plug in any external USB drive to see it appear on the sidebar immediately. Safe ejection (Eject button) helps unmount nodes securely.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Export Formats and Helpers
enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown (.md)"
    case pdf = "PDF Document (.pdf)"
    case word = "Word Document (.doc)"
    case excel = "Excel/CSV (.csv)"
    
    var id: String { self.rawValue }
}

func generateConsolidatedMarkdownReport(devices: [StorageDevice], scanManager: DiskScanManager, dateStr: String) -> String {
    var md = """
    ==================================================
    ⚡ SmartMac — S.M.A.R.T. Storage Telemetry
    Consolidated Diagnostic Report
    ==================================================
    - **Date Generated:** \(dateStr)
    - **Devices Reported:** \(devices.count)
    
    ==================================================
    
    """
    
    for device in devices {
        let key = "\(device.hostId?.uuidString ?? "local")-\(device.path)"
        let output = scanManager.scanResults[key]
        let hostInfo = device.isRemote ? "Remote Host: \(scanManager.remoteHosts.first(where: { $0.id == device.hostId })?.name ?? "Remote") (IP: \(device.address ?? ""))" : "Local Machine (\(Host.current().localizedName ?? "Local Mac"))"
        
        let tech = output?.storageTechnology ?? "Solid State / Flash Storage"
        let sectorSize = (output?.logicalBlockSize != nil) ? "\(output?.logicalBlockSize ?? 0) bytes logical, \(output?.physicalBlockSize ?? 0) bytes physical" : "N/A"
        let capacity = output?.userCapacity?.text ?? "N/A"
        let smartStatusStr = (output?.smartSupport?.available == true) ? "Supported, \(output?.smartSupport?.enabled == true ? "Enabled" : "Disabled")" : "N/A"
        
        md += "## Device: \(output?.modelName ?? device.name) (\(device.path))\n"
        md += "- **Location:** \(hostInfo)\n"
        md += "- **Storage Technology:** \(tech)\n"
        md += "- **Formatted Capacity:** \(capacity)\n"
        md += "- **Serial Number:** \(output?.serialNumber ?? "N/A")\n"
        md += "- **Firmware Version:** \(output?.firmwareVersion ?? "N/A")\n"
        md += "- **Connection Protocol:** \(output?.device?.protocolName ?? (device.isRemote ? "Remote SSH" : "Local Direct"))\n"
        md += "- **Sector Sizes:** \(sectorSize)\n"
        md += "- **S.M.A.R.T. Compliance:** \(smartStatusStr)\n\n"
        
        if let result = output {
            let diagnosis = result.runDiagnosis()
            md += "### Health Assessment\n"
            md += "- **Status:** **\(diagnosis.status.rawValue.uppercased())**\n"
            md += "- **Message:** \(diagnosis.message)\n"
            
            if let temp = result.temperature?.current {
                md += "- **Temperature:** \(temp) °C\n"
            }
            
            if let log = result.nvmeSmartHealthInformationLog {
                let healthPct = 100 - (log.percentageUsed ?? 0)
                let tbWritten = Double(log.dataUnitsWritten ?? 0) * 1000 * 512 / (1024*1024*1024*1024)
                let tbRead = Double(log.dataUnitsRead ?? 0) * 1000 * 512 / (1024*1024*1024*1024)
                md += """
                - **Remaining Life (Health):** \(healthPct)%
                - **Data Written:** \(String(format: "%.2f TB", tbWritten))
                - **Data Read:** \(String(format: "%.2f TB", tbRead))
                - **Power On Hours:** \(log.powerOnHours ?? 0) hours
                - **Power Cycles:** \(log.powerCycles ?? 0)
                - **Unsafe Shutdowns:** \(log.unsafeShutdowns ?? 0)
                - **Media Errors:** \(log.mediaErrors ?? 0)
                
                """
            } else if let hours = result.powerOnTime?.hours {
                md += "- **Power On Hours:** \(hours) hours\n\n"
            }
            
            if let wear = result.estimateWear() {
                md += "### SSD Lifespan & Wear Projection\n"
                md += "- **Total Bytes Written:** \(String(format: "%.2f TB", wear.totalTBWritten)) (Standard Lifetime: \(String(format: "%.0f TBW", wear.standardTBW)))\n"
                md += "- **Remaining Budget:** \(String(format: "%.2f TB remaining", wear.remainingTB))\n"
                md += "- **Avg. Daily Write Speed:** \(String(format: "%.2f GB / day", wear.dailyWriteAverageGB))\n"
                if let years = wear.estimatedYearsRemaining {
                    md += "- **Estimated Lifespan:** \(String(format: "%.1f years remaining", years))\n"
                } else {
                    md += "- **Estimated Lifespan:** Calibrating (> 10 years expected)\n"
                }
                md += "- **SSD Wear Rating:** \(wear.healthRating)\n\n"
            }
            
            if let ata = result.ataSmartAttributes, let table = ata.table {
                md += "### S.M.A.R.T. Attributes (SATA)\n"
                md += "| ID | Attribute Name | Value | Worst | Thresh | Raw Value |\n"
                md += "|---|---|---|---|---|---|\n"
                for attr in table {
                    md += "| \(attr.id ?? 0) | \(attr.name ?? "Unknown") | \(attr.value.map { "\($0)" } ?? "-") | \(attr.worst.map { "\($0)" } ?? "-") | \(attr.threshold.map { "\($0)" } ?? "-") | \(attr.raw?.string ?? "-") |\n"
                }
                md += "\n"
            }
        }
        md += "\n---\n\n"
    }
    return md
}

func generateCSVReport(devices: [StorageDevice], scanManager: DiskScanManager) -> String {
    var csv = "Device Path,Host,Model Name,Serial Number,Health Status,Temperature (C),Remaining Life (%),Power On Hours,Data Written (TB),Media Errors\n"
    
    for device in devices {
        let key = "\(device.hostId?.uuidString ?? "local")-\(device.path)"
        let output = scanManager.scanResults[key]
        let hostName = device.isRemote ? (device.address ?? "Remote") : "Local Mac"
        let model = output?.modelName ?? device.name
        let serial = output?.serialNumber ?? "N/A"
        let diagnosis = output?.runDiagnosis()
        let status = diagnosis?.status.rawValue.uppercased() ?? "UNKNOWN"
        let temp = output?.temperature?.current.map { "\($0)" } ?? ""
        
        var life = ""
        var hours = ""
        var written = ""
        var mediaErrors = ""
        
        if let log = output?.nvmeSmartHealthInformationLog {
            life = "\(100 - (log.percentageUsed ?? 0))"
            hours = "\(log.powerOnHours ?? 0)"
            written = String(format: "%.2f", Double(log.dataUnitsWritten ?? 0) * 1000 * 512 / (1024*1024*1024*1024))
            mediaErrors = "\(log.mediaErrors ?? 0)"
        } else if let hoursVal = output?.powerOnTime?.hours {
            hours = "\(hoursVal)"
        }
        
        let cleanModel = model.replacingOccurrences(of: ",", with: " ")
        csv += "\(device.path),\(hostName),\(cleanModel),\(serial),\(status),\(temp),\(life),\(hours),\(written),\(mediaErrors)\n"
    }
    
    return csv
}

func generateConsolidatedWordHTMLReport(devices: [StorageDevice], scanManager: DiskScanManager, dateStr: String) -> String {
    var html = """
    <html>
    <head>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; color: #333; }
        h1 { color: #004085; border-bottom: 2px solid #004085; padding-bottom: 10px; }
        h2 { color: #17a2b8; margin-top: 30px; page-break-before: always; }
        h2:first-of-type { page-break-before: avoid; }
        table { border-collapse: collapse; width: 100%; margin-top: 15px; }
        th, td { border: 1px solid #dee2e6; padding: 10px; text-align: left; }
        th { background-color: #f8f9fa; font-weight: bold; }
        .status-badge { display: inline-block; padding: 6px 12px; color: white; background-color: #000; font-weight: bold; border-radius: 4px; }
    </style>
    </head>
    <body>
        <div style="background: linear-gradient(135deg, #004085, #17a2b8); color: white; padding: 25px; border-radius: 8px; margin-bottom: 25px; text-align: center;">
            <h1 style="margin: 0; font-size: 28px; border: none; color: white; padding: 0;">SmartMac</h1>
            <p style="margin: 5px 0 0 0; font-size: 16px; opacity: 0.9;">S.M.A.R.T. Storage Telemetry & Consolidated Diagnostics</p>
        </div>
        <p><strong>Date Generated:</strong> \(dateStr)</p>
        <p><strong>Devices Included:</strong> \(devices.count)</p>
    """
    
    for device in devices {
        let key = "\(device.hostId?.uuidString ?? "local")-\(device.path)"
        let output = scanManager.scanResults[key]
        let model = output?.modelName ?? device.name
        let serial = output?.serialNumber ?? "N/A"
        let firmware = output?.firmwareVersion ?? "N/A"
        let proto = output?.device?.protocolName ?? (device.isRemote ? "Remote SSH" : "Local Direct")
        let diagnosis = output?.runDiagnosis()
        let status = diagnosis?.status.rawValue.uppercased() ?? "UNKNOWN"
        let statusColor = status == "HEALTHY" ? "#28a745" : (status == "WARNING" ? "#ffc107" : "#dc3545")
        let hostInfo = device.isRemote ? "Remote Host: \(scanManager.remoteHosts.first(where: { $0.id == device.hostId })?.name ?? "Remote") (IP: \(device.address ?? ""))" : "Local Machine (\(Host.current().localizedName ?? "Local Mac"))"
        
        let tech = output?.storageTechnology ?? "Solid State / Flash Storage"
        let sectorSize = (output?.logicalBlockSize != nil) ? "\(output?.logicalBlockSize ?? 0) bytes logical, \(output?.physicalBlockSize ?? 0) bytes physical" : "N/A"
        let capacity = output?.userCapacity?.text ?? "N/A"
        let smartStatusStr = (output?.smartSupport?.available == true) ? "Supported, \(output?.smartSupport?.enabled == true ? "Enabled" : "Disabled")" : "N/A"
        
        html += """
        <h2>Device: \(model) (\(device.path))</h2>
        <p><strong>Location:</strong> \(hostInfo)</p>
        
        <h3>Device Specifications</h3>
        <table>
            <tr><th>Property</th><th>Value</th></tr>
            <tr><td>Device Path</td><td>\(device.path)</td></tr>
            <tr><td>Model Name</td><td>\(model)</td></tr>
            <tr><td>Storage Technology</td><td>\(tech)</td></tr>
            <tr><td>Formatted Capacity</td><td>\(capacity)</td></tr>
            <tr><td>Serial Number</td><td>\(serial)</td></tr>
            <tr><td>Firmware Version</td><td>\(firmware)</td></tr>
            <tr><td>Connection Protocol</td><td>\(proto)</td></tr>
            <tr><td>Sector Sizes</td><td>\(sectorSize)</td></tr>
            <tr><td>S.M.A.R.T. Compliance</td><td>\(smartStatusStr)</td></tr>
        </table>
        
        <h3>Health Overview</h3>
        <p><strong>Status:</strong> <span class="status-badge" style="background-color: \(statusColor); color: white;">\(status)</span></p>
        """
        
        if let diag = diagnosis {
            html += "<p><strong>Diagnosis Detail:</strong> \(diag.message)</p>"
        }
        
        if let result = output {
            if let temp = result.temperature?.current {
                html += "<p><strong>Current Temperature:</strong> \(temp) &deg;C</p>"
            }
            
            if let log = result.nvmeSmartHealthInformationLog {
                let healthPct = 100 - (log.percentageUsed ?? 0)
                let tbWritten = Double(log.dataUnitsWritten ?? 0) * 1000 * 512 / (1024*1024*1024*1024)
                let tbRead = Double(log.dataUnitsRead ?? 0) * 1000 * 512 / (1024*1024*1024*1024)
                html += """
                <h3>Detailed Telemetry (NVMe)</h3>
                <table>
                    <tr><th>Metric</th><th>Value</th></tr>
                    <tr><td>Remaining Life</td><td>\(healthPct)%</td></tr>
                    <tr><td>Data Written</td><td>\(String(format: "%.2f TB", tbWritten))</td></tr>
                    <tr><td>Data Read</td><td>\(String(format: "%.2f TB", tbRead))</td></tr>
                    <tr><td>Power Cycles</td><td>\(log.powerCycles ?? 0)</td></tr>
                    <tr><td>Power On Hours</td><td>\(log.powerOnHours ?? 0) hours</td></tr>
                    <tr><td>Unsafe Shutdowns</td><td>\(log.unsafeShutdowns ?? 0)</td></tr>
                    <tr><td>Media Errors</td><td>\(log.mediaErrors ?? 0)</td></tr>
                </table>
                """
            }
            
            if let wear = result.estimateWear() {
                html += """
                <h3>SSD Lifespan & Wear Projection</h3>
                <table>
                    <tr><th>Metric</th><th>Value</th></tr>
                    <tr><td>Total Bytes Written</td><td>\(String(format: "%.2f TB", wear.totalTBWritten)) (Standard Lifetime: \(String(format: "%.0f TBW", wear.standardTBW)))</td></tr>
                    <tr><td>Remaining Budget</td><td>\(String(format: "%.2f TB remaining", wear.remainingTB))</td></tr>
                    <tr><td>Avg. Daily Write Speed</td><td>\(String(format: "%.2f GB / day", wear.dailyWriteAverageGB))</td></tr>
                    <tr><td>Estimated Lifespan</td><td>\(wear.estimatedYearsRemaining.map { String(format: "%.1f years remaining", $0) } ?? "Calibrating (> 10 years expected)")</td></tr>
                    <tr><td>SSD Wear Rating</td><td>\(wear.healthRating)</td></tr>
                </table>
                """
            }
            
            if let ata = result.ataSmartAttributes, let table = ata.table {
                html += """
                <h3>S.M.A.R.T. Attributes (SATA)</h3>
                <table>
                    <tr><th>ID</th><th>Attribute Name</th><th>Value</th><th>Worst</th><th>Threshold</th><th>Raw Value</th></tr>
                """
                for attr in table {
                    html += """
                    <tr>
                        <td>\(attr.id ?? 0)</td>
                        <td>\(attr.name ?? "Unknown")</td>
                        <td>\(attr.value.map { "\($0)" } ?? "-")</td>
                        <td>\(attr.worst.map { "\($0)" } ?? "-")</td>
                        <td>\(attr.threshold.map { "\($0)" } ?? "-")</td>
                        <td>\(attr.raw?.string ?? "-")</td>
                    </tr>
                    """
                }
                html += "</table>"
            }
        }
    }
    
    html += """
    </body>
    </html>
    """
    
    return html
}

// MARK: - Single Report PDF View Component (For Multi-page PDF generation)
struct SingleReportPDFView: View {
    let device: StorageDevice
    let output: SmartctlOutput?
    let scanManager: DiskScanManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 15) {
                Image(systemName: "gauge.extension.shortcut.minimize")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("SmartMac")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("S.M.A.R.T. Storage Telemetry")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Diagnostic Report")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Text("Consolidated Document")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 5)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Device Specifications")
                    .font(.headline)
                
                let hostInfo = device.isRemote ? "Remote Host: \(scanManager.remoteHosts.first(where: { $0.id == device.hostId })?.name ?? "Remote") (IP: \(device.address ?? ""))" : "Local Machine (\(Host.current().localizedName ?? "Local Mac"))"
                let tech = output?.storageTechnology ?? "Solid State / Flash Storage"
                let sectorSize = (output?.logicalBlockSize != nil) ? "\(output?.logicalBlockSize ?? 0) bytes logical, \(output?.physicalBlockSize ?? 0) bytes physical" : "N/A"
                let capacity = output?.userCapacity?.text ?? "N/A"
                let smartStatusStr = (output?.smartSupport?.available == true) ? "Supported, \(output?.smartSupport?.enabled == true ? "Enabled" : "Disabled")" : "N/A"
                
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    GridRow {
                        Text("Location:")
                            .fontWeight(.semibold)
                        Text(hostInfo)
                    }
                    GridRow {
                        Text("Device Path:")
                            .fontWeight(.semibold)
                        Text(device.path)
                    }
                    GridRow {
                        Text("Model Name:")
                            .fontWeight(.semibold)
                        Text(output?.modelName ?? device.name)
                    }
                    GridRow {
                        Text("Storage Tech:")
                            .fontWeight(.semibold)
                        Text(tech)
                    }
                    GridRow {
                        Text("Formatted Cap:")
                            .fontWeight(.semibold)
                        Text(capacity)
                    }
                    GridRow {
                        Text("Serial Number:")
                            .fontWeight(.semibold)
                        Text(output?.serialNumber ?? "N/A")
                    }
                    GridRow {
                        Text("Firmware Ver:")
                            .fontWeight(.semibold)
                        Text(output?.firmwareVersion ?? "N/A")
                    }
                    GridRow {
                        Text("Sector Sizes:")
                            .fontWeight(.semibold)
                        Text(sectorSize)
                    }
                    GridRow {
                        Text("SMART Support:")
                            .fontWeight(.semibold)
                        Text(smartStatusStr)
                    }
                }
                .font(.subheadline)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            if let result = output {
                let diagnosis = result.runDiagnosis()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Health Assessment")
                        .font(.headline)
                    HStack {
                        Text("Overall Status:")
                            .fontWeight(.semibold)
                        Text(diagnosis.status.rawValue.uppercased())
                            .fontWeight(.bold)
                            .foregroundColor(diagnosis.status == .healthy ? .green : .red)
                    }
                    Text(diagnosis.message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                if let log = result.nvmeSmartHealthInformationLog {
                    let healthPct = 100 - (log.percentageUsed ?? 0)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Detailed Telemetry (NVMe)")
                            .font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 6) {
                            GridRow {
                                Text("Remaining Life:")
                                    .fontWeight(.semibold)
                                Text("\(healthPct)%")
                            }
                            GridRow {
                                Text("Data Written:")
                                    .fontWeight(.semibold)
                                let tbWritten = Double(log.dataUnitsWritten ?? 0) * 1000 * 512 / (1024*1024*1024*1024)
                                Text(String(format: "%.2f TB", tbWritten))
                            }
                            GridRow {
                                Text("Power On Hours:")
                                    .fontWeight(.semibold)
                                Text("\(log.powerOnHours ?? 0) hours")
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                if let wear = result.estimateWear() {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SSD Lifespan & Wear Projection")
                            .font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 6) {
                            GridRow {
                                Text("Total Written:")
                                    .fontWeight(.semibold)
                                Text(String(format: "%.2f TB (Standard Lifetime: %.0f TBW)", wear.totalTBWritten, wear.standardTBW))
                            }
                            GridRow {
                                Text("Remaining Budget:")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.2f TB remaining", wear.remainingTB))
                            }
                            GridRow {
                                Text("Avg. Daily Writes:")
                                    .fontWeight(.semibold)
                                Text(String(format: "%.2f GB / day", wear.dailyWriteAverageGB))
                            }
                            GridRow {
                                Text("Estimated Lifespan:")
                                    .fontWeight(.semibold)
                                if let years = wear.estimatedYearsRemaining {
                                    Text(String(format: "%.1f years", years))
                                        .fontWeight(.bold)
                                        .foregroundColor(years > 5 ? .green : .orange)
                                } else {
                                    Text("Calibrating (> 10 years expected)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Health Assessment")
                        .font(.headline)
                    Text("STATUS: NOT SCANNED")
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Text("No S.M.A.R.T. scan was executed for this device in the current session.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            Spacer()
        }
        .padding(40)
        .frame(width: 612, height: 792)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Export Modal Sheet
struct ExportReportSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var scanManager: DiskScanManager
    
    @State private var selectedDevices: Set<String> = []
    @State private var exportFormat: ExportFormat = .markdown
    @State private var isExporting = false
    @State private var exportStatusMessage: String?
    
    private var totalScannedCount: Int {
        return scanManager.allDevices.filter { device in
            let key = "\(device.hostId?.uuidString ?? "local")-\(device.path)"
            return scanManager.scanResults[key] != nil
        }.count
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export Diagnostic Reports")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("1. Select Storage Devices to Include:")
                        .font(.headline)
                    Spacer()
                    if totalScannedCount > 0 {
                        Button("Select All") {
                            let scannedIds = scanManager.allDevices.filter { device in
                                let key = "\(device.hostId?.uuidString ?? "local")-\(device.path)"
                                return scanManager.scanResults[key] != nil
                            }.map { $0.id }
                            selectedDevices = Set(scannedIds)
                        }
                        .buttonStyle(.link)
                        
                        Text("|")
                            .foregroundColor(.secondary)
                        
                        Button("Deselect All") {
                            selectedDevices.removeAll()
                        }
                        .buttonStyle(.link)
                    }
                }
                
                if totalScannedCount == 0 {
                    VStack(spacing: 15) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("No Scanned Drives Found")
                            .font(.headline)
                        Text("Please select a drive from the sidebar, run a 'Scan Now' diagnostic, and return here to export its report.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            // Local System Node
                            let localMachineName = Host.current().localizedName ?? "Local Mac"
                            let localScanned = scanManager.detectedDisks.filter { device in
                                let key = "\(device.hostId?.uuidString ?? "local")-\(device.path)"
                                return scanManager.scanResults[key] != nil
                            }
                            
                            if !localScanned.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(localMachineName, systemImage: "laptopcomputer")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    ForEach(localScanned) { device in
                                        deviceRow(device)
                                    }
                                }
                                .padding(.leading, 5)
                            }
                            
                            // Remote Servers Nodes
                            ForEach(scanManager.remoteHosts) { host in
                                let remoteScanned = scanManager.allDevices.filter { device in
                                    device.hostId == host.id && scanManager.scanResults["\(host.id.uuidString)-\(device.path)"] != nil
                                }
                                
                                if !remoteScanned.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Label("\(host.name) (\(host.ip))", systemImage: "server.rack")
                                            .font(.headline)
                                            .foregroundColor(.teal)
                                        
                                        ForEach(remoteScanned) { device in
                                            deviceRow(device)
                                        }
                                    }
                                    .padding(.leading, 5)
                                    .padding(.top, 5)
                                }
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("2. Choose Export Format:")
                    .font(.headline)
                
                Picker("", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
            }
            
            if let msg = exportStatusMessage {
                Text(msg)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 5)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: {
                    exportReports()
                }) {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Choose Folder & Export")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDevices.isEmpty || isExporting || totalScannedCount == 0)
            }
        }
        .padding()
        // Resizable constraints
        .frame(minWidth: 550, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
    }
    
    private func deviceRow(_ device: StorageDevice) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { selectedDevices.contains(device.id) },
                set: { isSelected in
                    if isSelected {
                        selectedDevices.insert(device.id)
                    } else {
                        selectedDevices.remove(device.id)
                    }
                }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .fontWeight(.medium)
                        Text(device.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: device.path == "/dev/disk0" ? "internaldrive" : "externaldrive")
                        .foregroundColor(device.path == "/dev/disk0" ? .blue : .purple)
                }
            }
            .padding(.leading, 15)
        }
    }
    
    private func exportReports() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Select Export Destination Folder"
        openPanel.prompt = "Select Folder"
        
        openPanel.begin { response in
            if response == .OK, let folderURL = openPanel.url {
                isExporting = true
                exportStatusMessage = "Generating consolidated report..."
                
                let devicesToExport = scanManager.allDevices.filter { selectedDevices.contains($0.id) }
                let formatter = DateFormatter()
                formatter.dateFormat = "dd-MM-yyyy"
                let dateStr = formatter.string(from: Date())
                
                Task {
                    let baseName = "SmartMac_Diagnostic_Report_\(dateStr)"
                    var success = false
                    
                    do {
                        switch exportFormat {
                        case .markdown:
                            let content = generateConsolidatedMarkdownReport(devices: devicesToExport, scanManager: scanManager, dateStr: dateStr)
                            let fileURL = folderURL.appendingPathComponent("\(baseName).md")
                            try content.write(to: fileURL, atomically: true, encoding: .utf8)
                            success = true
                            
                        case .word:
                            let content = generateConsolidatedWordHTMLReport(devices: devicesToExport, scanManager: scanManager, dateStr: dateStr)
                            let fileURL = folderURL.appendingPathComponent("\(baseName).doc")
                            try content.write(to: fileURL, atomically: true, encoding: .utf8)
                            success = true
                            
                        case .excel:
                            let content = generateCSVReport(devices: devicesToExport, scanManager: scanManager)
                            let fileURL = folderURL.appendingPathComponent("\(baseName).csv")
                            try content.write(to: fileURL, atomically: true, encoding: .utf8)
                            success = true
                            
                        case .pdf:
                            let fileURL = folderURL.appendingPathComponent("\(baseName).pdf")
                            await saveAsConsolidatedPDF(devices: devicesToExport, url: fileURL)
                            success = true
                        }
                    } catch {
                        print("Failed to export: \(error)")
                    }
                    
                    await MainActor.run {
                        isExporting = false
                        if success {
                            exportStatusMessage = "Successfully exported consolidated report!"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                dismiss()
                            }
                        } else {
                            exportStatusMessage = "Failed to generate report. Please try again."
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    private func saveAsConsolidatedPDF(devices: [StorageDevice], url: URL) async {
        let width: CGFloat = 612
        let height: CGFloat = 792
        
        var box = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        guard let pdfContext = CGContext(url as CFURL, mediaBox: &box, nil) else {
            return
        }
        
        for device in devices {
            let key = "\(device.hostId?.uuidString ?? "local")-\(device.path)"
            let output = scanManager.scanResults[key]
            
            let pdfView = SingleReportPDFView(device: device, output: output, scanManager: scanManager)
            let renderer = ImageRenderer(content: pdfView)
            
            pdfContext.beginPDFPage(nil)
            renderer.render { size, context in
                context(pdfContext)
            }
            pdfContext.endPDFPage()
        }
        pdfContext.closePDF()
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

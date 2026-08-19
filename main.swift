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

// MARK: - Disk Info Model (Mock Data)
struct StorageDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: DeviceType
    let size: String
    let health: HealthStatus
    let temperature: Int
    let percentRemaining: Int?
    let isRemote: Bool
    let address: String?
    
    enum DeviceType {
        case internalNVMe
        case externalUSB
        case networkShare
    }
    
    enum HealthStatus: String {
        case healthy = "Healthy"
        case warning = "Warning"
        case critical = "Critical"
        
        var color: Color {
            switch self {
            case .healthy: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @AppStorage("selectedTheme") private var selectedTheme: AppTheme = .system
    @State private var selectedDevice: StorageDevice?
    @State private var showSettings = false
    
    let devices = [
        StorageDevice(name: "Macintosh HD", type: .internalNVMe, size: "1 TB NVMe SSD", health: .healthy, temperature: 32, percentRemaining: 98, isRemote: false, address: nil),
        StorageDevice(name: "T7 Shield", type: .externalUSB, size: "2 TB USB-C SSD", health: .healthy, temperature: 28, percentRemaining: 94, isRemote: false, address: nil),
        StorageDevice(name: "Synology NAS", type: .networkShare, size: "16 TB RAID 5 HDD", health: .warning, temperature: 41, percentRemaining: nil, isRemote: true, address: "192.168.1.100"),
        StorageDevice(name: "i7 HomeLab", type: .networkShare, size: "512 GB SATA SSD", health: .healthy, temperature: 35, percentRemaining: 88, isRemote: true, address: "192.168.1.200")
    ]
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedDevice) {
                Section("Local Storage") {
                    ForEach(devices.filter { !$0.isRemote }, id: \.self) { device in
                        NavigationLink(value: device) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.headline)
                                    Text(device.size)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: device.type == .internalNVMe ? "internaldrive" : "externaldrive")
                                    .imageScale(.large)
                                    .foregroundColor(device.health.color)
                            }
                        }
                    }
                }
                
                Section("Network Hosts (SSH)") {
                    ForEach(devices.filter { $0.isRemote }, id: \.self) { device in
                        NavigationLink(value: device) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.headline)
                                    Text(device.address ?? "")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "server.rack")
                                    .imageScale(.large)
                                    .foregroundColor(device.health.color)
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
                    
                    Button(action: { }) {
                        Label("Scan All", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding()
                }
            }
        } detail: {
            if let device = selectedDevice {
                DiskDetailView(device: device)
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
    @State private var selectedTab = "overview"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 15) {
                Image(systemName: device.type == .internalNVMe ? "internaldrive" : (device.type == .externalUSB ? "externaldrive" : "server.rack"))
                    .font(.system(size: 40))
                    .foregroundColor(device.health.color)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text(device.health.rawValue.uppercased())
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(device.health.color.opacity(0.2))
                            .foregroundColor(device.health.color)
                            .cornerRadius(5)
                    }
                    Text(device.size)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: { }) {
                    Label("Scan Disk", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: { }) {
                    Image(systemName: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Export diagnostic report")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            Picker("", selection: $selectedTab) {
                Text("Overview").tag("overview")
                Text("SMART Attributes").tag("smart")
                Text("Performance & Speed").tag("speed")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if selectedTab == "overview" {
                        OverviewTab(device: device)
                    } else if selectedTab == "smart" {
                        SMARTAttributesTab()
                    } else {
                        PerformanceTab()
                    }
                }
                .padding()
            }
            
            Spacer()
        }
    }
}

// MARK: - Overview Tab Sub-view
struct OverviewTab: View {
    let device: StorageDevice
    
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 15) {
            GridRow {
                Text("Device Temperature:")
                    .fontWeight(.semibold)
                HStack {
                    Text("\(device.temperature) °C")
                        .foregroundColor(device.temperature > 40 ? .orange : .primary)
                    Image(systemName: "thermometer.medium")
                        .foregroundColor(device.temperature > 40 ? .orange : .blue)
                }
            }
            
            if let life = device.percentRemaining {
                GridRow {
                    Text("Remaining Life Indicator:")
                        .fontWeight(.semibold)
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: Double(life), total: 100)
                            .tint(life < 20 ? .red : (life < 50 ? .orange : .green))
                        Text("\(life)% (Great health)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            GridRow {
                Text("Interface Protocol:")
                    .fontWeight(.semibold)
                Text(device.isRemote ? "SSH / Network" : (device.type == .internalNVMe ? "Apple Fabric NVMe" : "USB 3.2 (SAT Mode)"))
            }
            
            GridRow {
                Text("Last Diagnostic Run:")
                    .fontWeight(.semibold)
                Text("Today at 22:56 (On-Demand)")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - SMART Attributes Tab Sub-view
struct SMARTAttributesTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detailed S.M.A.R.T. Status Indicators")
                .font(.headline)
            
            Table(of: SMARTAttribute.self) {
                TableColumn("ID", value: \.idString)
                    .width(min: 30, max: 50)
                TableColumn("Attribute Name", value: \.name)
                    .width(min: 150, max: 250)
                TableColumn("Raw Value", value: \.rawValue)
                TableColumn("Threshold", value: \.threshold)
                TableColumn("Status", value: \.status)
            } rows: {
                TableRow(SMARTAttribute(id: 1, name: "Raw Read Error Rate", rawValue: "0", threshold: "51", status: "OK"))
                TableRow(SMARTAttribute(id: 5, name: "Reallocated Sectors Count", rawValue: "0", threshold: "10", status: "OK"))
                TableRow(SMARTAttribute(id: 9, name: "Power-On Hours", rawValue: "1,248 hrs", threshold: "0", status: "OK"))
                TableRow(SMARTAttribute(id: 12, name: "Power Cycle Count", rawValue: "189", threshold: "0", status: "OK"))
                TableRow(SMARTAttribute(id: 194, name: "Temperature", rawValue: "32°C", threshold: "0", status: "OK"))
            }
            .frame(height: 250)
        }
    }
}

struct SMARTAttribute: Identifiable {
    let id: Int
    let name: String
    let rawValue: String
    let threshold: String
    let status: String
    
    var idString: String { String(id) }
}

// MARK: - Performance Tab Sub-view
struct PerformanceTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("On-Demand Speed Test")
                .font(.headline)
            
            HStack(spacing: 20) {
                VStack {
                    Text("READ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("1,850 MB/s")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                VStack {
                    Text("WRITE")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("1,420 MB/s")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
            
            Button(action: { }) {
                Label("Start Speed Benchmark", systemImage: "gauge.medium")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

// MARK: - Settings View (Sheet)
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedTheme: AppTheme
    
    @State private var remoteHosts = ["Synology NAS (192.168.1.100)", "i7 HomeLab (192.168.1.200)"]
    @State private var newHost = ""
    
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
                
                Divider()
                
                Section(header: Text("Remote SSH Connections").font(.headline)) {
                    List {
                        ForEach(remoteHosts, id: \.self) { host in
                            HStack {
                                Text(host)
                                Spacer()
                                Button(action: { remoteHosts.removeAll(where: { $0 == host }) }) {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 100)
                    
                    HStack {
                        TextField("e.g. user@192.168.1.50", text: $newHost)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("Add SSH Host") {
                            if !newHost.isEmpty {
                                remoteHosts.append(newHost)
                                newHost = ""
                            }
                        }
                    }
                }
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
        .frame(width: 450, height: 450)
    }
}

// MARK: - App Entrypoint
@main
struct SmartMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 550)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

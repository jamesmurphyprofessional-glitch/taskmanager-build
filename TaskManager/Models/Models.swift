import Foundation
import AppKit

enum SidebarPage: String, CaseIterable, Identifiable {
    case processes = "Processes"
    case performance = "Performance"
    case appHistory = "App history"
    case startup = "Startup apps"
    case users = "Users"
    case details = "Details"
    case services = "Services"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .processes: return "square.stack.3d.up.fill"
        case .performance: return "speedometer"
        case .appHistory: return "clock.arrow.circlepath"
        case .startup: return "power.circle"
        case .users: return "person.2.fill"
        case .details: return "list.bullet.rectangle"
        case .services: return "gearshape.2.fill"
        }
    }
}

enum ProcessKind: String, CaseIterable {
    case app = "Apps"
    case background = "Background processes"
    case system = "macOS processes"
}

enum ProcessRunStatus: String {
    case running = "Running"
    case sleeping = "Sleeping"
    case idle = "Idle"
    case stopped = "Suspended"
    case zombie = "Zombie"
    case unknown = "Unknown"

    init(pbiStatus: UInt32) {
        switch Int32(pbiStatus) {
        case SRUN: self = .running
        case SSLEEP: self = .sleeping
        case SIDL: self = .idle
        case SSTOP: self = .stopped
        case SZOMB: self = .zombie
        default: self = .unknown
        }
    }
}

enum PowerUsage: String, Comparable {
    case veryLow = "Very low"
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"

    private var rank: Int {
        switch self {
        case .veryLow: return 0
        case .low: return 1
        case .moderate: return 2
        case .high: return 3
        }
    }

    static func < (lhs: PowerUsage, rhs: PowerUsage) -> Bool {
        lhs.rank < rhs.rank
    }

    static func classify(cpuPercent: Double, diskMBps: Double, wakeupsPerSec: Double) -> PowerUsage {
        if cpuPercent >= 15 || diskMBps >= 20 || wakeupsPerSec >= 80 { return .high }
        if cpuPercent >= 4 || diskMBps >= 4 || wakeupsPerSec >= 25 { return .moderate }
        if cpuPercent >= 0.6 || diskMBps >= 0.4 || wakeupsPerSec >= 5 { return .low }
        return .veryLow
    }
}

enum UpdateSpeed: String, CaseIterable, Identifiable {
    case high = "High"
    case normal = "Normal"
    case low = "Low"
    case paused = "Paused"

    var id: String { rawValue }

    var interval: TimeInterval? {
        switch self {
        case .high: return 0.5
        case .normal: return 1.0
        case .low: return 4.0
        case .paused: return nil
        }
    }
}

enum PerformancePane: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case disk = "Disk"
    case network = "Ethernet"
    case gpu = "GPU"

    var id: String { rawValue }
}

struct LiveProcess: Identifiable, Hashable {
    var id: Int32 { pid }
    var pid: Int32
    var ppid: Int32
    var name: String
    var displayName: String
    var path: String
    var user: String
    var uid: uid_t
    var status: ProcessRunStatus
    var kind: ProcessKind
    var cpuPercent: Double
    var cpuTimeSeconds: Double
    var memoryBytes: UInt64
    var virtualBytes: UInt64
    var compressedBytes: UInt64
    var diskReadBps: Double
    var diskWriteBps: Double
    var networkInBps: Double
    var networkOutBps: Double
    var gpuPercent: Double
    var threads: Int32
    var ports: UInt32
    var nice: Int32
    var architecture: String
    var publisher: String
    var bundleIdentifier: String?
    var isApplication: Bool
    var isNotResponding: Bool
    var wakeupsPerSec: Double
    var startDate: Date?
    var icon: NSImage?

    var diskMBps: Double { (diskReadBps + diskWriteBps) / 1_048_576.0 }
    var networkMBps: Double { (networkInBps + networkOutBps) / 1_048_576.0 }
    var memoryMB: Double { Double(memoryBytes) / 1_048_576.0 }
    var powerUsage: PowerUsage {
        PowerUsage.classify(cpuPercent: cpuPercent, diskMBps: diskMBps, wakeupsPerSec: wakeupsPerSec)
    }

    var statusLabel: String {
        if isNotResponding { return "Not responding" }
        return status.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    static func == (lhs: LiveProcess, rhs: LiveProcess) -> Bool {
        lhs.pid == rhs.pid
    }
}

struct ProcessGroup: Identifiable {
    var id: ProcessKind { kind }
    var kind: ProcessKind
    var processes: [LiveProcess]

    var cpuPercent: Double { processes.reduce(0) { $0 + $1.cpuPercent } }
    var memoryBytes: UInt64 { processes.reduce(0) { $0 + $1.memoryBytes } }
    var diskMBps: Double { processes.reduce(0) { $0 + $1.diskMBps } }
    var networkMBps: Double { processes.reduce(0) { $0 + $1.networkMBps } }
}

struct AppHistoryRow: Identifiable, Hashable {
    var id: String
    var name: String
    var publisher: String
    var cpuTimeSeconds: Double
    var networkBytes: UInt64
    var peakMemoryBytes: UInt64
    var icon: NSImage?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AppHistoryRow, rhs: AppHistoryRow) -> Bool {
        lhs.id == rhs.id
    }
}

struct LaunchService: Identifiable, Hashable {
    var id: String { label }
    var label: String
    var pid: Int32?
    var statusCode: Int32
    var running: Bool
    var domain: String
    var plistPath: String?
    var program: String?
    var descriptionText: String?

    var statusText: String {
        if running { return "Running" }
        if statusCode == 0 { return "Stopped" }
        return "Exited (\(statusCode))"
    }
}

struct StartupEntry: Identifiable, Hashable {
    enum Kind: String {
        case loginItem = "Login item"
        case launchAgent = "Launch agent"
        case launchDaemon = "Launch daemon"
    }

    var id: String
    var name: String
    var kind: Kind
    var enabled: Bool
    var path: String
    var publisher: String
    var impact: String
    var label: String?
}

struct SessionUser: Identifiable, Hashable {
    var id: uid_t { uid }
    var uid: uid_t
    var name: String
    var fullName: String
    var isConsole: Bool
    var processCount: Int
    var cpuPercent: Double
    var memoryBytes: UInt64
}

struct CPUSnapshot {
    var overall: Double = 0
    var user: Double = 0
    var system: Double = 0
    var idle: Double = 0
    var perCore: [Double] = []
    var pCores: Int = 0
    var eCores: Int = 0
    var logicalCores: Int = 0
    var brand: String = "Apple Silicon"
    var uptime: TimeInterval = 0
    var processCount: Int = 0
    var threadCount: Int = 0
    var handleCount: Int = 0
    var thermalState: String = "Nominal"
}

struct MemorySnapshot {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var wired: UInt64 = 0
    var active: UInt64 = 0
    var inactive: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var free: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var appMemory: UInt64 = 0
    var pageIns: UInt64 = 0
    var pageOuts: UInt64 = 0
    var pageSize: UInt64 = 4096

    var usedPercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }
}

struct DiskSnapshot: Identifiable {
    var id: String { name }
    var name: String
    var mount: String
    var total: UInt64
    var free: UInt64
    var readBps: Double
    var writeBps: Double
    var readOps: Double
    var writeOps: Double
    var responseMS: Double

    var used: UInt64 { total > free ? total - free : 0 }
    var usedPercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }
}

struct NetworkAdapterSnapshot: Identifiable {
    var id: String { name }
    var name: String
    var displayName: String
    var ipv4: String?
    var inBps: Double
    var outBps: Double
    var inPackets: Double
    var outPackets: Double
    var up: Bool
}

struct GPUSnapshot {
    var utilization: Double = 0
    var renderer: Double = 0
    var tiler: Double = 0
    var allocatedBytes: UInt64 = 0
    var inUseBytes: UInt64 = 0
    var name: String = "Apple GPU"
}

struct PerformanceHistory {
    var cpu: [Double] = []
    var memory: [Double] = []
    var diskRead: [Double] = []
    var diskWrite: [Double] = []
    var netIn: [Double] = []
    var netOut: [Double] = []
    var gpu: [Double] = []
    var perCore: [[Double]] = []

    static let capacity = 60

    mutating func append<T>(_ value: T, to keyPath: WritableKeyPath<PerformanceHistory, [T]>) {
        self[keyPath: keyPath].append(value)
        if self[keyPath: keyPath].count > Self.capacity {
            self[keyPath: keyPath].removeFirst(self[keyPath: keyPath].count - Self.capacity)
        }
    }
}

enum ProcessColumn: String, CaseIterable, Identifiable {
    case name = "Name"
    case status = "Status"
    case cpu = "CPU"
    case memory = "Memory"
    case disk = "Disk"
    case network = "Network"
    case gpu = "GPU"
    case pid = "PID"
    case user = "User"
    case power = "Power usage"
    case arch = "Architecture"
    case publisher = "Publisher"

    var id: String { rawValue }
}

enum DetailColumn: String, CaseIterable, Identifiable {
    case name = "Name"
    case pid = "PID"
    case status = "Status"
    case user = "User"
    case cpu = "CPU"
    case memory = "Memory"
    case disk = "Disk"
    case threads = "Threads"
    case handles = "Ports"
    case nice = "Priority"
    case arch = "Architecture"
    case path = "Command line"

    var id: String { rawValue }
}

struct ActionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

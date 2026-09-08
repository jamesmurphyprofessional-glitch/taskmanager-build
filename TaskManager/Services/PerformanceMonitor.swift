import Darwin
import Foundation
import IOKit
import IOKit.storage

final class PerformanceMonitor: @unchecked Sendable {
    private var lastCPU: [TMCPUTicks] = []
    private var lastIfs: [String: TMIfStats] = [:]
    private var lastDisk: [String: (read: UInt64, write: UInt64, readOps: UInt64, writeOps: UInt64, time: TimeInterval)] = [:]
    private var lastStamp = ProcessInfo.processInfo.systemUptime

    func sample(processCount: Int, threadCount: Int, handleCount: Int) -> (
        cpu: CPUSnapshot,
        memory: MemorySnapshot,
        disks: [DiskSnapshot],
        networks: [NetworkAdapterSnapshot],
        gpu: GPUSnapshot
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(now - lastStamp, 0.001)
        lastStamp = now
        return (
            sampleCPU(processCount: processCount, threadCount: threadCount, handleCount: handleCount),
            sampleMemory(),
            sampleDisks(dt: dt),
            sampleNetwork(dt: dt),
            sampleGPU()
        )
    }

    private func sampleCPU(processCount: Int, threadCount: Int, handleCount: Int) -> CPUSnapshot {
        var ticks = [TMCPUTicks](repeating: TMCPUTicks(user: 0, system: 0, idle: 0, nice: 0), count: 64)
        let count = Int(tm_cpu_ticks(&ticks, Int32(ticks.count)))
        ticks = Array(ticks.prefix(count))

        var perCore: [Double] = []
        var userSum = 0.0
        var systemSum = 0.0
        var idleSum = 0.0
        var usedSum = 0.0

        for (index, current) in ticks.enumerated() {
            let prev = index < lastCPU.count ? lastCPU[index] : current
            let user = Double(current.user &- prev.user)
            let system = Double(current.system &- prev.system)
            let nice = Double(current.nice &- prev.nice)
            let idle = Double(current.idle &- prev.idle)
            let total = user + system + nice + idle
            let used = user + system + nice
            if total > 0 {
                perCore.append(used / total * 100)
                userSum += user
                systemSum += system
                idleSum += idle
                usedSum += used
            } else {
                perCore.append(0)
            }
        }
        lastCPU = ticks
        let totalTicks = userSum + systemSum + idleSum + (ticks.count > 0 ? 0 : 1)
        let denom = max(userSum + systemSum + idleSum, 1)

        var snapshot = CPUSnapshot()
        snapshot.overall = usedSum / denom * 100
        snapshot.user = userSum / denom * 100
        snapshot.system = systemSum / denom * 100
        snapshot.idle = idleSum / denom * 100
        snapshot.perCore = perCore
        snapshot.logicalCores = ProcessInfo.processInfo.processorCount
        snapshot.pCores = sysctlInt("hw.perflevel0.logicalcpu") ?? snapshot.logicalCores
        snapshot.eCores = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        snapshot.brand = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        snapshot.uptime = ProcessInfo.processInfo.systemUptime
        snapshot.processCount = processCount
        snapshot.threadCount = threadCount
        snapshot.handleCount = handleCount
        snapshot.thermalState = {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: return "Nominal"
            case .fair: return "Fair"
            case .serious: return "Serious"
            case .critical: return "Critical"
            @unknown default: return "Unknown"
            }
        }()
        _ = totalTicks
        return snapshot
    }

    private func sampleMemory() -> MemorySnapshot {
        var snapshot = MemorySnapshot()
        snapshot.pageSize = UInt64(vm_kernel_page_size)
        snapshot.total = UInt64(ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        if result == KERN_SUCCESS {
            let page = snapshot.pageSize
            snapshot.free = UInt64(stats.free_count) * page
            snapshot.active = UInt64(stats.active_count) * page
            snapshot.inactive = UInt64(stats.inactive_count) * page
            snapshot.wired = UInt64(stats.wire_count) * page
            snapshot.compressed = UInt64(stats.compressor_page_count) * page
            snapshot.cached = UInt64(stats.external_page_count) * page
            snapshot.appMemory = UInt64(stats.internal_page_count) * page
            snapshot.pageIns = UInt64(stats.pageins)
            snapshot.pageOuts = UInt64(stats.pageouts)
            snapshot.used = snapshot.total > snapshot.free ? snapshot.total - snapshot.free - snapshot.cached / 4 : snapshot.active + snapshot.wired
            if snapshot.used > snapshot.total { snapshot.used = snapshot.total - snapshot.free }
        }

        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        if sysctl(&mib, 2, &usage, &size, nil, 0) == 0 {
            snapshot.swapUsed = UInt64(usage.xsu_used)
            snapshot.swapTotal = UInt64(usage.xsu_total)
        }
        return snapshot
    }

    private func sampleDisks(dt: TimeInterval) -> [DiskSnapshot] {
        var volumes: [String: (name: String, mount: String, total: UInt64, free: UInt64)] = [:]
        if let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey], options: [.skipHiddenVolumes]) {
            for url in mounted {
                let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
                let name = values?.volumeName ?? url.lastPathComponent
                let total = UInt64(values?.volumeTotalCapacity ?? 0)
                let free = UInt64(values?.volumeAvailableCapacity ?? 0)
                volumes[url.path] = (name, url.path, total, free)
            }
        }

        let io = blockIO(dt: dt)
        if volumes.isEmpty {
            return [DiskSnapshot(
                name: "Macintosh HD",
                mount: "/",
                total: io.total,
                free: io.free,
                readBps: io.readBps,
                writeBps: io.writeBps,
                readOps: io.readOps,
                writeOps: io.writeOps,
                responseMS: 0
            )]
        }

        return volumes.values.sorted { $0.mount < $1.mount }.enumerated().map { index, vol in
            DiskSnapshot(
                name: vol.name,
                mount: vol.mount,
                total: vol.total,
                free: vol.free,
                readBps: index == 0 ? io.readBps : 0,
                writeBps: index == 0 ? io.writeBps : 0,
                readOps: index == 0 ? io.readOps : 0,
                writeOps: index == 0 ? io.writeOps : 0,
                responseMS: 0
            )
        }
    }

    private func blockIO(dt: TimeInterval) -> (readBps: Double, writeBps: Double, readOps: Double, writeOps: Double, total: UInt64, free: UInt64) {
        var read: UInt64 = 0
        var write: UInt64 = 0
        var readOps: UInt64 = 0
        var writeOps: UInt64 = 0

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = props?.takeRetainedValue() as? [String: Any],
                   let stats = dict["Statistics"] as? [String: Any] {
                    read += uint64Value(stats["Bytes (Read)"])
                    write += uint64Value(stats["Bytes (Write)"])
                    readOps += uint64Value(stats["Operations (Read)"])
                    writeOps += uint64Value(stats["Operations (Write)"])
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
        }

        let key = "total"
        let prev = lastDisk[key]
        lastDisk[key] = (read, write, readOps, writeOps, ProcessInfo.processInfo.systemUptime)
        var readBps = 0.0
        var writeBps = 0.0
        var readRate = 0.0
        var writeRate = 0.0
        if let prev {
            readBps = max(0, Double(read &- prev.read) / dt)
            writeBps = max(0, Double(write &- prev.write) / dt)
            readRate = max(0, Double(readOps &- prev.readOps) / dt)
            writeRate = max(0, Double(writeOps &- prev.writeOps) / dt)
        }

        var stat = statfs()
        var total: UInt64 = 0
        var free: UInt64 = 0
        if statfs("/", &stat) == 0 {
            total = UInt64(stat.f_blocks) * UInt64(stat.f_bsize)
            free = UInt64(stat.f_bavail) * UInt64(stat.f_bsize)
        }
        return (readBps, writeBps, readRate, writeRate, total, free)
    }

    private func sampleNetwork(dt: TimeInterval) -> [NetworkAdapterSnapshot] {
        var buffer = [TMIfStats](unsafeUninitializedCapacity: 32) { ptr, initialized in
            memset(ptr.baseAddress, 0, 32 * MemoryLayout<TMIfStats>.stride)
            initialized = 32
        }
        let count = Int(tm_copy_ifstats(&buffer, 32))
        let ips = ipv4ByInterface()
        var adapters: [NetworkAdapterSnapshot] = []
        var nextLast: [String: TMIfStats] = [:]

        for i in 0..<count {
            var stats = buffer[i]
            let name = withUnsafeBytes(of: &stats.name) { raw -> String in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            if name.isEmpty || stats.loopback != 0 { continue }
            nextLast[name] = stats
            let prev = lastIfs[name]
            var inBps = 0.0
            var outBps = 0.0
            var inPkt = 0.0
            var outPkt = 0.0
            if let prev {
                inBps = max(0, Double(stats.ibytes &- prev.ibytes) / dt)
                outBps = max(0, Double(stats.obytes &- prev.obytes) / dt)
                inPkt = max(0, Double(stats.ipackets &- prev.ipackets) / dt)
                outPkt = max(0, Double(stats.opackets &- prev.opackets) / dt)
            }
            adapters.append(NetworkAdapterSnapshot(
                name: name,
                displayName: friendlyInterfaceName(name, type: stats.type),
                ipv4: ips[name],
                inBps: inBps,
                outBps: outBps,
                inPackets: inPkt,
                outPackets: outPkt,
                up: stats.up != 0
            ))
        }
        lastIfs = nextLast
        return adapters.sorted { $0.inBps + $0.outBps > $1.inBps + $1.outBps }
    }

    private func sampleGPU() -> GPUSnapshot {
        var snapshot = GPUSnapshot()
        snapshot.name = sysctlString("machdep.cpu.brand_string")?.replacingOccurrences(of: "Apple ", with: "Apple ") ?? "Apple GPU"
        if let brand = sysctlString("machdep.cpu.brand_string") {
            snapshot.name = "\(brand) GPU"
        }

        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator") else { return snapshot }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return snapshot
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                if let model = dict["model"] as? String { snapshot.name = model }
                if let stats = dict["PerformanceStatistics"] as? [String: Any] {
                    snapshot.utilization = max(snapshot.utilization, doubleValue(stats["Device Utilization %"]))
                    snapshot.renderer = max(snapshot.renderer, doubleValue(stats["Renderer Utilization %"]))
                    snapshot.tiler = max(snapshot.tiler, doubleValue(stats["Tiler Utilization %"]))
                    snapshot.allocatedBytes = max(snapshot.allocatedBytes, uint64Value(stats["Alloc system memory"]))
                    snapshot.inUseBytes = max(snapshot.inUseBytes, uint64Value(stats["In use system memory"]))
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return snapshot
    }

    private func ipv4ByInterface() -> [String: String] {
        var result: [String: String] = [:]
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return result }
        defer { freeifaddrs(first) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if let sa = current.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                result[name] = String(cString: buffer)
            }
            ptr = current.pointee.ifa_next
        }
        return result
    }

    private func friendlyInterfaceName(_ name: String, type: UInt32) -> String {
        if name.hasPrefix("en") {
            return name == "en0" ? "Wi-Fi" : "Ethernet (\(name))"
        }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") { return "VPN (\(name))" }
        if name.hasPrefix("awdl") { return "AirDrop" }
        if name.hasPrefix("llw") { return "Low latency WLAN" }
        if name.hasPrefix("bridge") { return "Bridge" }
        return name
    }

    private func sysctlString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private func sysctlInt(_ key: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private func uint64Value(_ value: Any?) -> UInt64 {
        if let n = value as? UInt64 { return n }
        if let n = value as? Int { return UInt64(max(0, n)) }
        if let n = value as? NSNumber { return n.uint64Value }
        return 0
    }

    private func doubleValue(_ value: Any?) -> Double {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let n = value as? NSNumber { return n.doubleValue }
        return 0
    }
}

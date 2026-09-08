import AppKit
import Foundation
import Security

final class ProcessMonitor: @unchecked Sendable {
    private struct Sample {
        var cpuTime: UInt64
        var diskRead: UInt64
        var diskWrite: UInt64
        var wakeups: UInt64
        var timestamp: TimeInterval
    }

    private var previous: [Int32: Sample] = [:]
    private var publisherCache: [String: String] = [:]
    private var history: [String: AppHistoryRow] = [:]
    private let iconCache = NSCache<NSString, NSImage>()

    func snapshot() -> (processes: [LiveProcess], history: [AppHistoryRow]) {
        let now = ProcessInfo.processInfo.systemUptime
        let pids = allPIDs()
        let runningApps = NSWorkspace.shared.runningApplications
        var appsByPID: [Int32: NSRunningApplication] = [:]
        var appsByPath: [String: NSRunningApplication] = [:]
        for app in runningApps {
            appsByPID[app.processIdentifier] = app
            if let url = app.executableURL {
                appsByPath[url.path] = app
            }
            if let bundle = app.bundleURL {
                appsByPath[bundle.path] = app
            }
        }

        var nextPrevious: [Int32: Sample] = [:]
        var processes: [LiveProcess] = []
        processes.reserveCapacity(pids.count)

        for pid in pids {
            guard pid > 0 else { continue }
            var task = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize else {
                continue
            }

            var bsd = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) != bsdSize {
                continue
            }

            let path = processPath(pid)
            let rawName = processName(pid, bsd: bsd)
            let runningApp = appsByPID[pid] ?? appsByPath[path]
            let displayName = runningApp?.localizedName ?? rawName
            let userName = accountName(uid: bsd.pbi_uid)
            let kind = classify(path: path, uid: bsd.pbi_uid, app: runningApp)

            var diskRead: UInt64 = 0
            var diskWrite: UInt64 = 0
            var wakeups: UInt64 = 0
            var physFootprint = task.pti_resident_size
            var rusage = rusage_info_v4()
            let rusageOK = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
                ptr.withMemoryRebound(to: Optional<rusage_info_t>.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, Int32(RUSAGE_INFO_V4), rebound)
                }
            }
            if rusageOK == 0 {
                diskRead = rusage.ri_diskio_bytesread
                diskWrite = rusage.ri_diskio_byteswritten
                wakeups = rusage.ri_interrupt_wkups + rusage.ri_pkg_idle_wkups
                if rusage.ri_phys_footprint > 0 {
                    physFootprint = rusage.ri_phys_footprint
                }
            }

            let cpuTime = task.pti_total_user &+ task.pti_total_system
            let prev = previous[pid]
            let dt = max(now - (prev?.timestamp ?? now), 0.001)
            var cpuPercent = 0.0
            var diskReadBps = 0.0
            var diskWriteBps = 0.0
            var wakeupsPerSec = 0.0
            if let prev {
                let cpuDelta = Double(cpuTime &- prev.cpuTime) / 1_000_000_000.0
                let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
                cpuPercent = max(0, cpuDelta / dt * 100.0 / Double(cores))
                diskReadBps = max(0, Double(diskRead &- prev.diskRead) / dt)
                diskWriteBps = max(0, Double(diskWrite &- prev.diskWrite) / dt)
                wakeupsPerSec = max(0, Double(wakeups &- prev.wakeups) / dt)
            }

            let startDate: Date? = {
                guard bsd.pbi_start_tvsec > 0 else { return nil }
                return Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000)
            }()

            let isNotResponding = runningApp?.isFinishedLaunching == true && hungHint(pid: pid, app: runningApp)

            let process = LiveProcess(
                pid: pid,
                ppid: Int32(bsd.pbi_ppid),
                name: rawName,
                displayName: displayName,
                path: path,
                user: userName,
                uid: bsd.pbi_uid,
                status: ProcessRunStatus(pbiStatus: bsd.pbi_status),
                kind: kind,
                cpuPercent: min(cpuPercent, 100),
                cpuTimeSeconds: Double(cpuTime) / 1_000_000_000.0,
                memoryBytes: physFootprint,
                virtualBytes: task.pti_virtual_size,
                compressedBytes: 0,
                diskReadBps: diskReadBps,
                diskWriteBps: diskWriteBps,
                networkInBps: 0,
                networkOutBps: 0,
                gpuPercent: 0,
                threads: task.pti_threadnum,
                ports: bsd.pbi_nfiles,
                nice: bsd.pbi_nice,
                architecture: architecture(pid: pid, app: runningApp),
                publisher: publisherCache[path] ?? "",
                bundleIdentifier: runningApp?.bundleIdentifier,
                isApplication: runningApp?.activationPolicy == .regular,
                isNotResponding: isNotResponding,
                wakeupsPerSec: wakeupsPerSec,
                startDate: startDate,
                icon: icon(for: path, app: runningApp)
            )
            processes.append(process)

            nextPrevious[pid] = Sample(
                cpuTime: cpuTime,
                diskRead: diskRead,
                diskWrite: diskWrite,
                wakeups: wakeups,
                timestamp: now
            )

            if process.isApplication || process.kind == .app {
                accumulateHistory(process)
            }
        }

        previous = nextPrevious
        return (processes, Array(history.values).sorted { $0.cpuTimeSeconds > $1.cpuTimeSeconds })
    }

    private func allPIDs() -> [Int32] {
        let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }
        let count = Int(bytesNeeded) / MemoryLayout<Int32>.size
        var buffer = [Int32](repeating: 0, count: count)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buffer, Int32(buffer.count * MemoryLayout<Int32>.size))
        guard filled > 0 else { return [] }
        let actual = Int(filled) / MemoryLayout<Int32>.size
        return Array(buffer.prefix(actual)).filter { $0 > 0 }
    }

    private func processPath(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return "" }
        return String(cString: buffer)
    }

    private func processName(_ pid: Int32, bsd: proc_bsdinfo) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            let named = String(cString: buffer)
            if !named.isEmpty { return named }
        }
        return withUnsafeBytes(of: bsd.pbi_name) { raw in
            let ptr = raw.bindMemory(to: CChar.self).baseAddress
            if let ptr, ptr.pointee != 0 {
                return String(cString: ptr)
            }
            return withUnsafeBytes(of: bsd.pbi_comm) { comm in
                let cptr = comm.bindMemory(to: CChar.self).baseAddress
                return cptr.map { String(cString: $0) } ?? "pid \(pid)"
            }
        }
    }

    private func accountName(uid: uid_t) -> String {
        if let pw = getpwuid(uid) {
            return String(cString: pw.pointee.pw_name)
        }
        return String(uid)
    }

    private func classify(path: String, uid: uid_t, app: NSRunningApplication?) -> ProcessKind {
        if app?.activationPolicy == .regular {
            return .app
        }
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/sbin/") || path.hasPrefix("/Library/Apple/") || uid == 0 {
            if app?.activationPolicy == .regular { return .app }
            return .system
        }
        if let bundle = app?.bundleIdentifier, bundle.hasPrefix("com.apple.") {
            return app?.activationPolicy == .regular ? .app : .system
        }
        return .background
    }

    private func architecture(pid: Int32, app: NSRunningApplication?) -> String {
        if let url = app?.bundleURL, let archs = Bundle(url: url)?.executableArchitectures {
            if archs.contains(NSNumber(value: NSBundleExecutableArchitectureARM64)) { return "Arm64" }
            if archs.contains(NSNumber(value: NSBundleExecutableArchitectureX86_64)) { return "x64" }
        }
        var mib = [Int32](repeating: 0, count: Int(CTL_MAXNAME))
        var miblen = size_t(CTL_MAXNAME)
        let name = "sysctl.proc_cputype"
        if sysctlnametomib(name, &mib, &miblen) == 0 {
            var typedMIB = Array(mib.prefix(Int(miblen)))
            typedMIB.append(Int32(pid))
            var cpuType: cpu_type_t = 0
            var len = MemoryLayout<cpu_type_t>.size
            if sysctl(&typedMIB, u_int(typedMIB.count), &cpuType, &len, nil, 0) == 0 {
                if cpuType == CPU_TYPE_ARM64 { return "Arm64" }
                if cpuType == CPU_TYPE_X86_64 { return "x64" }
                if cpuType == CPU_TYPE_ARM { return "Arm" }
            }
        }
        return "Arm64"
    }

    private func icon(for path: String, app: NSRunningApplication?) -> NSImage? {
        if let icon = app?.icon { return icon }
        return nil
    }

    private func hungHint(pid: Int32, app: NSRunningApplication?) -> Bool {
        guard app?.activationPolicy == .regular else { return false }
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size {
            return Int32(bsd.pbi_status) == SSTOP
        }
        return false
    }

    private func accumulateHistory(_ process: LiveProcess) {
        let key = process.bundleIdentifier ?? process.path
        let id = key.isEmpty ? process.name : key
        var row = history[id] ?? AppHistoryRow(
            id: id,
            name: process.displayName,
            publisher: process.publisher,
            cpuTimeSeconds: 0,
            networkBytes: 0,
            peakMemoryBytes: 0,
            icon: process.icon
        )
        row.name = process.displayName
        row.cpuTimeSeconds = max(row.cpuTimeSeconds, process.cpuTimeSeconds)
        row.peakMemoryBytes = max(row.peakMemoryBytes, process.memoryBytes)
        row.networkBytes &+= UInt64(max(0, process.networkInBps + process.networkOutBps))
        if row.publisher.isEmpty { row.publisher = process.publisher }
        if row.icon == nil { row.icon = process.icon }
        history[id] = row
    }

    static func publisher(for path: String) -> String {
        guard !path.isEmpty else { return "Unknown" }
        let url = URL(fileURLWithPath: path) as CFURL
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess, let code = staticCode else {
            return "Unknown"
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else {
            return "Unknown"
        }
        if let ident = dict[kSecCodeInfoIdentifier as String] as? String, ident.hasPrefix("com.apple.") {
            return "Apple Inc."
        }
        if let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate], let first = certs.first {
            if let summary = SecCertificateCopySubjectSummary(first) as String? {
                return summary.replacingOccurrences(of: "Developer ID Application: ", with: "")
            }
        }
        if let ident = dict[kSecCodeInfoIdentifier as String] as? String, !ident.isEmpty {
            return ident
        }
        return "Unknown"
    }
}

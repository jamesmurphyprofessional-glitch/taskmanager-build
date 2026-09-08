import Foundation
import SystemConfiguration

enum UserMonitor {
    static func users(from processes: [LiveProcess]) -> [SessionUser] {
        var grouped: [uid_t: [LiveProcess]] = [:]
        for process in processes {
            grouped[process.uid, default: []].append(process)
        }
        let console = consoleUID()
        return grouped.keys.sorted().map { uid in
            let rows = grouped[uid] ?? []
            let name = rows.first?.user ?? String(uid)
            return SessionUser(
                uid: uid,
                name: name,
                fullName: fullName(uid: uid) ?? name,
                isConsole: uid == console,
                processCount: rows.count,
                cpuPercent: rows.reduce(0) { $0 + $1.cpuPercent },
                memoryBytes: rows.reduce(0) { $0 + $1.memoryBytes }
            )
        }.sorted { lhs, rhs in
            if lhs.isConsole != rhs.isConsole { return lhs.isConsole }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func consoleUID() -> uid_t {
        var uid = getuid()
        if let store = SCDynamicStoreCreate(nil, "TaskManager" as CFString, nil, nil) {
            _ = SCDynamicStoreCopyConsoleUser(store, &uid, nil)
        }
        return uid
    }

    private static func fullName(uid: uid_t) -> String? {
        guard let pw = getpwuid(uid) else { return nil }
        let gecos = String(cString: pw.pointee.pw_gecos)
        return gecos.split(separator: ",").first.map(String.init)
    }
}

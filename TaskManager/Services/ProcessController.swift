import AppKit
import Foundation

enum ProcessActionError: LocalizedError {
    case protected
    case notFound
    case permissionDenied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .protected:
            return "This process is required by macOS and cannot be ended."
        case .notFound:
            return "The process is no longer running."
        case .permissionDenied:
            return "macOS denied the signal. End only your own processes, or run Task Manager with administrator privileges for system tasks."
        case .failed(let message):
            return message
        }
    }
}

enum ProcessController {
    static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "opendirectoryd"
    ]

    static func endTask(_ process: LiveProcess, force: Bool) throws {
        try endPIDs([process.pid], name: process.name, force: force)
    }

    static func endTree(root: LiveProcess, all: [LiveProcess], force: Bool) throws {
        let children = descendants(of: root.pid, in: all)
        var pids = children.map(\.pid)
        pids.append(root.pid)
        try endPIDs(pids, name: root.name, force: force)
    }

    static func setNice(_ process: LiveProcess, value: Int32) throws {
        try guardKillable(process.pid, name: process.name)
        errno = 0
        if setpriority(PRIO_PROCESS, id_t(process.pid), value) != 0 {
            throw mapErrno()
        }
    }

    static func setEfficiencyMode(_ process: LiveProcess, enabled: Bool) throws {
        try setNice(process, value: enabled ? 10 : 0)
    }

    static func openLocation(_ process: LiveProcess) throws {
        let path = process.path
        guard !path.isEmpty else {
            throw ProcessActionError.failed("No executable path is available for this process.")
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func searchOnline(_ process: LiveProcess) {
        let query = process.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? process.name
        if let url = URL(string: "https://www.google.com/search?q=\(query)%20macos%20process") {
            NSWorkspace.shared.open(url)
        }
    }

    static func runNewTask(command: String, asAdmin: Bool) throws {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProcessActionError.failed("Enter an app name, path, or command.")
        }

        let fileURL = URL(fileURLWithPath: trimmed)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if asAdmin {
                try runShell("open -a \(shellEscape(fileURL.path))", asAdmin: true)
                return
            }
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: fileURL, configuration: config) { _, error in
                if error != nil {
                    NSWorkspace.shared.open(fileURL)
                }
            }
            return
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed)
            ?? NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: "/Applications/\(trimmed).app")) {
            if asAdmin {
                try runShell("open -a \(shellEscape(appURL.path))", asAdmin: true)
            } else {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
            return
        }

        try runShell(trimmed, asAdmin: asAdmin)
    }

    private static func endPIDs(_ pids: [Int32], name: String, force: Bool) throws {
        var lastError: ProcessActionError?
        for pid in pids {
            do {
                try guardKillable(pid, name: name)
                if let app = NSRunningApplication(processIdentifier: pid), !force {
                    if !app.terminate() {
                        _ = app.forceTerminate()
                    }
                    continue
                }
                if let app = NSRunningApplication(processIdentifier: pid), force {
                    _ = app.forceTerminate()
                    continue
                }
                let sig = force ? SIGKILL : SIGTERM
                if kill(pid, sig) != 0 {
                    throw mapErrno()
                }
            } catch let error as ProcessActionError {
                lastError = error
            }
        }
        if let lastError {
            throw lastError
        }
    }

    private static func guardKillable(_ pid: Int32, name: String) throws {
        if pid <= 1 || protectedNames.contains(name) {
            throw ProcessActionError.protected
        }
        if kill(pid, 0) != 0 && errno == ESRCH {
            throw ProcessActionError.notFound
        }
    }

    private static func descendants(of root: Int32, in all: [LiveProcess]) -> [LiveProcess] {
        var byParent: [Int32: [LiveProcess]] = [:]
        for process in all {
            byParent[process.ppid, default: []].append(process)
        }
        var result: [LiveProcess] = []
        var stack = byParent[root] ?? []
        while let next = stack.popLast() {
            result.append(next)
            stack.append(contentsOf: byParent[next.pid] ?? [])
        }
        return result
    }

    private static func mapErrno() -> ProcessActionError {
        switch errno {
        case EPERM, EACCES:
            return .permissionDenied
        case ESRCH:
            return .notFound
        default:
            return .failed(String(cString: strerror(errno)))
        }
    }

    private static func runShell(_ command: String, asAdmin: Bool) throws {
        if asAdmin {
            let script = "do shell script \(appleScriptString(command)) with administrator privileges"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try process.run()
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        try process.run()
    }

    private static func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

import Foundation

final class ServiceMonitor: @unchecked Sendable {
    func list() -> [LaunchService] {
        guard let output = shell("/bin/launchctl", ["list"]) else { return [] }
        var seen = Set<String>()
        var rows: [LaunchService] = []
        for line in output.components(separatedBy: .newlines).dropFirst() {
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init).filter { !$0.isEmpty }
            guard parts.count >= 3 else { continue }
            let pid = Int32(parts[0])
            let status = Int32(parts[1]) ?? 0
            let label = parts[2]
            if !seen.insert(label).inserted { continue }
            let domain = label.hasPrefix("com.apple.") ? "system" : "gui/\(getuid())"
            rows.append(LaunchService(
                label: label,
                pid: pid,
                statusCode: status,
                running: pid != nil,
                domain: domain,
                plistPath: nil,
                program: nil,
                descriptionText: nil
            ))
        }
        return rows.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    func start(_ service: LaunchService) throws {
        try runLaunchctl(["kickstart", "-k", "\(service.domain)/\(service.label)"])
    }

    func stop(_ service: LaunchService) throws {
        try runLaunchctl(["bootout", "\(service.domain)/\(service.label)"])
    }

    func restart(_ service: LaunchService) throws {
        if service.running {
            try stop(service)
        }
        try start(service)
    }

    private func runLaunchctl(_ args: [String]) throws {
        guard let result = shell("/bin/launchctl", args) else {
            throw ProcessActionError.failed("launchctl did not respond.")
        }
        if result.hasPrefix("ERROR:") {
            throw ProcessActionError.failed(result)
        }
    }

    private func shell(_ path: String, _ args: [String]) -> String? {
        ProcessRunner.run(path, args, timeout: 4)
    }
}

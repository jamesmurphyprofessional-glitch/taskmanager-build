import AppKit
import Foundation

final class StartupMonitor: @unchecked Sendable {
    func list() -> [StartupEntry] {
        var items: [StartupEntry] = []
        items.append(contentsOf: launchJobs(
            in: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"),
            kind: .launchAgent
        ))
        items.append(contentsOf: launchJobs(in: URL(fileURLWithPath: "/Library/LaunchAgents"), kind: .launchAgent))
        items.append(contentsOf: launchJobs(in: URL(fileURLWithPath: "/Library/LaunchDaemons"), kind: .launchDaemon))
        items.append(contentsOf: loginItems())
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func setEnabled(_ entry: StartupEntry, enabled: Bool) throws {
        switch entry.kind {
        case .loginItem:
            try toggleLoginItem(name: entry.name, path: entry.path, enabled: enabled)
        case .launchAgent, .launchDaemon:
            guard let label = entry.label, !label.isEmpty else {
                throw ProcessActionError.failed("This item has no launchd label.")
            }
            let domain = entry.kind == .launchDaemon ? "system" : "gui/\(getuid())"
            _ = ProcessRunner.run("/bin/launchctl", [enabled ? "enable" : "disable", "\(domain)/\(label)"], timeout: 4)
        }
    }

    func open(_ entry: StartupEntry) {
        let url = URL(fileURLWithPath: entry.path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func loginItems() -> [StartupEntry] {
        let script = """
        tell application "System Events"
            set output to ""
            repeat with itm in login items
                set output to output & name of itm & tab & path of itm & linefeed
            end repeat
            return output
        end tell
        """
        guard let text = ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 2) else { return [] }
        return text.split(separator: "\n").compactMap { line -> StartupEntry? in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return StartupEntry(
                id: "login:\(parts[1])",
                name: parts[0],
                kind: .loginItem,
                enabled: true,
                path: parts[1],
                publisher: "",
                impact: "Not measured",
                label: nil
            )
        }
    }

    private func launchJobs(in directory: URL, kind: StartupEntry.Kind) -> [StartupEntry] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "plist" }.compactMap { url -> StartupEntry? in
            guard let plist = NSDictionary(contentsOf: url) else { return nil }
            let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
            let runAtLoad = plist["RunAtLoad"] as? Bool ?? false
            let keepAlive: Bool = {
                if let flag = plist["KeepAlive"] as? Bool { return flag }
                if let dict = plist["KeepAlive"] as? [String: Any] { return !dict.isEmpty }
                return false
            }()
            guard runAtLoad || keepAlive || kind == .launchDaemon else { return nil }
            let program = (plist["Program"] as? String)
                ?? (plist["ProgramArguments"] as? [String])?.first
                ?? url.path
            return StartupEntry(
                id: "\(kind.rawValue):\(label)",
                name: label,
                kind: kind,
                enabled: runAtLoad || keepAlive,
                path: program,
                publisher: "",
                impact: keepAlive ? "High" : "Medium",
                label: label
            )
        }
    }

    private func toggleLoginItem(name: String, path: String, enabled: Bool) throws {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script: String
        if enabled {
            script = "tell application \"System Events\" to make login item at end with properties {path:\"\(escapedPath)\", hidden:false}"
        } else {
            script = "tell application \"System Events\" to delete login item \"\(escapedName)\""
        }
        if ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 4) == nil {
            throw ProcessActionError.failed("Could not update Login Items. Allow Automation for Task Manager in System Settings → Privacy & Security → Automation.")
        }
    }
}

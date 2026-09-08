import Foundation

enum Formatters {
    static func percent(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(value)
        var unit = 0
        while size >= 1024 && unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        if unit == 0 {
            return "\(value) B"
        }
        let digits = size >= 100 || unit <= 1 ? 0 : 1
        return String(format: "%.\(digits)f %@", size, units[unit])
    }

    static func mb(_ value: Double) -> String {
        if value < 0.1 { return "0.1 MB" }
        if value < 10 { return String(format: "%.1f MB", value) }
        return String(format: "%.0f MB", value)
    }

    static func mbps(_ bytesPerSecond: Double) -> String {
        let mb = bytesPerSecond / 1_048_576.0
        if abs(mb) < 0.05 { return "0 MB/s" }
        if abs(mb) < 10 { return String(format: "%.1f MB/s", mb) }
        return String(format: "%.0f MB/s", mb)
    }

    static func bitsPerSec(_ bytesPerSecond: Double) -> String {
        let bits = bytesPerSecond * 8
        if bits < 1000 { return String(format: "%.0f bps", bits) }
        if bits < 1_000_000 { return String(format: "%.1f Kbps", bits / 1000) }
        if bits < 1_000_000_000 { return String(format: "%.1f Mbps", bits / 1_000_000) }
        return String(format: "%.2f Gbps", bits / 1_000_000_000)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func cpuTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let frac = Int((seconds - Double(total)) * 1000)
        if h > 0 { return String(format: "%d:%02d:%02d.%03d", h, m, s, frac) }
        return String(format: "%d:%02d.%03d", m, s, frac)
    }
}

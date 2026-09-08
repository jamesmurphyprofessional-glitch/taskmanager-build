import SwiftUI

enum TM {
    static let bg = Color(red: 0.125, green: 0.125, blue: 0.125)
    static let sidebar = Color(red: 0.153, green: 0.153, blue: 0.153)
    static let panel = Color(red: 0.169, green: 0.169, blue: 0.169)
    static let raised = Color(red: 0.204, green: 0.204, blue: 0.204)
    static let stroke = Color(red: 0.275, green: 0.275, blue: 0.275)
    static let text = Color(red: 0.95, green: 0.95, blue: 0.95)
    static let muted = Color(red: 0.67, green: 0.67, blue: 0.67)
    static let accent = Color(red: 0.376, green: 0.807, blue: 1.0)
    static let cpu = Color(red: 0.07, green: 0.60, blue: 0.37)
    static let memory = Color(red: 0.55, green: 0.36, blue: 0.80)
    static let disk = Color(red: 0.20, green: 0.55, blue: 0.86)
    static let network = Color(red: 0.86, green: 0.55, blue: 0.16)
    static let gpu = Color(red: 0.86, green: 0.29, blue: 0.29)
    static let danger = Color(red: 0.91, green: 0.30, blue: 0.24)
    static let row = Color(red: 0.145, green: 0.145, blue: 0.145)

    static func heat(value: Double, mid: Double, high: Double) -> Color {
        if value >= high { return Color(red: 0.72, green: 0.18, blue: 0.14).opacity(0.85) }
        if value >= mid { return Color(red: 0.72, green: 0.48, blue: 0.10).opacity(0.70) }
        if value > 0.05 { return Color(red: 0.10, green: 0.42, blue: 0.28).opacity(0.55) }
        return Color.clear
    }
}

enum HeatScale {
    static func cpu(_ value: Double) -> Color { TM.heat(value: value, mid: 10, high: 40) }
    static func memory(_ mb: Double, totalMB: Double) -> Color {
        let pct = totalMB > 0 ? mb / totalMB * 100 : 0
        return TM.heat(value: pct, mid: 4, high: 12)
    }
    static func disk(_ mbps: Double) -> Color { TM.heat(value: mbps, mid: 2, high: 20) }
    static func network(_ mbps: Double) -> Color { TM.heat(value: mbps, mid: 1, high: 10) }
    static func gpu(_ value: Double) -> Color { TM.heat(value: value, mid: 15, high: 50) }
}

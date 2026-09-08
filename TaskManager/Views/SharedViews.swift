import SwiftUI

struct HeatCell: View {
    let text: String
    let color: Color
    var mono: Bool = true

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: mono ? .monospaced : .default))
            .foregroundStyle(TM.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.horizontal, 8)
            .background(color)
    }
}

struct Sparkline: View {
    let values: [Double]
    var maxValue: Double? = 100
    var color: Color = TM.accent
    var fill = true

    var body: some View {
        GeometryReader { geo in
            let maxY = max(maxValue ?? (values.max() ?? 1), 0.001)
            let pts = points(in: geo.size, maxY: maxY)
            ZStack {
                if fill, pts.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: pts.first?.x ?? 0, y: geo.size.height))
                        for p in pts { path.addLine(to: p) }
                        path.addLine(to: CGPoint(x: pts.last?.x ?? geo.size.width, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(color.opacity(0.22))
                }
                Path { path in
                    guard let first = pts.first else { return }
                    path.move(to: first)
                    for p in pts.dropFirst() { path.addLine(to: p) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
        }
    }

    private func points(in size: CGSize, maxY: Double) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let last = Array(values.suffix(PerformanceHistory.capacity))
        let step = last.count > 1 ? size.width / CGFloat(last.count - 1) : 0
        return last.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - CGFloat(min(max(value, 0) / maxY, 1)) * size.height
            )
        }
    }
}

struct DualSparkline: View {
    let first: [Double]
    let second: [Double]
    var firstColor: Color
    var secondColor: Color

    var body: some View {
        let peak = max(first.max() ?? 0, second.max() ?? 0, 0.1)
        ZStack {
            Sparkline(values: first, maxValue: peak, color: firstColor, fill: true)
            Sparkline(values: second, maxValue: peak, color: secondColor, fill: false)
        }
    }
}

struct MetricChip: View {
    let title: String
    let value: String
    var color: Color = TM.muted

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(TM.muted)
            Text(value)
                .foregroundStyle(TM.text)
                .fontWeight(.semibold)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}

struct ProcessNameCell: View {
    let process: LiveProcess
    var indent: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            if indent > 0 { Color.clear.frame(width: indent) }
            if let icon = process.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: process.isApplication ? "app.fill" : "gearshape.fill")
                    .foregroundStyle(TM.muted)
                    .frame(width: 16)
            }
            Text(process.displayName)
                .lineLimit(1)
            if process.isNotResponding {
                Text("Not responding")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TM.danger)
            }
        }
    }
}

struct ConfirmEndSheet: View {
    let names: [String]
    let force: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(force ? "Force quit this process?" : "End task?")
                .font(.title3.weight(.semibold))
            Text(force
                 ? "Force quit immediately stops \(names.joined(separator: ", ")). Unsaved work will be lost."
                 : "This will ask \(names.joined(separator: ", ")) to close. Unsaved work may be lost.")
                .foregroundStyle(TM.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(force ? "Force quit" : "End task", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .tint(TM.danger)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

struct RunTaskSheet: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create new task")
                .font(.title3.weight(.semibold))
            Text("Type the name of a program, folder, document, or command. This is the macOS equivalent of Run.")
                .font(.callout)
                .foregroundStyle(TM.muted)
            TextField("Open", text: $state.runCommand)
                .textFieldStyle(.roundedBorder)
                .onSubmit { state.runNewTask() }
            Toggle("Create this task with administrative privileges", isOn: $state.runAsAdmin)
            HStack {
                Spacer()
                Button("Cancel") { state.showRunDialog = false }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { state.runNewTask() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.runCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}

struct PropertiesSheet: View {
    let process: LiveProcess
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let icon = process.icon {
                    Image(nsImage: icon).resizable().frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(process.displayName).font(.title3.weight(.semibold))
                    Text(process.path.isEmpty ? process.name : process.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(TM.muted)
                        .textSelection(.enabled)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                row("PID", "\(process.pid)")
                row("Parent PID", "\(process.ppid)")
                row("User", process.user)
                row("Status", process.statusLabel)
                row("CPU", Formatters.percent(process.cpuPercent))
                row("CPU time", Formatters.cpuTime(process.cpuTimeSeconds))
                row("Memory", Formatters.bytes(process.memoryBytes))
                row("Virtual memory", Formatters.bytes(process.virtualBytes))
                row("Disk", Formatters.mbps(process.diskReadBps + process.diskWriteBps))
                row("Threads", "\(process.threads)")
                row("Open files / ports", "\(process.ports)")
                row("Priority (nice)", "\(process.nice)")
                row("Architecture", process.architecture)
                row("Publisher", process.publisher.isEmpty ? ProcessMonitor.publisher(for: process.path) : process.publisher)
                if let start = process.startDate {
                    row("Started", start.formatted(date: .abbreviated, time: .standard))
                }
                if let bundle = process.bundleIdentifier {
                    row("Bundle ID", bundle)
                }
            }
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(TM.muted)
            Text(value).textSelection(.enabled)
        }
    }
}

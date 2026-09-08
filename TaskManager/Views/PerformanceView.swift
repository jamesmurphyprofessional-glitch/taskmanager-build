import SwiftUI

struct PerformanceView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HSplitView {
            paneList
                .frame(minWidth: 210, idealWidth: 230, maxWidth: 280)
            detail
                .frame(minWidth: 520)
        }
        .background(TM.bg)
    }

    private var paneList: some View {
        ScrollView {
            VStack(spacing: 6) {
                paneButton(.cpu, title: "CPU", value: Formatters.percent(state.cpu.overall, digits: 0), color: TM.cpu) {
                    Sparkline(values: state.historySeries.cpu, color: TM.cpu)
                }
                paneButton(.memory, title: "Memory", value: Formatters.percent(state.memory.usedPercent, digits: 0), color: TM.memory) {
                    Sparkline(values: state.historySeries.memory, color: TM.memory)
                }
                paneButton(.disk, title: state.disks.first?.name ?? "Disk", value: Formatters.mbps(state.statusDisk), color: TM.disk) {
                    DualSparkline(first: state.historySeries.diskRead, second: state.historySeries.diskWrite, firstColor: TM.disk, secondColor: TM.accent)
                }
                paneButton(.network, title: primaryNetwork?.displayName ?? "Ethernet", value: Formatters.mbps(state.statusNetwork), color: TM.network) {
                    DualSparkline(first: state.historySeries.netIn, second: state.historySeries.netOut, firstColor: TM.network, secondColor: TM.accent)
                }
                paneButton(.gpu, title: "GPU", value: Formatters.percent(state.gpu.utilization, digits: 0), color: TM.gpu) {
                    Sparkline(values: state.historySeries.gpu, color: TM.gpu)
                }
            }
            .padding(10)
        }
        .background(TM.sidebar)
    }

    private func paneButton<Graph: View>(_ pane: PerformancePane, title: String, value: String, color: Color, @ViewBuilder graph: () -> Graph) -> some View {
        Button {
            state.performancePane = pane
        } label: {
            HStack(spacing: 8) {
                graph()
                    .frame(width: 72, height: 40)
                    .background(TM.bg)
                    .overlay(Rectangle().stroke(color.opacity(0.7), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(TM.muted)
                }
                Spacer()
            }
            .padding(8)
            .background(state.performancePane == pane ? TM.raised : Color.clear)
            .overlay(
                Rectangle()
                    .fill(state.performancePane == pane ? color : Color.clear)
                    .frame(width: 3),
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(TM.text)
    }

    @ViewBuilder
    private var detail: some View {
        switch state.performancePane {
        case .cpu: cpuDetail
        case .memory: memoryDetail
        case .disk: diskDetail
        case .network: networkDetail
        case .gpu: gpuDetail
        }
    }

    private var cpuDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("CPU", subtitle: state.cpu.brand, color: TM.cpu)
            if state.showLogicalProcessors {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(4, max(1, state.cpu.perCore.count)))
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(state.cpu.perCore.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CPU \(index)")
                                .font(.system(size: 10))
                                .foregroundStyle(TM.muted)
                            Sparkline(values: index < state.historySeries.perCore.count ? state.historySeries.perCore[index] : [], color: TM.cpu)
                                .frame(height: 58)
                                .background(TM.bg)
                                .overlay(Rectangle().stroke(TM.cpu.opacity(0.6), lineWidth: 1))
                        }
                    }
                }
            } else {
                Sparkline(values: state.historySeries.cpu, color: TM.cpu)
                    .frame(height: 220)
                    .background(TM.bg)
                    .overlay(Rectangle().stroke(TM.cpu.opacity(0.7), lineWidth: 1))
            }
            Toggle("% Utilization / Logical processors", isOn: $state.showLogicalProcessors)
                .toggleStyle(.switch)
            HStack(alignment: .top, spacing: 28) {
                statColumn([
                    ("Utilization", Formatters.percent(state.cpu.overall)),
                    ("User", Formatters.percent(state.cpu.user)),
                    ("System", Formatters.percent(state.cpu.system)),
                    ("Idle", Formatters.percent(state.cpu.idle))
                ])
                statColumn([
                    ("Processes", "\(state.cpu.processCount)"),
                    ("Threads", "\(state.cpu.threadCount)"),
                    ("Handles", "\(state.cpu.handleCount)"),
                    ("Uptime", Formatters.duration(state.cpu.uptime))
                ])
                statColumn([
                    ("Logical processors", "\(state.cpu.logicalCores)"),
                    ("Performance cores", "\(state.cpu.pCores)"),
                    ("Efficiency cores", "\(state.cpu.eCores)"),
                    ("Thermal", state.cpu.thermalState)
                ])
            }
            Spacer()
        }
        .padding(18)
    }

    private var memoryDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Memory", subtitle: "\(Formatters.bytes(state.memory.total)) RAM", color: TM.memory)
            Sparkline(values: state.historySeries.memory, color: TM.memory)
                .frame(height: 220)
                .background(TM.bg)
                .overlay(Rectangle().stroke(TM.memory.opacity(0.7), lineWidth: 1))
            memoryComposition
            HStack(alignment: .top, spacing: 28) {
                statColumn([
                    ("In use", Formatters.bytes(state.memory.used)),
                    ("Available", Formatters.bytes(state.memory.free + state.memory.cached)),
                    ("Committed", Formatters.percent(state.memory.usedPercent)),
                    ("Cached", Formatters.bytes(state.memory.cached))
                ])
                statColumn([
                    ("Wired", Formatters.bytes(state.memory.wired)),
                    ("App memory", Formatters.bytes(state.memory.appMemory)),
                    ("Compressed", Formatters.bytes(state.memory.compressed)),
                    ("Swap used", Formatters.bytes(state.memory.swapUsed))
                ])
                statColumn([
                    ("Paged in", "\(state.memory.pageIns)"),
                    ("Paged out", "\(state.memory.pageOuts)"),
                    ("Swap total", Formatters.bytes(state.memory.swapTotal)),
                    ("Speed", "LPDDR")
                ])
            }
            Spacer()
        }
        .padding(18)
    }

    private var memoryComposition: some View {
        GeometryReader { geo in
            let total = max(Double(state.memory.total), 1)
            HStack(spacing: 1) {
                Rectangle().fill(TM.memory).frame(width: geo.size.width * Double(state.memory.appMemory) / total)
                Rectangle().fill(TM.memory.opacity(0.65)).frame(width: geo.size.width * Double(state.memory.wired) / total)
                Rectangle().fill(TM.accent.opacity(0.7)).frame(width: geo.size.width * Double(state.memory.compressed) / total)
                Rectangle().fill(TM.raised)
            }
        }
        .frame(height: 28)
        .overlay(Rectangle().stroke(TM.stroke, lineWidth: 1))
    }

    private var diskDetail: some View {
        let disk = state.disks.first
        return VStack(alignment: .leading, spacing: 12) {
            header(disk?.name ?? "Disk", subtitle: disk.map { "\($0.mount)  \(Formatters.bytes($0.total))" } ?? "", color: TM.disk)
            DualSparkline(first: state.historySeries.diskRead, second: state.historySeries.diskWrite, firstColor: TM.disk, secondColor: TM.accent)
                .frame(height: 220)
                .background(TM.bg)
                .overlay(Rectangle().stroke(TM.disk.opacity(0.7), lineWidth: 1))
            HStack(alignment: .top, spacing: 28) {
                statColumn([
                    ("Active time", Formatters.mbps((disk?.readBps ?? 0) + (disk?.writeBps ?? 0))),
                    ("Read speed", Formatters.mbps(disk?.readBps ?? 0)),
                    ("Write speed", Formatters.mbps(disk?.writeBps ?? 0)),
                    ("Read IOPS", String(format: "%.0f", disk?.readOps ?? 0))
                ])
                statColumn([
                    ("Capacity", Formatters.bytes(disk?.total ?? 0)),
                    ("Used", Formatters.bytes(disk?.used ?? 0)),
                    ("Free", Formatters.bytes(disk?.free ?? 0)),
                    ("Write IOPS", String(format: "%.0f", disk?.writeOps ?? 0))
                ])
            }
            if state.disks.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Volumes").foregroundStyle(TM.muted).font(.caption)
                    ForEach(state.disks) { item in
                        HStack {
                            Text(item.name)
                            Text(item.mount).foregroundStyle(TM.muted)
                            Spacer()
                            Text("\(Formatters.bytes(item.used)) / \(Formatters.bytes(item.total))")
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(18)
    }

    private var networkDetail: some View {
        let adapter = primaryNetwork
        return VStack(alignment: .leading, spacing: 12) {
            header(adapter?.displayName ?? "Network", subtitle: adapter?.ipv4.map { "IPv4 \($0)" } ?? adapter?.name ?? "", color: TM.network)
            DualSparkline(first: state.historySeries.netIn, second: state.historySeries.netOut, firstColor: TM.network, secondColor: TM.accent)
                .frame(height: 220)
                .background(TM.bg)
                .overlay(Rectangle().stroke(TM.network.opacity(0.7), lineWidth: 1))
            HStack(alignment: .top, spacing: 28) {
                statColumn([
                    ("Send", Formatters.bitsPerSec(adapter?.outBps ?? 0)),
                    ("Receive", Formatters.bitsPerSec(adapter?.inBps ?? 0)),
                    ("Send packets", String(format: "%.0f/s", adapter?.outPackets ?? 0)),
                    ("Receive packets", String(format: "%.0f/s", adapter?.inPackets ?? 0))
                ])
                VStack(alignment: .leading, spacing: 6) {
                    Text("Adapters").font(.caption).foregroundStyle(TM.muted)
                    ForEach(state.networks.filter(\.up)) { item in
                        HStack {
                            Circle().fill(item.id == adapter?.id ? TM.network : TM.muted).frame(width: 6, height: 6)
                            Text(item.displayName)
                            Spacer()
                            Text(item.ipv4 ?? item.name).foregroundStyle(TM.muted)
                        }
                        .font(.system(size: 12))
                    }
                }
            }
            Spacer()
        }
        .padding(18)
    }

    private var gpuDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("GPU", subtitle: state.gpu.name, color: TM.gpu)
            Sparkline(values: state.historySeries.gpu, color: TM.gpu)
                .frame(height: 220)
                .background(TM.bg)
                .overlay(Rectangle().stroke(TM.gpu.opacity(0.7), lineWidth: 1))
            HStack(alignment: .top, spacing: 28) {
                statColumn([
                    ("Utilization", Formatters.percent(state.gpu.utilization)),
                    ("Renderer", Formatters.percent(state.gpu.renderer)),
                    ("Tiler", Formatters.percent(state.gpu.tiler))
                ])
                statColumn([
                    ("Dedicated memory in use", Formatters.bytes(state.gpu.inUseBytes)),
                    ("Shared memory allocated", Formatters.bytes(state.gpu.allocatedBytes)),
                    ("Hardware-accelerated GPU", "Yes")
                ])
            }
            Spacer()
        }
        .padding(18)
    }

    private var primaryNetwork: NetworkAdapterSnapshot? {
        state.networks.first(where: { $0.up && ($0.name.hasPrefix("en") || $0.ipv4 != nil) }) ?? state.networks.first
    }

    private func header(_ title: String, subtitle: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 28, weight: .semibold))
            Text(subtitle).foregroundStyle(TM.muted)
            Spacer()
            Text("% Utilization over 60 seconds")
                .font(.caption)
                .foregroundStyle(color)
        }
    }

    private func statColumn(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.0).font(.caption).foregroundStyle(TM.muted)
                    Text(row.1).font(.system(size: 16, weight: .medium, design: .monospaced))
                }
            }
        }
    }
}

import AppKit
import SwiftUI

struct ProcessesView: View {
    @EnvironmentObject private var state: AppState
    @State private var sort = ProcessColumn.cpu
    @State private var ascending = false
    @State private var expanded: Set<ProcessKind> = Set(ProcessKind.allCases)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(TM.stroke)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedGroups) { group in
                        groupHeader(group)
                        if expanded.contains(group.kind) {
                            ForEach(sorted(group.processes)) { process in
                                processRow(process, indent: 18)
                            }
                        }
                    }
                }
            }
            .background(TM.row)
        }
        .background(TM.bg)
    }

    private var sortedGroups: [ProcessGroup] {
        state.processGroups
    }

    private var header: some View {
        HStack(spacing: 0) {
            headerButton("Name", column: .name, alignment: .leading)
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
            headerButton("Status", column: .status).frame(width: 110)
            headerButton("CPU", column: .cpu).frame(width: 78)
            headerButton("Memory", column: .memory).frame(width: 90)
            headerButton("Disk", column: .disk).frame(width: 88)
            headerButton("Network", column: .network).frame(width: 88)
            headerButton("GPU", column: .gpu).frame(width: 64)
            headerButton("PID", column: .pid).frame(width: 64)
            headerButton("User", column: .user).frame(width: 92)
            headerButton("Power", column: .power).frame(width: 92)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(TM.muted)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(TM.panel)
    }

    private func headerButton(_ title: String, column: ProcessColumn, alignment: Alignment = .trailing) -> some View {
        Button {
            if sort == column {
                ascending.toggle()
            } else {
                sort = column
                ascending = column == .name || column == .user || column == .status
            }
        } label: {
            HStack(spacing: 4) {
                if alignment == .trailing { Spacer() }
                Text(title)
                if sort == column {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                if alignment == .leading { Spacer() }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func groupHeader(_ group: ProcessGroup) -> some View {
        Button {
            if expanded.contains(group.kind) {
                expanded.remove(group.kind)
            } else {
                expanded.insert(group.kind)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: expanded.contains(group.kind) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 12)
                Text("\(group.kind.rawValue) (\(group.processes.count))")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(Formatters.percent(group.cpuPercent)).frame(width: 78, alignment: .trailing)
                Text(Formatters.bytes(group.memoryBytes)).frame(width: 90, alignment: .trailing)
                Text(Formatters.mbps(group.diskMBps * 1_048_576)).frame(width: 88, alignment: .trailing)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(TM.text)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(TM.panel)
        }
        .buttonStyle(.plain)
    }

    private func processRow(_ process: LiveProcess, indent: CGFloat) -> some View {
        let selected = state.selectedPIDs.contains(process.pid)
        let totalMB = Double(state.memory.total) / 1_048_576.0
        return Button {
            if NSEvent.modifierFlags.contains(.command) {
                if selected { state.selectedPIDs.remove(process.pid) }
                else { state.selectedPIDs.insert(process.pid) }
            } else {
                state.selectedPIDs = [process.pid]
            }
        } label: {
            HStack(spacing: 0) {
                ProcessNameCell(process: process, indent: indent)
                    .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
                Text(process.statusLabel)
                    .foregroundStyle(process.isNotResponding ? TM.danger : TM.muted)
                    .frame(width: 110, alignment: .trailing)
                HeatCell(text: Formatters.percent(process.cpuPercent), color: HeatScale.cpu(process.cpuPercent))
                    .frame(width: 78)
                HeatCell(text: Formatters.mb(process.memoryMB), color: HeatScale.memory(process.memoryMB, totalMB: totalMB))
                    .frame(width: 90)
                HeatCell(text: Formatters.mbps(process.diskReadBps + process.diskWriteBps), color: HeatScale.disk(process.diskMBps))
                    .frame(width: 88)
                HeatCell(text: process.networkMBps == 0 ? "0 MB/s" : Formatters.mbps(process.networkInBps + process.networkOutBps), color: HeatScale.network(process.networkMBps))
                    .frame(width: 88)
                HeatCell(text: Formatters.percent(process.gpuPercent, digits: 0), color: HeatScale.gpu(process.gpuPercent))
                    .frame(width: 64)
                Text("\(process.pid)")
                    .frame(width: 64, alignment: .trailing)
                Text(process.user)
                    .lineLimit(1)
                    .frame(width: 92, alignment: .trailing)
                Text(process.powerUsage.rawValue)
                    .foregroundStyle(process.powerUsage == .high ? TM.danger : TM.muted)
                    .frame(width: 92, alignment: .trailing)
            }
            .font(.system(size: 11))
            .foregroundStyle(TM.text)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(selected ? TM.accent.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { processMenu(process) }
        .onTapGesture(count: 2) {
            state.selectedPIDs = [process.pid]
            state.showProperties = true
        }
    }

    @ViewBuilder
    private func processMenu(_ process: LiveProcess) -> some View {
        Button("End task") {
            state.selectedPIDs = [process.pid]
            state.endSelected(force: false)
        }
        Button("End process tree") {
            state.selectedPIDs = [process.pid]
            state.endTree(force: false)
        }
        Button("Force quit") {
            state.selectedPIDs = [process.pid]
            state.endSelected(force: true)
        }
        Divider()
        Button(process.nice >= 10 ? "Leave efficiency mode" : "Efficiency mode") {
            state.selectedPIDs = [process.pid]
            state.setEfficiency(process.nice < 10)
        }
        Menu("Set priority") {
            Button("Realtime (nice -20)") { state.selectedPIDs = [process.pid]; state.setPriority(-20) }
            Button("High (nice -10)") { state.selectedPIDs = [process.pid]; state.setPriority(-10) }
            Button("Normal (nice 0)") { state.selectedPIDs = [process.pid]; state.setPriority(0) }
            Button("Low (nice 10)") { state.selectedPIDs = [process.pid]; state.setPriority(10) }
            Button("Idle (nice 19)") { state.selectedPIDs = [process.pid]; state.setPriority(19) }
        }
        Divider()
        Button("Go to details") {
            state.selectedPIDs = [process.pid]
            state.page = .details
        }
        Button("Open file location") {
            state.selectedPIDs = [process.pid]
            state.openLocation()
        }
        Button("Search online") {
            state.selectedPIDs = [process.pid]
            state.searchOnline()
        }
        Button("Properties") {
            state.selectedPIDs = [process.pid]
            state.showProperties = true
        }
    }

    private func sorted(_ rows: [LiveProcess]) -> [LiveProcess] {
        let ordered = rows.sorted { lhs, rhs in
            switch sort {
            case .name: return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case .status: return lhs.statusLabel < rhs.statusLabel
            case .cpu: return lhs.cpuPercent < rhs.cpuPercent
            case .memory: return lhs.memoryBytes < rhs.memoryBytes
            case .disk: return lhs.diskMBps < rhs.diskMBps
            case .network: return lhs.networkMBps < rhs.networkMBps
            case .gpu: return lhs.gpuPercent < rhs.gpuPercent
            case .pid: return lhs.pid < rhs.pid
            case .user: return lhs.user.localizedCaseInsensitiveCompare(rhs.user) == .orderedAscending
            case .power: return lhs.powerUsage < rhs.powerUsage
            case .arch: return lhs.architecture < rhs.architecture
            case .publisher: return lhs.publisher < rhs.publisher
            }
        }
        return ascending ? ordered : ordered.reversed()
    }
}

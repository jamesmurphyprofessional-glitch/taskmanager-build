import AppKit
import SwiftUI

struct DetailsView: View {
    @EnvironmentObject private var state: AppState
    @State private var sort = DetailColumn.cpu
    @State private var ascending = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(TM.stroke)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedRows) { process in
                        row(process)
                    }
                }
            }
        }
        .background(TM.row)
    }

    private var header: some View {
        HStack(spacing: 0) {
            head("Name", .name, .leading).frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            head("PID", .pid).frame(width: 64)
            head("Status", .status).frame(width: 100)
            head("User name", .user).frame(width: 92)
            head("CPU", .cpu).frame(width: 72)
            head("Memory", .memory).frame(width: 88)
            head("Disk", .disk).frame(width: 84)
            head("Threads", .threads).frame(width: 70)
            head("Handles", .handles).frame(width: 70)
            head("Priority", .nice).frame(width: 70)
            head("Platform", .arch).frame(width: 72)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(TM.muted)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(TM.panel)
    }

    private func head(_ title: String, _ column: DetailColumn, _ alignment: Alignment = .trailing) -> some View {
        Button {
            if sort == column { ascending.toggle() }
            else {
                sort = column
                ascending = column == .name || column == .user || column == .status || column == .path
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
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ process: LiveProcess) -> some View {
        let selected = state.selectedPIDs.contains(process.pid)
        return Button {
            if NSEvent.modifierFlags.contains(.command) {
                if selected { state.selectedPIDs.remove(process.pid) }
                else { state.selectedPIDs.insert(process.pid) }
            } else {
                state.selectedPIDs = [process.pid]
            }
        } label: {
            HStack(spacing: 0) {
                ProcessNameCell(process: process)
                    .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                Text("\(process.pid)").frame(width: 64, alignment: .trailing)
                Text(process.statusLabel).frame(width: 100, alignment: .trailing)
                Text(process.user).lineLimit(1).frame(width: 92, alignment: .trailing)
                HeatCell(text: Formatters.percent(process.cpuPercent), color: HeatScale.cpu(process.cpuPercent)).frame(width: 72)
                HeatCell(text: Formatters.mb(process.memoryMB), color: HeatScale.memory(process.memoryMB, totalMB: Double(state.memory.total) / 1_048_576.0)).frame(width: 88)
                HeatCell(text: Formatters.mbps(process.diskReadBps + process.diskWriteBps), color: HeatScale.disk(process.diskMBps)).frame(width: 84)
                Text("\(process.threads)").frame(width: 70, alignment: .trailing)
                Text("\(process.ports)").frame(width: 70, alignment: .trailing)
                Text("\(process.nice)").frame(width: 70, alignment: .trailing)
                Text(process.architecture).frame(width: 72, alignment: .trailing)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(TM.text)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(selected ? TM.accent.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("End process") { state.selectedPIDs = [process.pid]; state.endSelected(force: false) }
            Button("End process tree") { state.selectedPIDs = [process.pid]; state.endTree(force: false) }
            Button("Set priority to High") { state.selectedPIDs = [process.pid]; state.setPriority(-10) }
            Button("Set priority to Normal") { state.selectedPIDs = [process.pid]; state.setPriority(0) }
            Button("Set priority to Low") { state.selectedPIDs = [process.pid]; state.setPriority(10) }
            Divider()
            Button("Open file location") { state.selectedPIDs = [process.pid]; state.openLocation() }
            Button("Properties") { state.selectedPIDs = [process.pid]; state.showProperties = true }
        }
    }

    private var sortedRows: [LiveProcess] {
        let ordered = state.filteredProcesses.sorted { lhs, rhs in
            switch sort {
            case .name: return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case .pid: return lhs.pid < rhs.pid
            case .status: return lhs.statusLabel < rhs.statusLabel
            case .user: return lhs.user < rhs.user
            case .cpu: return lhs.cpuPercent < rhs.cpuPercent
            case .memory: return lhs.memoryBytes < rhs.memoryBytes
            case .disk: return lhs.diskMBps < rhs.diskMBps
            case .threads: return lhs.threads < rhs.threads
            case .handles: return lhs.ports < rhs.ports
            case .nice: return lhs.nice < rhs.nice
            case .arch: return lhs.architecture < rhs.architecture
            case .path: return lhs.path < rhs.path
            }
        }
        return ascending ? ordered : ordered.reversed()
    }
}

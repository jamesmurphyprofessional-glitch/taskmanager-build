import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var confirmForce = false
    @State private var confirmEnd = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                sidebar
                    .frame(minWidth: 188, idealWidth: 204, maxWidth: 240)
                VStack(spacing: 0) {
                    toolbar
                    Divider().overlay(TM.stroke)
                    page
                    Divider().overlay(TM.stroke)
                    statusBar
                }
            }
        }
        .background(TM.bg)
        .alert(item: $state.alert) { item in
            Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $state.showRunDialog) {
            RunTaskSheet().environmentObject(state)
        }
        .sheet(isPresented: $state.showProperties) {
            if let process = state.selectedProcess {
                PropertiesSheet(process: process) { state.showProperties = false }
            }
        }
        .confirmationDialog(
            confirmForce ? "Force quit selected process?" : "End selected task?",
            isPresented: $confirmEnd,
            titleVisibility: .visible
        ) {
            Button(confirmForce ? "Force quit" : "End task", role: .destructive) {
                state.endSelected(force: confirmForce)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unsaved work in the selected process may be lost.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Task Manager")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TM.muted)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(SidebarPage.allCases) { page in
                Button {
                    state.page = page
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: page.symbol)
                            .frame(width: 16)
                        Text(page.rawValue)
                        Spacer()
                    }
                    .foregroundStyle(state.page == page ? TM.text : TM.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(state.page == page ? TM.raised : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("Update speed")
                    .font(.caption)
                    .foregroundStyle(TM.muted)
                Picker("", selection: $state.updateSpeed) {
                    ForEach(UpdateSpeed.allCases) { speed in
                        Text(speed.rawValue).tag(speed)
                    }
                }
                .labelsHidden()
                .onChange(of: state.updateSpeed) { _, _ in
                    state.applyUpdateSpeed()
                }
                Toggle("Always on top", isOn: $state.alwaysOnTop)
                    .onChange(of: state.alwaysOnTop) { _, _ in
                        state.applyAlwaysOnTop()
                    }
                    .font(.caption)
                    .foregroundStyle(TM.muted)
            }
            .padding(14)
            Text("Developed by James Murphy")
                .font(.system(size: 10))
                .foregroundStyle(TM.muted)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(TM.sidebar)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(state.page.rawValue)
                .font(.system(size: 20, weight: .semibold))
            Spacer()
            if state.page == .processes || state.page == .details {
                TextField("Search processes", text: $state.search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Button("Run new task") { state.showRunDialog = true }
                Button(state.page == .details ? "End process" : "End task") {
                    confirmForce = false
                    confirmEnd = true
                }
                .disabled(state.selectedPIDs.isEmpty)
                .keyboardShortcut(.delete, modifiers: [])
            }
            if state.page == .services {
                Button("Start") { state.controlService("start") }
                    .disabled(state.selectedService == nil)
                Button("Stop") { state.controlService("stop") }
                    .disabled(state.selectedService == nil)
                Button("Restart") { state.controlService("restart") }
                    .disabled(state.selectedService == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(TM.bg)
    }

    @ViewBuilder
    private var page: some View {
        switch state.page {
        case .processes: ProcessesView()
        case .performance: PerformanceView()
        case .appHistory: AppHistoryView()
        case .startup: StartupView()
        case .users: UsersView()
        case .details: DetailsView()
        case .services: ServicesView()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            MetricChip(title: "Processes", value: "\(state.processes.count)")
            MetricChip(title: "CPU", value: Formatters.percent(state.statusCPU), color: TM.cpu)
            MetricChip(title: "Memory", value: Formatters.percent(state.statusMemory), color: TM.memory)
            MetricChip(title: "Disk", value: Formatters.mbps(state.statusDisk), color: TM.disk)
            MetricChip(title: "Network", value: Formatters.mbps(state.statusNetwork), color: TM.network)
            MetricChip(title: "GPU", value: Formatters.percent(state.statusGPU, digits: 0), color: TM.gpu)
            Spacer()
            Text(state.updateSpeed == .paused ? "Paused" : "Updated \(state.lastSample.formatted(date: .omitted, time: .standard))")
                .font(.system(size: 11))
                .foregroundStyle(TM.muted)
            Text("·")
                .foregroundStyle(TM.muted)
            Text("Developed by James Murphy")
                .font(.system(size: 11))
                .foregroundStyle(TM.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(TM.sidebar)
    }
}

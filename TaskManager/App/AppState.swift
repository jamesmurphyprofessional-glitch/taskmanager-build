import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var page: SidebarPage = .processes
    @Published var processes: [LiveProcess] = []
    @Published var history: [AppHistoryRow] = []
    @Published var services: [LaunchService] = []
    @Published var startupItems: [StartupEntry] = []
    @Published var users: [SessionUser] = []
    @Published var cpu = CPUSnapshot()
    @Published var memory = MemorySnapshot()
    @Published var disks: [DiskSnapshot] = []
    @Published var networks: [NetworkAdapterSnapshot] = []
    @Published var gpu = GPUSnapshot()
    @Published var historySeries = PerformanceHistory()
    @Published var selectedPIDs: Set<Int32> = []
    @Published var selectedService: LaunchService.ID?
    @Published var selectedStartup: StartupEntry.ID?
    @Published var selectedUser: uid_t?
    @Published var search = ""
    @Published var updateSpeed: UpdateSpeed = .normal
    @Published var alwaysOnTop = false
    @Published var showAllProcessTypes = true
    @Published var performancePane: PerformancePane = .cpu
    @Published var showLogicalProcessors = false
    @Published var alert: ActionAlert?
    @Published var showRunDialog = false
    @Published var showProperties = false
    @Published var runCommand = ""
    @Published var runAsAdmin = false
    @Published var lastSample = Date()

    private let sampler = Sampler()
    private let serviceMonitor = ServiceMonitor()
    private let startupMonitor = StartupMonitor()
    private var timer: AnyCancellable?
    private var isSampling = false
    private var auxiliaryLoaded = false

    var selectedProcess: LiveProcess? {
        guard let pid = selectedPIDs.first else { return nil }
        return processes.first { $0.pid == pid }
    }

    var filteredProcesses: [LiveProcess] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return processes }
        return processes.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
                || $0.user.localizedCaseInsensitiveContains(query)
                || $0.path.localizedCaseInsensitiveContains(query)
                || String($0.pid).contains(query)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var processGroups: [ProcessGroup] {
        ProcessKind.allCases.compactMap { kind in
            let rows = filteredProcesses.filter { $0.kind == kind }
            guard !rows.isEmpty else { return nil }
            return ProcessGroup(kind: kind, processes: rows)
        }
    }

    var statusCPU: Double { cpu.overall }
    var statusMemory: Double { memory.usedPercent }
    var statusDisk: Double { disks.first.map { $0.readBps + $0.writeBps } ?? 0 }
    var statusNetwork: Double { networks.reduce(0) { $0 + $1.inBps + $1.outBps } }
    var statusGPU: Double { gpu.utilization }

    init() {
        applyUpdateSpeed()
        refreshNow()
    }

    func applyUpdateSpeed() {
        timer?.cancel()
        guard let interval = updateSpeed.interval else { return }
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshNow()
            }
    }

    func refreshNow() {
        guard !isSampling else { return }
        isSampling = true
        let sampler = self.sampler
        Task.detached(priority: .userInitiated) { [weak self] in
            let snapshot = sampler.sample()
            await self?.applySnapshot(snapshot)
        }
    }

    func refreshAuxiliary() {
        let serviceMonitor = self.serviceMonitor
        let startupMonitor = self.startupMonitor
        Task.detached(priority: .utility) { [weak self] in
            let services = serviceMonitor.list()
            let startup = startupMonitor.list()
            await self?.applyAuxiliary(services: services, startup: startup)
        }
    }

    func loadAuxiliaryIfNeeded() {
        guard !auxiliaryLoaded else { return }
        auxiliaryLoaded = true
        refreshAuxiliary()
    }

    func endSelected(force: Bool) {
        let targets = processes.filter { selectedPIDs.contains($0.pid) }
        guard !targets.isEmpty else { return }
        do {
            for process in targets {
                try ProcessController.endTask(process, force: force)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.refreshNow()
            }
        } catch {
            alert = ActionAlert(title: "Unable to end task", message: error.localizedDescription)
        }
    }

    func endTree(force: Bool) {
        guard let root = selectedProcess else { return }
        do {
            try ProcessController.endTree(root: root, all: processes, force: force)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.refreshNow()
            }
        } catch {
            alert = ActionAlert(title: "Unable to end process tree", message: error.localizedDescription)
        }
    }

    func setPriority(_ value: Int32) {
        guard let process = selectedProcess else { return }
        do {
            try ProcessController.setNice(process, value: value)
            refreshNow()
        } catch {
            alert = ActionAlert(title: "Unable to set priority", message: error.localizedDescription)
        }
    }

    func setEfficiency(_ enabled: Bool) {
        guard let process = selectedProcess else { return }
        do {
            try ProcessController.setEfficiencyMode(process, enabled: enabled)
        } catch {
            alert = ActionAlert(title: "Unable to change efficiency mode", message: error.localizedDescription)
        }
    }

    func openLocation() {
        guard let process = selectedProcess else { return }
        do {
            try ProcessController.openLocation(process)
        } catch {
            alert = ActionAlert(title: "Unable to open location", message: error.localizedDescription)
        }
    }

    func searchOnline() {
        guard let process = selectedProcess else { return }
        ProcessController.searchOnline(process)
    }

    func runNewTask() {
        do {
            try ProcessController.runNewTask(command: runCommand, asAdmin: runAsAdmin)
            showRunDialog = false
            runCommand = ""
            runAsAdmin = false
        } catch {
            alert = ActionAlert(title: "Unable to create task", message: error.localizedDescription)
        }
    }

    func controlService(_ action: String) {
        guard let id = selectedService, let service = services.first(where: { $0.id == id }) else { return }
        do {
            switch action {
            case "start": try serviceMonitor.start(service)
            case "stop": try serviceMonitor.stop(service)
            default: try serviceMonitor.restart(service)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.refreshAuxiliary()
            }
        } catch {
            alert = ActionAlert(title: "Service command failed", message: error.localizedDescription)
        }
    }

    func toggleStartup(_ entry: StartupEntry, enabled: Bool) {
        do {
            try startupMonitor.setEnabled(entry, enabled: enabled)
            refreshAuxiliary()
        } catch {
            alert = ActionAlert(title: "Unable to update startup item", message: error.localizedDescription)
        }
    }

    func applyAlwaysOnTop() {
        for window in NSApp.windows {
            window.level = alwaysOnTop ? .floating : .normal
        }
    }

    private func applySnapshot(_ snapshot: Sampler.Snapshot) {
        processes = snapshot.processes
        history = snapshot.history
        users = snapshot.users
        cpu = snapshot.cpu
        memory = snapshot.memory
        disks = snapshot.disks
        networks = snapshot.networks
        gpu = snapshot.gpu
        historySeries.append(cpu.overall, to: \.cpu)
        historySeries.append(memory.usedPercent, to: \.memory)
        historySeries.append((disks.first?.readBps ?? 0) / 1_048_576.0, to: \.diskRead)
        historySeries.append((disks.first?.writeBps ?? 0) / 1_048_576.0, to: \.diskWrite)
        historySeries.append(networks.reduce(0) { $0 + $1.inBps } / 1_048_576.0, to: \.netIn)
        historySeries.append(networks.reduce(0) { $0 + $1.outBps } / 1_048_576.0, to: \.netOut)
        historySeries.append(gpu.utilization, to: \.gpu)
        if historySeries.perCore.count != cpu.perCore.count {
            historySeries.perCore = cpu.perCore.map { [$0] }
        } else {
            for index in cpu.perCore.indices {
                historySeries.perCore[index].append(cpu.perCore[index])
                if historySeries.perCore[index].count > PerformanceHistory.capacity {
                    historySeries.perCore[index].removeFirst(historySeries.perCore[index].count - PerformanceHistory.capacity)
                }
            }
        }
        lastSample = Date()
        isSampling = false
    }

    private func applyAuxiliary(services: [LaunchService], startup: [StartupEntry]) {
        self.services = services
        self.startupItems = startup
    }
}

final class Sampler: @unchecked Sendable {
    struct Snapshot {
        var processes: [LiveProcess]
        var history: [AppHistoryRow]
        var users: [SessionUser]
        var cpu: CPUSnapshot
        var memory: MemorySnapshot
        var disks: [DiskSnapshot]
        var networks: [NetworkAdapterSnapshot]
        var gpu: GPUSnapshot
    }

    private let processMonitor = ProcessMonitor()
    private let performanceMonitor = PerformanceMonitor()
    private let lock = NSLock()

    func sample() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let sample = processMonitor.snapshot()
        let processes = sample.processes.sorted { $0.cpuPercent > $1.cpuPercent }
        let threads = processes.reduce(0) { $0 + Int($1.threads) }
        let handles = processes.reduce(0) { $0 + Int($1.ports) }
        let metrics = performanceMonitor.sample(
            processCount: processes.count,
            threadCount: threads,
            handleCount: handles
        )
        return Snapshot(
            processes: processes,
            history: sample.history,
            users: UserMonitor.users(from: processes),
            cpu: metrics.cpu,
            memory: metrics.memory,
            disks: metrics.disks,
            networks: metrics.networks,
            gpu: metrics.gpu
        )
    }
}

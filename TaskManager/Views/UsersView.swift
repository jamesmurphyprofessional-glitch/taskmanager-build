import SwiftUI

struct UsersView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(TM.stroke)
            List(state.users, selection: $state.selectedUser) { user in
                HStack {
                    Image(systemName: user.isConsole ? "person.crop.circle.fill" : "person.crop.circle")
                        .foregroundStyle(TM.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(user.fullName.isEmpty ? user.name : user.fullName)
                                .fontWeight(.semibold)
                            if user.isConsole {
                                Text("signed in")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(TM.cpu.opacity(0.2))
                                    .foregroundStyle(TM.cpu)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(user.name).foregroundStyle(TM.muted).font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(user.processCount)").frame(width: 90, alignment: .trailing)
                    HeatCell(text: Formatters.percent(user.cpuPercent), color: HeatScale.cpu(user.cpuPercent))
                        .frame(width: 80, height: 22)
                    HeatCell(
                        text: Formatters.bytes(user.memoryBytes),
                        color: HeatScale.memory(Double(user.memoryBytes) / 1_048_576.0, totalMB: Double(state.memory.total) / 1_048_576.0)
                    )
                    .frame(width: 100, height: 22)
                }
                .padding(.vertical, 4)
                .tag(user.uid)
                .contextMenu {
                    Button("Show processes") {
                        state.search = user.name
                        state.page = .processes
                    }
                    if !user.isConsole {
                        Button("Disconnect is not available for this account") {}
                            .disabled(true)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(TM.bg)
    }

    private var header: some View {
        HStack {
            Text("User").frame(maxWidth: .infinity, alignment: .leading)
            Text("Processes").frame(width: 90, alignment: .trailing)
            Text("CPU").frame(width: 80, alignment: .trailing)
            Text("Memory").frame(width: 100, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(TM.muted)
        .padding(.horizontal, 20)
        .frame(height: 26)
        .background(TM.panel)
    }
}

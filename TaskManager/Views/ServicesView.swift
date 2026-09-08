import SwiftUI

struct ServicesView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""

    private var rows: [LaunchService] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return state.services }
        return state.services.filter {
            $0.label.localizedCaseInsensitiveContains(q)
                || ($0.program?.localizedCaseInsensitiveContains(q) ?? false)
                || $0.domain.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search services", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                Text("\(rows.count) services")
                    .foregroundStyle(TM.muted)
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            header
            Divider().overlay(TM.stroke)
            List(rows, selection: $state.selectedService) { service in
                HStack {
                    Circle()
                        .fill(service.running ? TM.cpu : TM.muted.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(service.label)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(service.pid.map(String.init) ?? "")
                        .frame(width: 70, alignment: .trailing)
                    Text(service.statusText)
                        .foregroundStyle(service.running ? TM.cpu : TM.muted)
                        .frame(width: 110, alignment: .trailing)
                    Text(service.domain)
                        .foregroundStyle(TM.muted)
                        .frame(width: 140, alignment: .trailing)
                    Text(service.program ?? service.plistPath ?? "")
                        .foregroundStyle(TM.muted)
                        .lineLimit(1)
                        .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 12))
                .tag(service.id)
                .contextMenu {
                    Button("Start") { state.selectedService = service.id; state.controlService("start") }
                    Button("Stop") { state.selectedService = service.id; state.controlService("stop") }
                    Button("Restart") { state.selectedService = service.id; state.controlService("restart") }
                    if let pid = service.pid {
                        Button("Go to process") {
                            state.selectedPIDs = [pid]
                            state.page = .details
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(TM.bg)
        .onAppear { state.loadAuxiliaryIfNeeded() }
    }

    private var header: some View {
        HStack {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("PID").frame(width: 70, alignment: .trailing)
            Text("Status").frame(width: 110, alignment: .trailing)
            Text("Group").frame(width: 140, alignment: .trailing)
            Text("Description").frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(TM.muted)
        .padding(.horizontal, 28)
        .frame(height: 26)
        .background(TM.panel)
    }
}

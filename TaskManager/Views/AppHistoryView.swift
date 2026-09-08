import SwiftUI

struct AppHistoryView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Resource use by apps since Task Manager was opened. macOS does not keep a Windows-style long-term app history store.")
                .font(.callout)
                .foregroundStyle(TM.muted)
                .padding(14)
            header
            Divider().overlay(TM.stroke)
            List(state.history) { row in
                HStack {
                    HStack(spacing: 8) {
                        if let icon = row.icon {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(row.name).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.publisher.isEmpty ? "—" : row.publisher)
                        .foregroundStyle(TM.muted)
                        .lineLimit(1)
                        .frame(width: 220, alignment: .leading)
                    Text(Formatters.cpuTime(row.cpuTimeSeconds))
                        .frame(width: 110, alignment: .trailing)
                    Text(Formatters.bytes(row.networkBytes))
                        .frame(width: 100, alignment: .trailing)
                    Text(Formatters.bytes(row.peakMemoryBytes))
                        .frame(width: 110, alignment: .trailing)
                }
                .font(.system(size: 12))
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(TM.bg)
    }

    private var header: some View {
        HStack {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Publisher").frame(width: 220, alignment: .leading)
            Text("CPU time").frame(width: 110, alignment: .trailing)
            Text("Network").frame(width: 100, alignment: .trailing)
            Text("Peak memory").frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(TM.muted)
        .padding(.horizontal, 20)
        .frame(height: 26)
        .background(TM.panel)
    }
}

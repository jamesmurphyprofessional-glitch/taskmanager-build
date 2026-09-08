import SwiftUI

struct StartupView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("These programs are configured to start when you sign in or when macOS boots. Disabling items you do not need can improve startup time.")
                .font(.callout)
                .foregroundStyle(TM.muted)
                .padding(14)
            header
            Divider().overlay(TM.stroke)
            List(state.startupItems, selection: $state.selectedStartup) { item in
                HStack {
                    Text(item.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.publisher)
                        .foregroundStyle(TM.muted)
                        .lineLimit(1)
                        .frame(width: 220, alignment: .leading)
                    Text(item.kind.rawValue)
                        .frame(width: 120, alignment: .leading)
                    Text(item.impact)
                        .foregroundStyle(item.impact == "High" ? TM.danger : TM.muted)
                        .frame(width: 90, alignment: .leading)
                    Toggle("", isOn: Binding(
                        get: { item.enabled },
                        set: { state.toggleStartup(item, enabled: $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .frame(width: 70)
                }
                .font(.system(size: 12))
                .tag(item.id)
                .contextMenu {
                    Button("Open file location") {
                        StartupMonitor().open(item)
                    }
                    Button(item.enabled ? "Disable" : "Enable") {
                        state.toggleStartup(item, enabled: !item.enabled)
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
            Text("Publisher").frame(width: 220, alignment: .leading)
            Text("Type").frame(width: 120, alignment: .leading)
            Text("Startup impact").frame(width: 90, alignment: .leading)
            Text("Status").frame(width: 70, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(TM.muted)
        .padding(.horizontal, 20)
        .frame(height: 26)
        .background(TM.panel)
    }
}

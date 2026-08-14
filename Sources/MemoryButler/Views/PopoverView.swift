import SwiftUI

struct PopoverView: View {
    private enum Tab: CaseIterable {
        case overview, settings, history

        var title: String {
            switch self {
            case .overview: return L("tab.overview")
            case .settings: return L("tab.settings")
            case .history:  return L("tab.history")
            }
        }
    }

    @State private var tab: Tab = .overview
    @ObservedObject private var settings = AppModel.shared.settings

    var body: some View {
        VStack(spacing: 10) {
            header

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .overview: OverviewView()
            case .settings: SettingsView()
            case .history:  HistoryView()
            }

            footer
        }
        .padding(14)
        .frame(width: 332)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "memorychip.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)
            Text(L("app.name"))
                .font(.system(size: 14, weight: .bold))
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Text("MemoryButler \(Updater.isBundled ? Updater.currentVersion : "dev")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L("footer.quit"))
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }
}

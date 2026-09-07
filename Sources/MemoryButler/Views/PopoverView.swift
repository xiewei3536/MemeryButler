import SwiftUI

enum PopoverTab: CaseIterable {
    case overview, apps, settings, history

    var title: String {
        switch self {
        case .overview: return L("tab.overview")
        case .apps:     return L("tab.apps")
        case .settings: return L("tab.settings")
        case .history:  return L("tab.history")
        }
    }
}

struct PopoverView: View {
    @State private var tab: PopoverTab
    @ObservedObject private var settings = AppModel.shared.settings

    init(initialTab: PopoverTab = .overview) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 10) {
            header

            Picker("", selection: $tab) {
                ForEach(PopoverTab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .overview: OverviewView(showApps: { tab = .apps })
            case .apps:     AppsView()
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
            Link(destination: AppInfo.repoURL) {
                HStack(spacing: 3) {
                    Text("MemoryButler \(Updater.isBundled ? Updater.currentVersion : "dev")")
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 8))
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
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
            .keyboardShortcut("q", modifiers: .command)   // 面板開著時 ⌘Q 也能結束
            .help(L("footer.quit.help"))
        }
        .padding(.top, 2)
    }
}

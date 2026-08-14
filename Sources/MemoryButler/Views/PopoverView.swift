import SwiftUI

struct PopoverView: View {
    private enum Tab: String, CaseIterable {
        case overview = "總覽"
        case settings = "設定"
        case history  = "紀錄"
    }

    @State private var tab: Tab = .overview

    var body: some View {
        VStack(spacing: 10) {
            header

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
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
            Text("記憶體管家")
                .font(.system(size: 14, weight: .bold))
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Text("MemoryButler 1.0")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                    Text("結束")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }
}

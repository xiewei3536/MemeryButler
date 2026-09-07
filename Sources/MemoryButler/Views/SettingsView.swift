import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppModel.shared.settings
    @ObservedObject private var updater = AppModel.shared.updater

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                automationCard
                behaviorCard
                generalCard
                updateCard
                aboutCard
            }
            .padding(.bottom, 2)
        }
        .frame(height: Layout.settingsHeight)   // 內容一定超過一頁：固定高度捲動，且與總覽同高
    }

    // MARK: 自動化

    private var automationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                SettingRow(title: L("set.auto.title"),
                           subtitle: L("set.auto.sub")) {
                    SwitchToggle(L("set.auto.title"), isOn: $settings.autoEnabled)
                }

                Divider()

                Group {
                    SettingRow(title: L("set.pressure.title"),
                               subtitle: L("set.pressure.sub")) {
                        SwitchToggle(L("set.pressure.title"), isOn: $settings.triggerOnPressure)
                    }

                    SettingRow(title: L("set.threshold.title"),
                               subtitle: LF("set.threshold.sub", Int(settings.thresholdPercent))) {
                        SwitchToggle(L("set.threshold.title"), isOn: $settings.triggerOnThreshold)
                    }
                    if settings.triggerOnThreshold {
                        Slider(value: $settings.thresholdPercent, in: 5...30, step: 1)
                            .controlSize(.small)
                            .accessibilityLabel(L("set.threshold.title"))
                    }

                    SettingRow(title: L("set.schedule.title"),
                               subtitle: settings.scheduleEnabled
                                         ? LF("set.schedule.sub.on", settings.scheduleMinutes)
                                         : L("set.schedule.sub.off")) {
                        SwitchToggle(L("set.schedule.title"), isOn: $settings.scheduleEnabled)
                    }
                    if settings.scheduleEnabled {
                        Picker("", selection: $settings.scheduleMinutes) {
                            Text(L("sched.15")).tag(15)
                            Text(L("sched.30")).tag(30)
                            Text(L("sched.60")).tag(60)
                            Text(L("sched.120")).tag(120)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                }
                .disabled(!settings.autoEnabled)
                .opacity(settings.autoEnabled ? 1 : 0.45)
            }
        }
    }

    // MARK: 節奏與守門

    private var behaviorCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                SettingRow(title: L("set.cooldown.title"),
                           subtitle: LF("set.cooldown.sub", Int(settings.cooldownMinutes))) {
                    EmptyView()
                }
                Slider(value: $settings.cooldownMinutes, in: 5...60, step: 5)
                    .controlSize(.small)
                    .accessibilityLabel(L("set.cooldown.title"))

                Divider()

                SettingRow(title: L("set.lowpower.title"),
                           subtitle: L("set.lowpower.sub")) {
                    SwitchToggle(L("set.lowpower.title"), isOn: $settings.pauseOnLowPower)
                }
            }
        }
    }

    // MARK: 一般

    private var generalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                SettingRow(title: L("set.menubar.title"), subtitle: nil) {
                    SwitchToggle(L("set.menubar.title"), isOn: $settings.showPercentInMenuBar)
                }

                Divider()

                SettingRow(title: L("set.login.title"),
                           subtitle: L("set.login.sub")) {
                    SwitchToggle(L("set.login.title"), isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    ))
                }

                Divider()

                SettingRow(title: L("set.lang.title"), subtitle: nil) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
        }
    }

    // MARK: 軟體更新

    private var updateCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                SettingRow(title: L("set.update.title"),
                           subtitle: LF("set.update.current",
                                        Updater.isBundled ? Updater.currentVersion : "dev")) {
                    checkControl
                }

                if let text = statusText {
                    HStack(spacing: 5) {
                        if case .available = updater.status {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.series)
                        }
                        Text(text)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        if case .available = updater.status {
                            Button(L("update.banner.button")) {
                                Task { await AppModel.shared.updater.downloadAndInstall() }
                            }
                            .controlSize(.mini)
                        }
                    }
                }

                Divider()

                SettingRow(title: L("set.update.auto"), subtitle: nil) {
                    SwitchToggle(L("set.update.auto"), isOn: $settings.autoUpdateCheck)
                }
            }
        }
    }

    // MARK: 關於與開源資訊

    private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.series)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MemoryButler \(Updater.isBundled ? Updater.currentVersion : "dev")")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(L("about.opensource"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 14) {
                    aboutLink(L("about.viewSource"), "curlybraces", AppInfo.repoURL)
                    aboutLink(L("about.reportIssue"), "ladybug", AppInfo.issuesURL)
                    aboutLink("MIT", "doc.text", AppInfo.licenseURL)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func aboutLink(_ title: String, _ symbol: String, _ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10))
                Text(title).font(.system(size: 11))
            }
            .foregroundStyle(Theme.series)
        }
    }

    @ViewBuilder
    private var checkControl: some View {
        if case .checking = updater.status {
            ProgressView().controlSize(.small)
        } else {
            Button(L("set.update.check")) {
                Task { await AppModel.shared.updater.check(userInitiated: true) }
            }
            .controlSize(.small)
        }
    }

    private var statusText: String? {
        switch updater.status {
        case .checking:            return L("update.checking")
        case .upToDate:            return L("update.uptodate")
        case .failed(let e):       return LF("update.failed", e)
        case .available(let v):    return LF("update.banner.title", "v" + v)
        case .downloading(let p):  return LF("update.downloading", Int(p * 100))
        case .installing:          return L("update.installing")
        case .restarting:          return L("update.restarting")
        case .idle:                return nil
        }
    }
}

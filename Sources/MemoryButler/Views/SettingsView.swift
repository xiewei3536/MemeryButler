import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppModel.shared.settings

    var body: some View {
        VStack(spacing: 10) {
            Card {
                VStack(alignment: .leading, spacing: 11) {
                    SettingRow(title: "智慧自動釋放",
                               subtitle: "由管家自主監控並在適當時機釋放") {
                        Toggle("", isOn: $settings.autoEnabled)
                            .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }

                    Divider()

                    Group {
                        SettingRow(title: "壓力警告時釋放",
                                   subtitle: "收到系統核心壓力訊號立即行動") {
                            Toggle("", isOn: $settings.triggerOnPressure)
                                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        }

                        SettingRow(title: "可用記憶體過低時釋放",
                                   subtitle: "低於 \(Int(settings.thresholdPercent))% 並持續 30 秒") {
                            Toggle("", isOn: $settings.triggerOnThreshold)
                                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        }
                        if settings.triggerOnThreshold {
                            Slider(value: $settings.thresholdPercent, in: 5...30, step: 1)
                                .controlSize(.small)
                        }

                        SettingRow(title: "定時釋放",
                                   subtitle: settings.scheduleEnabled
                                             ? "每 \(settings.scheduleMinutes) 分鐘整理一次"
                                             : "以固定節奏定期整理") {
                            Toggle("", isOn: $settings.scheduleEnabled)
                                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        }
                        if settings.scheduleEnabled {
                            Picker("", selection: $settings.scheduleMinutes) {
                                Text("每 15 分鐘").tag(15)
                                Text("每 30 分鐘").tag(30)
                                Text("每 60 分鐘").tag(60)
                                Text("每 2 小時").tag(120)
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

            Card {
                VStack(alignment: .leading, spacing: 11) {
                    SettingRow(title: "冷卻時間",
                               subtitle: "兩次自動釋放至少間隔 \(Int(settings.cooldownMinutes)) 分鐘,成效不佳時自動加倍") {
                        EmptyView()
                    }
                    Slider(value: $settings.cooldownMinutes, in: 5...60, step: 5)
                        .controlSize(.small)

                    Divider()

                    SettingRow(title: "低耗電模式時暫停",
                               subtitle: "省電期間不執行自動釋放") {
                        Toggle("", isOn: $settings.pauseOnLowPower)
                            .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 11) {
                    SettingRow(title: "選單列顯示使用率", subtitle: nil) {
                        Toggle("", isOn: $settings.showPercentInMenuBar)
                            .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }

                    Divider()

                    SettingRow(title: "登入時自動啟動",
                               subtitle: "開機後靜靜守在選單列") {
                        Toggle("", isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: { settings.setLaunchAtLogin($0) }
                        ))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                }
            }
        }
    }
}

import Foundation
import SwiftUI
import ServiceManagement

/// 所有使用者設定。@Published 保證 UI 即時刷新，didSet 落盤 UserDefaults。
@MainActor
final class SettingsStore: ObservableObject {

    private static let d = UserDefaults.standard

    // 自動化
    @Published var autoEnabled: Bool { didSet { Self.d.set(autoEnabled, forKey: "autoEnabled") } }
    @Published var triggerOnPressure: Bool { didSet { Self.d.set(triggerOnPressure, forKey: "triggerOnPressure") } }
    @Published var triggerOnThreshold: Bool { didSet { Self.d.set(triggerOnThreshold, forKey: "triggerOnThreshold") } }
    @Published var thresholdPercent: Double { didSet { Self.d.set(thresholdPercent, forKey: "thresholdPercent") } }
    @Published var scheduleEnabled: Bool { didSet { Self.d.set(scheduleEnabled, forKey: "scheduleEnabled") } }
    @Published var scheduleMinutes: Int { didSet { Self.d.set(scheduleMinutes, forKey: "scheduleMinutes") } }
    @Published var cooldownMinutes: Double { didSet { Self.d.set(cooldownMinutes, forKey: "cooldownMinutes") } }
    @Published var pauseOnLowPower: Bool { didSet { Self.d.set(pauseOnLowPower, forKey: "pauseOnLowPower") } }

    // 外觀
    @Published var showPercentInMenuBar: Bool { didSet { Self.d.set(showPercentInMenuBar, forKey: "showPercentInMenuBar") } }

    // 語言
    @Published var language: AppLanguage {
        didSet {
            Self.d.set(language.rawValue, forKey: "appLanguage")
            L10n.language = language
        }
    }

    // 更新
    @Published var autoUpdateCheck: Bool { didSet { Self.d.set(autoUpdateCheck, forKey: "autoUpdateCheck") } }

    // 登入啟動
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    init() {
        Self.d.register(defaults: [
            "autoEnabled": true,
            "triggerOnPressure": true,
            "triggerOnThreshold": true,
            "thresholdPercent": 12.0,
            "scheduleEnabled": false,
            "scheduleMinutes": 60,
            "cooldownMinutes": 15.0,
            "pauseOnLowPower": true,
            "showPercentInMenuBar": true,
            "appLanguage": "system",
            "autoUpdateCheck": true,
        ])
        autoEnabled         = Self.d.bool(forKey: "autoEnabled")
        triggerOnPressure   = Self.d.bool(forKey: "triggerOnPressure")
        triggerOnThreshold  = Self.d.bool(forKey: "triggerOnThreshold")
        thresholdPercent    = Self.d.double(forKey: "thresholdPercent")
        scheduleEnabled     = Self.d.bool(forKey: "scheduleEnabled")
        scheduleMinutes     = Self.d.integer(forKey: "scheduleMinutes")
        cooldownMinutes     = Self.d.double(forKey: "cooldownMinutes")
        pauseOnLowPower     = Self.d.bool(forKey: "pauseOnLowPower")
        showPercentInMenuBar = Self.d.bool(forKey: "showPercentInMenuBar")
        language = AppLanguage(rawValue: Self.d.string(forKey: "appLanguage") ?? "system") ?? .system
        autoUpdateCheck = Self.d.bool(forKey: "autoUpdateCheck")
        L10n.language = language
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 未打包成 .app 執行時會失敗；下方以實際狀態校正 UI
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

import Foundation
import SwiftUI
import AppKit

/// 全域組裝：監控 → 引擎 → 自動駕駛。
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let monitor: MemoryMonitor
    let engine: ReleaseEngine
    let settings: SettingsStore
    let autopilot: AutoPilot
    let updater: Updater
    let apps = AppUsageModel()

    private init() {
        let monitor = MemoryMonitor()
        let engine = ReleaseEngine()
        let settings = SettingsStore()
        self.monitor = monitor
        self.engine = engine
        self.settings = settings
        self.autopilot = AutoPilot(monitor: monitor, engine: engine, settings: settings)
        self.updater = Updater(settings: settings)
        monitor.start()
    }

    func manualRelease() {
        guard !engine.isRunning else { return }
        Task {
            if case .released = await engine.release(trigger: .manual) {
                autopilot.noteManualRelease()
            }
        }
    }
}

// MARK: - 色彩（動態系統色，自動適配亮/暗模式）

extension PressureLevel {
    var color: Color {
        switch self {
        case .normal:   return Color(nsColor: .systemGreen)
        case .warning:  return Color(nsColor: .systemOrange)
        case .critical: return Color(nsColor: .systemRed)
        }
    }
    var symbol: String {
        switch self {
        case .normal:   return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.circle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

enum AppInfo {
    static let repoURL = URL(string: "https://github.com/xiewei3536/MemeryButler")!
    static let issuesURL = URL(string: "https://github.com/xiewei3536/MemeryButler/issues")!
    static let releasesURL = URL(string: "https://github.com/xiewei3536/MemeryButler/releases")!
    static let licenseURL = URL(string: "https://github.com/xiewei3536/MemeryButler/blob/main/LICENSE")!
}

enum Layout {
    // 選單列面板是「依內容自動調整大小」的視窗，而 ScrollView 的理想高度接近零：
    // 直接放 ScrollView 會被壓扁到只剩一列。原則：內容少就讓視窗跟著縮短（不用 ScrollView），
    // 內容多才固定在上限並捲動。上限取總覽分頁的自然高度，切分頁時視窗才不會大跳。

    /// 紀錄分頁：不超過這個筆數就直接展開，超過才捲動
    static let historyInlineRows = 8
    /// 紀錄分頁捲動時的列表高度（約 8 列）
    static let historyListHeight: CGFloat = 400
    /// 設定分頁的高度（內容一定超過一頁，固定為與總覽相近的高度捲動）
    static let settingsHeight: CGFloat = 544
}

enum Theme {
    /// 單一資料序列用色（唯一序列，不與其他類別色相鄰）
    static let series = Color(nsColor: .systemBlue)
    static let accentGradient = LinearGradient(
        colors: [Color(nsColor: .systemBlue), Color(nsColor: .systemIndigo)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

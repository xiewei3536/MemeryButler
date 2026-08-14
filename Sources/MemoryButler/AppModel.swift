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
            if await engine.release(trigger: .manual) != nil {
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

enum Theme {
    /// 單一資料序列用色（唯一序列，不與其他類別色相鄰）
    static let series = Color(nsColor: .systemBlue)
    static let accentGradient = LinearGradient(
        colors: [Color(nsColor: .systemBlue), Color(nsColor: .systemIndigo)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

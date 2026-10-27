import Foundation
import SwiftUI
import AppKit
import Combine

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
    let system = SystemMonitor()
    let panel = PanelState()
    let lag: LagDetector
    let feed: PanelFeed
    let menuBar: MenuBarModel

    private init() {
        let monitor = MemoryMonitor()
        let engine = ReleaseEngine()
        let settings = SettingsStore()
        self.monitor = monitor
        self.engine = engine
        self.settings = settings
        let autopilot = AutoPilot(monitor: monitor, engine: engine, settings: settings)
        self.autopilot = autopilot
        self.updater = Updater(settings: settings)
        let lag = LagDetector(settings: settings, monitor: monitor)
        self.lag = lag
        self.feed = PanelFeed(monitor: monitor, lag: lag, panel: panel)
        self.menuBar = MenuBarModel(monitor: monitor)
        lag.onAutoDemote = { [weak autopilot] text in autopilot?.note(text) }
        monitor.start()
        lag.start()
    }

    func manualRelease() {
        guard !engine.isRunning else { return }
        let swapInRate = monitor.current.swapInRate
        Task {
            if case .released(let event) = await engine.release(trigger: .manual, recentSwapInRate: swapInRate) {
                autopilot.noteManualRelease(event)
            }
        }
    }
}

// MARK: - 選單列數字
//
// 選單列標籤每次重算都會重新排字、重畫狀態列圖片；使用率常常幾十秒不變，
// 只在顯示的整數百分比改變時才發布

@MainActor
final class MenuBarModel: ObservableObject {
    @Published private(set) var percent = 0
    private var cancellable: AnyCancellable?

    init(monitor: MemoryMonitor) {
        cancellable = monitor.$current
            .map { Int(($0.usedFraction * 100).rounded()) }
            .removeDuplicates()
            .sink { [weak self] in self?.percent = $0 }
    }
}

// MARK: - 面板重繪節拍器
//
// 1.3 以前面板內的視圖直接觀察 MemoryMonitor：面板關著時（MenuBarExtra 的內容仍然活著）
// 每 2 秒照樣重算整個總覽，連 150 點的 Swift Charts 曲線一起——實測閒置約 1% CPU，
// sample 裡全是 HistoryChartCard.chart.getter。現在面板內容只觀察這個節拍器：
// 看得見時跟著每次取樣重繪，看不見時完全不打擾 SwiftUI；一打開就立刻補上最新資料。

@MainActor
final class PanelFeed: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    init(monitor: MemoryMonitor, lag: LagDetector, panel: PanelState) {
        monitor.objectWillChange
            .merge(with: lag.objectWillChange)
            .sink { [weak self, weak panel] _ in
                if panel?.isVisible == true { self?.objectWillChange.send() }
            }
            .store(in: &cancellables)
        panel.$isVisible
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
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
    static let settingsHeight: CGFloat = 600
}

enum Theme {
    /// 單一資料序列用色（唯一序列，不與其他類別色相鄰）
    static let series = Color(nsColor: .systemBlue)
    /// CPU 用量的序列色：與記憶體的藍明確區分，又不與警告用的橘、紅混淆
    static let cpuSeries = Color(nsColor: .systemIndigo)
    static let accentGradient = LinearGradient(
        colors: [Color(nsColor: .systemBlue), Color(nsColor: .systemIndigo)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - 面板可見狀態
//
// MenuBarExtra(.window) 的內容視圖在面板關閉後仍然活著：repeatForever 動畫、TimelineView、
// .task 迴圈全部繼續跑。實測在 144Hz 外接螢幕上，面板關著的 App 仍佔 12～19% CPU
//（sample 顯示主執行緒 18% 在 DisplayLink 驅動的動畫版面重算）。
// 這裡以「有沒有高度 > 100 且未被遮蔽的視窗」判定面板是否真的看得見，讓動畫與計時器在隱藏時暫停。

@MainActor
final class PanelState: ObservableObject {
    @Published private(set) var isVisible = false
    private var observers: [NSObjectProtocol] = []
    private var fallbackTimer: DispatchSourceTimer?

    init() {
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
        ]
        for name in names {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // 通知送達時視窗狀態可能還沒更新完，下一輪 run loop 再算
                DispatchQueue.main.async { self?.recompute() }
            })
        }
        // 保險：萬一某次切換沒有通知，每 5 秒校正一次（成本可忽略）
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in self?.recompute() }
        t.resume()
        fallbackTimer = t
    }

    private func recompute() {
        let visible = NSApp.windows.contains { w in
            w.isVisible && w.frame.height > 100 && w.occlusionState.contains(.visible)
        }
        if visible != isVisible { isVisible = visible }
    }
}


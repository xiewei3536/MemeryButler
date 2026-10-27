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
    // 直接放 ScrollView 會被壓扁到只剩一列。做法（FittingScroll）：先量分頁內容的自然高度，
    // 外框取 min(自然高度, 螢幕放得下的高度)——放得下就跟內容一樣高、不捲動，放不下才捲動。
    // 1.4.0 在 1280×720（HiDPI）的螢幕上只有 695pt 可用，面板比螢幕高、底部被切掉，
    // 所以上限一定要跟著面板所在的螢幕走，不能寫死。

    /// 分頁內容以外的高度：內距 28、標題列 ~21、分頁列 ~46、頁尾 ~16、間距 30，再留 ~19 的邊
    static let panelChrome: CGFloat = 160
    /// 分頁內容的最小上限（極矮的螢幕也至少給這麼高，寧可捲動）
    static let minContentHeight: CGFloat = 260
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
    /// 面板所在螢幕可用的高度（扣掉選單列與 Dock）；面板不能比這高，否則底部會被切掉
    @Published private(set) var screenHeight: CGFloat
    private var observers: [NSObjectProtocol] = []
    private var fallbackTimer: DispatchSourceTimer?

    /// 分頁內容最多能有多高
    var contentMaxHeight: CGFloat { max(Layout.minContentHeight, screenHeight - Layout.panelChrome) }

    init() {
        // 自我測試可以模擬別的螢幕高度（MEMORYBUTLER_SNAPSHOT_SCREEN_HEIGHT=695）
        let simulated = ProcessInfo.processInfo.environment["MEMORYBUTLER_SNAPSHOT_SCREEN_HEIGHT"]
            .flatMap(Double.init).map { CGFloat($0) }
        screenHeight = simulated ?? NSScreen.main?.visibleFrame.height ?? 800

        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
            NSApplication.didChangeScreenParametersNotification,   // 改解析度、接上／拔掉螢幕
        ]
        for name in names {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // 通知送達時視窗狀態可能還沒更新完，下一輪 run loop 再算
                DispatchQueue.main.async { [weak self] in self?.recompute() }
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
        let panelWindow = NSApp.windows.first { w in
            w.isVisible && w.frame.height > 100 && w.occlusionState.contains(.visible)
        }
        let visible = panelWindow != nil
        if visible != isVisible { isVisible = visible }
        guard ProcessInfo.processInfo.environment["MEMORYBUTLER_SNAPSHOT_SCREEN_HEIGHT"] == nil else { return }
        // 多螢幕時以面板實際出現的那一個為準
        if let h = (panelWindow?.screen ?? NSScreen.main)?.visibleFrame.height, abs(h - screenHeight) > 0.5 {
            screenHeight = h
        }
    }
}


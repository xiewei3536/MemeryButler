import Foundation
import Combine

/// 智慧自動釋放：訂閱監控資料，依三種規則自主決策，
/// 並以「自適應冷卻」避免無效的頻繁釋放；連續幾次都沒效果就暫停，不再白白折騰系統。
@MainActor
final class AutoPilot: ObservableObject {

    /// 下一次允許自動釋放的時間（冷卻中則為未來時間）
    @Published private(set) var nextAllowedAt: Date = .distantPast
    /// 自適應倍率（釋放成效差 → 拉長冷卻，最多 4 倍）
    @Published private(set) var backoffMultiplier: Double = 1.0
    /// 最近一次自動決策說明（顯示在 UI）
    @Published private(set) var lastDecision: String = L("decision.monitoring")
    /// 最近一次決策的時間（nil = 尚無決策）
    @Published private(set) var lastDecisionAt: Date?
    /// 連續無效而暫停自動釋放，直到這個時間（nil = 沒有暫停）。寫進偏好設定：重開 App 不會忘記，也不會被延長
    @Published private(set) var suspendedUntil: Date? {
        didSet { UserDefaults.standard.set(suspendedUntil?.timeIntervalSince1970 ?? 0, forKey: Self.suspendedKey) }
    }
    /// 累計評估次數（監督心跳的證據）。刻意不 @Published：每 2 秒變一次，
    /// 發布出去會讓關著的面板也跟著重算；面板看得見時由 PanelFeed 帶動重繪
    private(set) var evaluationCount: Int = 0

    /// 連續幾次自動釋放沒效果就暫停
    static let futileLimit = 3
    /// 暫停多久（期間記憶體狀況明顯好轉會提早恢復）
    static let suspendDuration: TimeInterval = 6 * 3600

    private let monitor: MemoryMonitor
    private let engine: ReleaseEngine
    private let settings: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    private var thresholdBreachedSince: Date?
    private var lastScheduledRun: Date = Date()
    /// 目前連續幾次自動釋放沒效果（同樣寫進偏好設定；1.4 第一次啟動時由歷史紀錄推回）
    private(set) var futileStreak = 0 {
        didSet { UserDefaults.standard.set(futileStreak, forKey: Self.streakKey) }
    }
    private static let streakKey = "autopilot.futileStreak"
    private static let suspendedKey = "autopilot.suspendedUntil"

    init(monitor: MemoryMonitor, engine: ReleaseEngine, settings: SettingsStore) {
        self.monitor = monitor
        self.engine = engine
        self.settings = settings

        // 暫停狀態：有存檔就用存檔；1.4 第一次啟動時由紀錄推回「最近連續幾次自動釋放沒效果」
        //（暫停起點取最近一次「自動」釋放的時間，手動釋放不算）
        let d = UserDefaults.standard
        var streak: Int
        var until: Date?
        if d.object(forKey: Self.streakKey) != nil {
            streak = d.integer(forKey: Self.streakKey)
            let t = d.double(forKey: Self.suspendedKey)
            until = t > 0 ? Date(timeIntervalSince1970: t) : nil
        } else {
            streak = Self.leadingFutileStreak(engine.events)
            if streak >= Self.futileLimit, let lastAuto = engine.events.first(where: { $0.trigger != .manual }) {
                until = lastAuto.date.addingTimeInterval(Self.suspendDuration)
            }
        }
        if let u = until, u <= Date() {
            // 啟動前就已到期：自然恢復，只留一次機會
            until = nil
            streak = min(streak, Self.futileLimit - 1)
        }
        futileStreak = streak
        suspendedUntil = until
        if until != nil {
            lastDecision = L("decision.suspended")
            lastDecisionAt = Date()
        }
        d.set(futileStreak, forKey: Self.streakKey)
        d.set(suspendedUntil?.timeIntervalSince1970 ?? 0, forKey: Self.suspendedKey)

        // 每次取樣都評估一次（2 秒節奏）
        monitor.$current
            .dropFirst()
            .sink { [weak self] sample in self?.evaluate(sample) }
            .store(in: &cancellables)

        // 核心壓力事件：即時反應，不等輪詢
        monitor.pressureEvent
            .sink { [weak self] level in
                guard let self, level != .normal else { return }
                self.attempt(trigger: .pressure, reason: LF("decision.reason.pressureSignal", level.label))
            }
            .store(in: &cancellables)

        // 使用者重新打開自動釋放 = 想再試一次：清除暫停
        settings.$autoEnabled
            .dropFirst()
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.liftSuspension() }
            .store(in: &cancellables)
    }

    var cooldownRemaining: TimeInterval { max(0, nextAllowedAt.timeIntervalSinceNow) }
    var isSuspended: Bool { (suspendedUntil ?? .distantPast) > Date() }

    /// 紀錄（新→舊）開頭連續幾筆是「自動觸發且沒效果」
    nonisolated static func leadingFutileStreak(_ events: [ReleaseEvent]) -> Int {
        var n = 0
        for e in events {
            if e.trigger == .manual { continue }   // 手動的不算，也不打斷
            guard e.reclaimed < ReleaseEngine.effectiveBytes else { break }
            n += 1
        }
        return n
    }

    // MARK: - 規則評估

    private func evaluate(_ sample: MemorySample) {
        evaluationCount += 1
        guard settings.autoEnabled, !engine.isRunning else { return }

        // 暫停中：記憶體明顯變寬裕（關了 App 或重開機）就提早恢復；
        // 時間到自然恢復則只留「一次機會」——再白跑一次就立刻再暫停，不必再白跑三次
        if suspendedUntil != nil {
            let relieved = !HealthInsight.isSwapHeavy(sample) && sample.swapUsed < sample.total / 8
                && Double(sample.available) / Double(max(sample.total, 1)) > 0.35
            if relieved {
                liftSuspension()
            } else if !isSuspended {
                liftSuspension()
                futileStreak = Self.futileLimit - 1
            }
        }

        // 規則 1：壓力達警告以上
        if settings.triggerOnPressure, sample.pressure != .normal {
            attempt(trigger: .pressure, reason: LF("decision.reason.pressure", sample.pressure.label))
            return
        }

        // 規則 2：可用記憶體低於門檻，且持續 30 秒（避免瞬間尖峰誤觸發）
        if settings.triggerOnThreshold {
            let availPct = Double(sample.available) / Double(sample.total) * 100
            if availPct < settings.thresholdPercent {
                if let since = thresholdBreachedSince {
                    if Date().timeIntervalSince(since) >= 30 {
                        thresholdBreachedSince = nil
                        attempt(trigger: .threshold,
                                reason: LF("decision.reason.threshold", Int(availPct)))
                        return
                    }
                } else {
                    thresholdBreachedSince = Date()
                }
            } else {
                thresholdBreachedSince = nil
            }
        }

        // 規則 3：定時排程
        if settings.scheduleEnabled {
            let interval = TimeInterval(settings.scheduleMinutes * 60)
            if Date().timeIntervalSince(lastScheduledRun) >= interval {
                // 記憶體寬裕時排程沒有東西可整理：記下這一輪就好，不白跑
                let availFraction = Double(sample.available) / Double(max(sample.total, 1))
                if sample.pressure == .normal, availFraction >= 0.4 {
                    lastScheduledRun = Date()
                    decide(L("decision.schedule.plenty"))
                    return
                }
                attempt(trigger: .schedule, reason: LF("decision.reason.schedule", settings.scheduleMinutes))
                return
            }
        }
    }

    // MARK: - 執行（含冷卻與守門）

    private func attempt(trigger: ReleaseTrigger, reason: String) {
        guard settings.autoEnabled, !engine.isRunning else { return }

        // 連續無效而暫停：不出手（排程也照樣記下這一輪，避免恢復後立刻補跑）
        if isSuspended {
            if trigger == .schedule { lastScheduledRun = Date() }
            decide(L("decision.suspended"))
            return
        }

        // 低耗電模式守門：使用者在省電，不要湊熱鬧
        if settings.pauseOnLowPower, ProcessInfo.processInfo.isLowPowerModeEnabled {
            decide(L("decision.lowpower"))
            return
        }

        // 過熱守門：風扇已經在狂轉，別再添柴（手動釋放不受此限）
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            decide(L("decision.thermal"))
            return
        default:
            break
        }

        // 冷卻守門
        guard Date() >= nextAllowedAt else {
            let m = Int(ceil(cooldownRemaining / 60))
            decide(LF("decision.cooling", reason, m))
            return
        }

        decide(LF("decision.acting", reason))
        if trigger == .schedule { lastScheduledRun = Date() }

        let swapInRate = monitor.current.swapInRate
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.engine.release(trigger: trigger, recentSwapInRate: swapInRate)
            self.applyAdaptiveCooldown(after: outcome)
        }
    }

    /// 自適應冷卻：釋放 < 200MB 表示系統本來就緊，加倍退避；
    /// 釋放 > 1GB 表示很有效，回復正常節奏；
    /// 因交換空間成長而煞車 = 記憶體真的不夠，再擠也只是寫磁碟，加倍退避並提醒關 App；
    /// 連續 3 次沒效果 = 這台 Mac 的記憶體是被 App 實際佔滿，不是快取：暫停 6 小時。
    private func applyAdaptiveCooldown(after outcome: ReleaseOutcome) {
        let event: ReleaseEvent
        switch outcome {
        case .busy:
            return
        case .skipped(let why):
            // 出手也沒用：拉長冷卻避免每 2 秒空轉，並直說只有關 App 有用
            backoffMultiplier = min(4.0, backoffMultiplier * 2)
            decide(L("decision.skip.\(why.rawValue)"))
            nextAllowedAt = Date().addingTimeInterval(settings.cooldownMinutes * 60 * backoffMultiplier)
            return
        case .released(let e):
            event = e
        }

        // 連一塊壓載都吃不進去 = 系統忙到無法協助,2 分鐘後短冷卻重試(不算失敗、不計入無效)
        if (event.ballast ?? 0) < (64 << 20) {
            decide(L("decision.tooTight"))
            nextAllowedAt = Date().addingTimeInterval(120)
            return
        }

        futileStreak = event.reclaimed < ReleaseEngine.effectiveBytes ? futileStreak + 1 : 0
        if futileStreak >= Self.futileLimit {
            suspendedUntil = Date().addingTimeInterval(Self.suspendDuration)
            backoffMultiplier = 4.0
            decide(L("decision.suspended"))
            return
        }
        if event.stopReason == .swapGrowth {
            backoffMultiplier = min(4.0, backoffMultiplier * 2)
            decide(LF("decision.swapLimited", Fmt.bytes(event.reclaimed)))
            nextAllowedAt = Date().addingTimeInterval(settings.cooldownMinutes * 60 * backoffMultiplier)
            return
        }
        if event.reclaimed < (200 << 20) {
            backoffMultiplier = min(4.0, backoffMultiplier * 2)
            decide(LF("decision.limited", Fmt.bytes(event.reclaimed)))
        } else {
            if event.reclaimed > (1 << 30) { backoffMultiplier = 1.0 }
            decide(LF("decision.freed", Fmt.bytes(event.reclaimed)))
        }
        let cooldown = settings.cooldownMinutes * 60 * backoffMultiplier
        nextAllowedAt = Date().addingTimeInterval(cooldown)
    }

    /// 同一句話重複時不重新發布：壓力警告期間每 2 秒評估一次，每次都發布會讓 UI 每 2 秒重算一次。
    /// 但隔了 5 分鐘以上又做出同樣的決定（例如每小時的排程），時間要更新，不然看起來像舊消息
    private func decide(_ text: String) {
        let now = Date()
        if text == lastDecision, let at = lastDecisionAt, now.timeIntervalSince(at) < 300 { return }
        lastDecision = text
        lastDecisionAt = now
    }

    private func liftSuspension() {
        let wasSuspended = suspendedUntil != nil
        guard wasSuspended || futileStreak > 0 else { return }
        suspendedUntil = nil
        futileStreak = 0
        backoffMultiplier = 1.0
        if wasSuspended { decide(L("decision.resumed")) }
    }

    /// 其他模組的自主動作（例如自動把失控程序降到背景）也寫進同一條狀態列
    func note(_ text: String) { decide(text) }

    /// 手動釋放後也重置冷卻計時（避免手動後緊接著自動又跑一次）；
    /// 手動釋放確實回收到不少 = 情況變了，解除暫停
    func noteManualRelease(_ event: ReleaseEvent) {
        nextAllowedAt = Date().addingTimeInterval(settings.cooldownMinutes * 60)
        if event.reclaimed >= (256 << 20) { liftSuspension() }
    }
}

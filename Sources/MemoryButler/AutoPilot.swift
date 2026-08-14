import Foundation
import Combine

/// 智慧自動釋放：訂閱監控資料，依三種規則自主決策，
/// 並以「自適應冷卻」避免無效的頻繁釋放。
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
    /// 累計評估次數（監督心跳的證據）
    @Published private(set) var evaluationCount: Int = 0

    private let monitor: MemoryMonitor
    private let engine: ReleaseEngine
    private let settings: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    private var thresholdBreachedSince: Date?
    private var lastScheduledRun: Date = Date()

    init(monitor: MemoryMonitor, engine: ReleaseEngine, settings: SettingsStore) {
        self.monitor = monitor
        self.engine = engine
        self.settings = settings

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
    }

    var cooldownRemaining: TimeInterval { max(0, nextAllowedAt.timeIntervalSinceNow) }

    // MARK: - 規則評估

    private func evaluate(_ sample: MemorySample) {
        evaluationCount += 1
        guard settings.autoEnabled, !engine.isRunning else { return }

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
                attempt(trigger: .schedule, reason: LF("decision.reason.schedule", settings.scheduleMinutes))
                return
            }
        }
    }

    // MARK: - 執行（含冷卻與守門）

    private func attempt(trigger: ReleaseTrigger, reason: String) {
        guard settings.autoEnabled, !engine.isRunning else { return }

        // 低耗電模式守門：使用者在省電，不要湊熱鬧
        if settings.pauseOnLowPower, ProcessInfo.processInfo.isLowPowerModeEnabled {
            decide(L("decision.lowpower"))
            return
        }

        // 冷卻守門
        guard Date() >= nextAllowedAt else {
            let m = Int(ceil(cooldownRemaining / 60))
            decide(LF("decision.cooling", reason, m))
            return
        }

        decide(LF("decision.acting", reason))
        if trigger == .schedule { lastScheduledRun = Date() }

        Task { [weak self] in
            guard let self else { return }
            let event = await self.engine.release(trigger: trigger)
            self.applyAdaptiveCooldown(after: event)
        }
    }

    /// 自適應冷卻：釋放 < 200MB 表示系統本來就緊，加倍退避；
    /// 釋放 > 1GB 表示很有效，回復正常節奏。
    private func applyAdaptiveCooldown(after event: ReleaseEvent?) {
        guard let event else { return }
        // 連一塊壓載都吃不進去 = 系統忙到無法協助,2 分鐘後短冷卻重試(不算失敗)
        if (event.ballast ?? 0) < (128 << 20) {
            decide(L("decision.tooTight"))
            nextAllowedAt = Date().addingTimeInterval(120)
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

    private func decide(_ text: String) {
        lastDecision = text
        lastDecisionAt = Date()
    }

    /// 手動釋放後也重置冷卻計時（避免手動後緊接著自動又跑一次）
    func noteManualRelease() {
        nextAllowedAt = Date().addingTimeInterval(settings.cooldownMinutes * 60)
    }
}

import Foundation

// MARK: - 觸發來源與紀錄

enum ReleaseTrigger: String, Codable {
    case manual, pressure, threshold, schedule

    var displayName: String { L("trigger.\(rawValue)") }

    var symbol: String {
        switch self {
        case .manual:    return "hand.tap.fill"
        case .pressure:  return "exclamationmark.triangle.fill"
        case .threshold: return "gauge.with.needle.fill"
        case .schedule:  return "clock.fill"
        }
    }
}

/// 這一趟為什麼停下來（決定後續的冷卻策略與給使用者的說明）
enum StopReason: String, Codable {
    case cap               // 達到壓載總量上限
    case deadline          // 達到時間上限
    case critical          // 核心壓力緊繃，立刻收手
    case warnDwell         // 在警告區停留夠久，回收已收斂
    case swapGrowth        // 交換空間開始成長：再擠只會把別的 App 寫進磁碟
    case compressorGrowth  // 壓縮池單趟成長已達上限：核心已壓完一波，再逼就要換出
    case compressorCap     // 壓縮池已接近會觸發換出的規模
    case thermal           // 機器過熱
    case allocFailed       // 連一塊壓載都拿不到
}

/// 起跑前就知道出手只會害到使用者的情況：不出手、不記錄，但要老實說
enum SkipReason: String {
    case compressorFull   // 壓縮池已佈實體記憶體 12% 以上：再施壓只會把別的 App 寫進磁碟
    case swapping         // 交換空間此刻正在成長：系統已經在寫磁碟，別添亂
    case critical         // 壓力已經緊繃
}

enum ReleaseOutcome {
    case released(ReleaseEvent)
    case skipped(SkipReason)
    case busy
}

struct ReleaseEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    let trigger: ReleaseTrigger
    let reclaimed: Int64          // 釋放出的位元組（可能為 0）
    let duration: TimeInterval
    let ballast: Int64?           // 實際吃進的壓載量（判斷這一趟有沒有真的做功）
    let stopReason: StopReason?   // 1.2 新增；舊紀錄為 nil
    let swapDelta: Int64?         // 釋放期間交換空間變化（>0 代表有頁面被寫到磁碟）
}

// MARK: - 引擎狀態

enum EngineState: Equatable {
    case idle
    case running(progress: Double)   // 0...1 粗略進度
    case done(reclaimed: Int64)
    case skipped(SkipReason)         // 起跑前判定出手無益，短暫顯示原因
}

// MARK: - 釋放引擎
//
// 原理：以受控速度向核心索取匿名記憶體並實際觸碰每一頁（內容不可壓縮），
// 迫使 XNU 立即丟棄可清除快取、壓縮不活躍 App 的閒置頁；隨後一次性歸還，
// 系統便多出真正可用的閒置記憶體。全程免 root。
//
// 8GB 機器實測得到的核心事實：
//   • 核心是「一波一波」壓縮的——free 見底後會一次壓 0.8～1.1GB，過程中 malloc 被擋住，
//     我們的檢查只能在那一波之後發生。
//   • 壓縮池達到實體記憶體約 29% 時，核心開始把舊的壓縮段寫進磁碟（swap），
//     被寫出去的是「其他 App」的記憶體，切回去就卡——這是記憶體清理工具反而害人的機制。
//   • 沒有任何煞車時「釋放 1.9GB」= swap +1.8GB；只有 swap 煞車時停手後核心仍續寫 ~0.4GB；
//     加上壓縮池煞車（本版）後，停手後 4 秒內 swap 成長為 0。
//
// 因此本版的安全機制：
//   起跑前：壓縮池 > RAM 12%、swap 正在成長、壓力緊繃 → 不出手，直接告知使用者只有關 App 有用
//   迴圈中（每 64MB 檢查一次）：壓力緊繃 / swap 任何成長 / 壓縮池絕對 > 24% /
//   壓縮池單趟成長 > 3% / 過熱 → 立刻歸還；警告區停留 2.5 秒 → 收手；總量與時間上限

@MainActor
final class ReleaseEngine: ObservableObject {

    @Published private(set) var state: EngineState = .idle
    @Published private(set) var events: [ReleaseEvent] = []
    @Published private(set) var lastRelease: ReleaseEvent?

    /// 壓縮池已佈實體記憶體多少比例就不出手（8GB ≈ 983MB）
    nonisolated static let preflightCompressorFraction = 0.12
    /// 單趟允許壓縮池成長的比例（8GB ≈ 245MB；最少 128MB）
    nonisolated static let compressorGrowthCapFraction = 0.03
    /// 壓縮池絕對上限（8GB 實測 ≥ 29% 開始換出，留足餘裕）
    nonisolated static let compressorHardCapFraction = 0.24

    private let eventsKey = "releaseEvents"
    private let eventsLimit = 60
    private var generation = 0   // 讓「幾秒後回到 idle」的計時器不會誤殺後來的新狀態

    init() {
        if let data = UserDefaults.standard.data(forKey: eventsKey),
           let saved = try? JSONDecoder().decode([ReleaseEvent].self, from: data) {
            events = saved
            lastRelease = saved.first
        }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    @discardableResult
    func release(trigger: ReleaseTrigger) async -> ReleaseOutcome {
        guard !isRunning else { return .busy }

        let started = Date()
        generation += 1
        state = .running(progress: 0.02)

        // 起跑前檢查：確定出手不會害到使用者。swap 是否「正在」成長要看兩次讀值。
        let before = MemoryReader.sample()
        let swapProbe = MemoryReader.swapUsedBytes()
        try? await Task.sleep(nanoseconds: 250_000_000)
        let swapGrew = MemoryReader.swapUsedBytes() > swapProbe
        if let skip = Self.preflight(before, swapGrew: swapGrew) {
            setTransient(.skipped(skip), seconds: 6)
            return .skipped(skip)
        }
        state = .running(progress: 0.05)

        let physical = before.total
        // 單次最多索取實體記憶體的 90%（核心會邊回收邊給，實際遠低於此）
        let maxBallast = physical / 10 * 9
        let deadline = started.addingTimeInterval(25)
        // 手動釋放是使用者在等；自動釋放則退到 utility，不跟使用者正在做的事搶 CPU
        let priority: TaskPriority = trigger == .manual ? .userInitiated : .utility
        let limits = BallastLimits(
            maxBallast: maxBallast,
            physical: physical,
            deadline: deadline,
            compressorStart: before.compressed,
            compressorGrowthCap: max(128 << 20, UInt64(Double(physical) * Self.compressorGrowthCapFraction)),
            compressorHardCap: UInt64(Double(physical) * Self.compressorHardCapFraction)
        )

        // 進度以 AsyncStream 回傳主執行緒，背景閉包完全不捕獲 self（嚴格併發檢查安全）
        let (progressStream, progressCont) = AsyncStream.makeStream(of: Double.self)
        let progressTask = Task { @MainActor [weak self] in
            for await p in progressStream {
                if let self, self.isRunning { self.state = .running(progress: p) }
            }
        }

        // 重活丟到背景執行緒；回傳實際吃進的壓載量、停止原因、交換空間變化
        let result: BallastResult = await Task.detached(priority: priority) {
            Self.runBallast(limits, progress: progressCont)
        }.value
        progressTask.cancel()

        state = .running(progress: 0.95)
        // 歸還後 free 計數約需 0.5～1 秒才會反映，等足再統計
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        let after = MemoryReader.sample()
        // 統計口徑：閒置(free)記憶體的淨增量。
        // 不能用「可用(=總量-已用)」——被清出的快取本來就算在可用裡，差值恆為 0
        let reclaimed = max(0, Int64(after.free) - Int64(before.free))
        let event = ReleaseEvent(
            id: UUID(), date: started, trigger: trigger,
            reclaimed: reclaimed, duration: Date().timeIntervalSince(started),
            ballast: Int64(result.allocated),
            stopReason: result.reason,
            swapDelta: result.swapDelta
        )

        events.insert(event, at: 0)
        if events.count > eventsLimit { events.removeLast(events.count - eventsLimit) }
        lastRelease = event
        persist()

        setTransient(.done(reclaimed: reclaimed), seconds: 4)
        return .released(event)
    }

    /// 起跑前判定：這一刻出手會不會只是把別的 App 寫進磁碟
    nonisolated static func preflight(_ s: MemorySample, swapGrew: Bool) -> SkipReason? {
        if s.pressure == .critical { return .critical }
        if swapGrew { return .swapping }
        if s.total > 0, Double(s.compressed) > Double(s.total) * preflightCompressorFraction {
            return .compressorFull
        }
        return nil
    }

    // MARK: 壓載迴圈（純函式，在背景執行緒跑）

    struct BallastLimits: Sendable {
        let maxBallast: UInt64
        let physical: UInt64
        let deadline: Date
        let compressorStart: UInt64
        let compressorGrowthCap: UInt64
        let compressorHardCap: UInt64
    }

    struct BallastResult: Sendable {
        let allocated: UInt64
        let reason: StopReason
        let swapDelta: Int64
    }

    nonisolated private static func runBallast(
        _ limits: BallastLimits, progress: AsyncStream<Double>.Continuation
    ) -> BallastResult {
        let pageSize = Int(MemoryReader.pageSize)
        let chunkSize = 64 << 20                 // 64MB / 塊：煞車後最多只多吃一塊
        // 交換空間平時穩定到 byte，一有成長就是核心開始把壓縮段寫進磁碟
        let swapTolerance: UInt64 = 4 << 20
        let swapStart = MemoryReader.swapUsedBytes()

        var chunks: [UnsafeMutableRawPointer] = []
        var allocated: UInt64 = 0
        var warnSince: Date?
        var reason: StopReason = .cap

        // 不可壓縮的填充：一頁隨機範本複製到每一頁，再蓋上頁序號。
        // 若用均勻位元組，核心會直接壓縮壓載本身（幾乎零成本）而不去回收其他記憶體；
        // 若每頁都跑 arc4random，CPU 成本高 8 倍以上（實測 134ms vs 15ms / 128MB）。
        guard let template = malloc(pageSize) else {
            progress.finish()
            return BallastResult(allocated: 0, reason: .allocFailed, swapDelta: 0)
        }
        arc4random_buf(template, pageSize)

        defer {
            for c in chunks { free(c) }
            free(template)
            progress.finish()
        }

        while true {
            if Date() >= limits.deadline { reason = .deadline; break }
            if allocated >= limits.maxBallast { reason = .cap; break }

            let level = MemoryReader.pressureLevel()
            // 煞車 1：壓力緊繃 → 立刻收手
            if level == .critical { reason = .critical; break }
            // 煞車 2：交換空間開始成長 → 立刻收手（再擠只是把別的 App 寫進磁碟）
            if MemoryReader.swapUsedBytes() > swapStart &+ swapTolerance { reason = .swapGrowth; break }
            // 煞車 3：壓縮池——絕對規模接近會換出的門檻，或這一趟已讓核心壓完一波
            let compressed = MemoryReader.compressedBytes()
            if compressed > limits.compressorHardCap { reason = .compressorCap; break }
            if compressed > limits.compressorStart &+ limits.compressorGrowthCap { reason = .compressorGrowth; break }
            // 煞車 4：機器過熱，不再添柴
            if ProcessInfo.processInfo.thermalState == .critical { reason = .thermal; break }
            // 煞車 5：進入「警告」區後再持續 2.5 秒——這段時間才是核心
            // 真正回收快取、壓縮閒置 App 的時候，太早停手等於白跑
            if level == .warning {
                if let w = warnSince {
                    if Date().timeIntervalSince(w) >= 2.5 { reason = .warnDwell; break }
                } else {
                    warnSince = Date()
                }
            } else {
                warnSince = nil
            }

            guard let p = malloc(chunkSize) else { reason = .allocFailed; break }
            var offset = 0
            var pageIndex: UInt64 = allocated / UInt64(pageSize)
            while offset < chunkSize {
                memcpy(p + offset, template, pageSize)
                p.storeBytes(of: pageIndex, toByteOffset: offset, as: UInt64.self)
                offset += pageSize
                pageIndex &+= 1
            }
            chunks.append(p)
            allocated &+= UInt64(chunkSize)

            progress.yield(min(0.9, 0.05 + Double(allocated) / Double(limits.physical) * 1.2))
            usleep(15_000)   // 讓回收管線跟上、UI 保持流暢
        }

        // 只有在「回收已收斂 / 到達上限」時多持有片刻讓核心結算；
        // 任何一種煞車觸發都立刻歸還，一毫秒都不多佔
        switch reason {
        case .cap, .deadline, .warnDwell: usleep(300_000)
        default: break
        }

        let swapDelta = Int64(MemoryReader.swapUsedBytes()) - Int64(swapStart)
        return BallastResult(allocated: allocated, reason: reason, swapDelta: swapDelta)
    }

    // MARK: 狀態與持久化

    /// 顯示一個短暫狀態（done / skipped），幾秒後回到 idle；若期間有新動作則不干涉
    private func setTransient(_ s: EngineState, seconds: UInt64) {
        generation += 1
        let gen = generation
        state = s
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, self.generation == gen else { return }
            self.state = .idle
        }
    }

    func clearEvents() {
        events.removeAll()
        lastRelease = nil
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: eventsKey)
        }
    }
}

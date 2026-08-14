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

struct ReleaseEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    let trigger: ReleaseTrigger
    let reclaimed: Int64          // 釋放出的位元組（可能為 0）
    let duration: TimeInterval
    let ballast: Int64?           // 實際吃進的壓載量（判斷這一趟有沒有真的做功）
}

// MARK: - 引擎狀態

enum EngineState: Equatable {
    case idle
    case running(progress: Double)   // 0...1 粗略進度
    case done(reclaimed: Int64)
}

// MARK: - 釋放引擎
//
// 原理：以受控速度向核心索取大量匿名記憶體並實際觸碰每一頁，
// 迫使 XNU 的 memorystatus / compressor 立即回收閒置頁面、
// 壓縮不活躍 App 的記憶體、丟棄可清除快取；隨後一次性歸還，
// 系統便多出大量真正可用的閒置記憶體。全程免 root。
// 安全機制：緊繃壓力立即煞車、警告區限時 2.5 秒、總量上限、時間上限。

@MainActor
final class ReleaseEngine: ObservableObject {

    @Published private(set) var state: EngineState = .idle
    @Published private(set) var events: [ReleaseEvent] = []
    @Published private(set) var lastRelease: ReleaseEvent?

    private let eventsKey = "releaseEvents"
    private let eventsLimit = 60

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
    func release(trigger: ReleaseTrigger) async -> ReleaseEvent? {
        guard !isRunning else { return nil }

        let started = Date()
        let before = MemoryReader.sample()
        state = .running(progress: 0.05)

        let physical = before.total
        // 單次最多索取實體記憶體的 90%（核心會邊回收邊給，實際遠低於此）
        let maxBallast = physical / 10 * 9
        let chunkSize = 128 << 20            // 128MB / 塊
        let deadline = started.addingTimeInterval(25)

        // 進度以 AsyncStream 回傳主執行緒，背景閉包完全不捕獲 self（嚴格併發檢查安全）
        let (progressStream, progressCont) = AsyncStream.makeStream(of: Double.self)
        let progressTask = Task { @MainActor [weak self] in
            for await p in progressStream {
                if let self, self.isRunning { self.state = .running(progress: p) }
            }
        }

        // 重活丟到背景執行緒;回傳實際吃進的壓載量
        let ballastAllocated: UInt64 = await Task.detached(priority: .userInitiated) {
            var chunks: [UnsafeMutableRawPointer] = []
            var allocated: UInt64 = 0
            var warnSince: Date?

            defer {
                for c in chunks { free(c) }
                progressCont.finish()
            }

            while Date() < deadline && allocated < maxBallast {
                let level = MemoryReader.pressureLevel()
                // 煞車 1：壓力緊繃 → 立刻收手
                if level == .critical { break }
                // 煞車 2：進入「警告」區後再持續 2.5 秒——這段時間才是核心
                // 真正回收快取、壓縮閒置 App 的時候，太早停手等於白跑
                if level == .warning {
                    if let w = warnSince {
                        if Date().timeIntervalSince(w) >= 2.5 { break }
                    } else {
                        warnSince = Date()
                    }
                } else {
                    warnSince = nil
                }

                guard let p = malloc(chunkSize) else { break }
                // 不可壓縮的隨機填充:若用均勻位元組,核心會直接壓縮壓載本身
                //（幾乎零成本）而不去回收其他記憶體,整趟就白費了
                arc4random_buf(p, chunkSize)
                chunks.append(p)
                allocated &+= UInt64(chunkSize)

                progressCont.yield(min(0.9, 0.05 + Double(allocated) / Double(physical) * 1.2))
                usleep(15_000)   // 讓回收管線跟上、UI 保持流暢
            }

            // 高壓下多持有片刻讓回收收斂，再一次性歸還（defer 執行 free）
            usleep(400_000)
            return allocated
        }.value
        progressTask.cancel()

        state = .running(progress: 0.95)
        // 歸還後給核心一點時間結算頁面
        try? await Task.sleep(nanoseconds: 400_000_000)

        let after = MemoryReader.sample()
        // 統計口徑:閒置(free)記憶體的淨增量。
        // 不能用「可用(=總量-已用)」——被清出的快取本來就算在可用裡,差值恆為 0
        let reclaimed = max(0, Int64(after.free) - Int64(before.free))
        let event = ReleaseEvent(
            id: UUID(), date: started, trigger: trigger,
            reclaimed: reclaimed, duration: Date().timeIntervalSince(started),
            ballast: Int64(ballastAllocated)
        )

        events.insert(event, at: 0)
        if events.count > eventsLimit { events.removeLast(events.count - eventsLimit) }
        lastRelease = event
        persist()

        state = .done(reclaimed: reclaimed)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if let self, case .done = self.state { self.state = .idle }
        }
        return event
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

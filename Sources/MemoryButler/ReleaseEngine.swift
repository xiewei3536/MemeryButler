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
// 安全機制：保底水位、壓力煞車、總量上限、時間上限。

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
        // 保底閒置水位：至少 300MB 或總量 4%，避免把系統逼進 critical 深水區
        let floorBytes = max(300 << 20, physical / 25)
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

        // 重活丟到背景執行緒
        await Task.detached(priority: .userInitiated) {
            var chunks: [UnsafeMutableRawPointer] = []
            var allocated: UInt64 = 0

            defer {
                for c in chunks { free(c) }
                progressCont.finish()
            }

            while Date() < deadline && allocated < maxBallast {
                // 煞車 1：閒置記憶體已被壓到保底水位 → 核心已完成大掃除
                if MemoryReader.freeBytes() < floorBytes { break }
                // 煞車 2：壓力達到緊繃 → 立刻收手
                if MemoryReader.pressureLevel() == .critical { break }

                guard let p = malloc(chunkSize) else { break }
                // 觸碰每一頁強制實際佔用（memset 整塊最快也最徹底）
                memset(p, 0x5A, chunkSize)
                chunks.append(p)
                allocated &+= UInt64(chunkSize)

                progressCont.yield(min(0.9, 0.05 + Double(allocated) / Double(physical) * 1.2))
                usleep(15_000)   // 讓 compressor 跟上、UI 保持流暢
            }

            // 短暫停留讓回收收斂，再一次性歸還（defer 執行 free）
            usleep(250_000)
        }.value
        progressTask.cancel()

        state = .running(progress: 0.95)
        // 歸還後給核心一點時間結算頁面
        try? await Task.sleep(nanoseconds: 400_000_000)

        let after = MemoryReader.sample()
        let reclaimed = max(0, Int64(after.available) - Int64(before.available))
        let event = ReleaseEvent(
            id: UUID(), date: started, trigger: trigger,
            reclaimed: reclaimed, duration: Date().timeIntervalSince(started)
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

import Foundation
import Combine

/// 持續監控系統記憶體，維護歷史曲線並廣播壓力事件。
@MainActor
final class MemoryMonitor: ObservableObject {

    @Published private(set) var current: MemorySample = .zero
    @Published private(set) var history: [MemorySample] = []

    /// 核心壓力事件（比輪詢更即時），AutoPilot 會訂閱
    let pressureEvent = PassthroughSubject<PressureLevel, Never>()

    private var timer: DispatchSourceTimer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var last: MemorySample?
    private let interval: TimeInterval = 2.0
    private let historyLimit = 150   // 2 秒 × 150 = 5 分鐘
    /// 換頁速率的平滑時間常數：一次切換 App 的換入尖峰約持續 8 秒才退到門檻下，
    /// 不會因為單一取樣忽高忽低讓判讀閃爍
    private let rateTau: TimeInterval = 10

    func start() {
        guard timer == nil else { return }

        refresh()

        let t = DispatchSource.makeTimerSource(queue: .main)
        // 給核心一點合併計時器的空間（省電），2 秒節奏不需要精準到毫秒
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
        t.setEventHandler { [weak self] in self?.refresh() }
        t.resume()
        timer = t

        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let level = MemoryReader.pressureLevel()
            self.refresh()
            self.pressureEvent.send(level)
        }
        src.resume()
        pressureSource = src
    }

    func refresh() {
        var sample = MemoryReader.sample()
        if let prev = last {
            let dt = sample.date.timeIntervalSince(prev.date)
            if dt > 0.2 {
                let inRate = Double(sample.swapInsTotal >= prev.swapInsTotal ? sample.swapInsTotal - prev.swapInsTotal : 0) / dt
                let outRate = Double(sample.swapOutsTotal >= prev.swapOutsTotal ? sample.swapOutsTotal - prev.swapOutsTotal : 0) / dt
                let k = 1 - exp(-dt / rateTau)
                sample.swapInRate = prev.swapInRate + (inRate - prev.swapInRate) * k
                sample.swapOutRate = prev.swapOutRate + (outRate - prev.swapOutRate) * k
            } else {
                // 壓力事件緊接在定時取樣後：區間太短算不準，沿用上一筆
                sample.swapInRate = prev.swapInRate
                sample.swapOutRate = prev.swapOutRate
            }
        }
        last = sample
        current = sample
        history.append(sample)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }
}

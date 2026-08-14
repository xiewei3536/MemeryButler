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
    private let interval: TimeInterval = 2.0
    private let historyLimit = 150   // 2 秒 × 150 = 5 分鐘

    func start() {
        guard timer == nil else { return }

        refresh()

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval)
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
        let sample = MemoryReader.sample()
        current = sample
        history.append(sample)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }
}

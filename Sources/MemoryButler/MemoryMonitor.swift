import Foundation
import Combine

/// 核心壓力通知即時處理；面板隱藏／低耗電時降低輪詢，睡眠期間不取樣。
@MainActor
final class MemoryMonitor: ObservableObject {
    @Published private(set) var current: MemorySample = .zero
    @Published private(set) var history: [MemorySample] = []
    let pressureEvent = PassthroughSubject<PressureLevel, Never>()

    private var timer: DispatchSourceTimer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var last: MemorySample?
    private var visible = false
    private var lowPower = false
    private var suspended = false
    private(set) var samplingInterval: TimeInterval = 6

    func start() {
        guard pressureSource == nil else { return }
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self, !self.suspended else { return }
            self.refresh()
            self.pressureEvent.send(self.current.pressure)
        }
        src.resume()
        pressureSource = src
        refresh()
        scheduleTimer()
    }

    func configure(visible: Bool, lowPower: Bool) {
        let opening = visible && !self.visible
        self.visible = visible
        self.lowPower = lowPower
        if opening && !suspended { refresh() }
        scheduleTimer()
    }

    func suspend() {
        suspended = true
        timer?.cancel()
        timer = nil
        last = nil
    }

    func resume() {
        suspended = false
        last = nil
        refresh()
        scheduleTimer()
    }

    private func scheduleTimer() {
        guard pressureSource != nil, !suspended else { return }
        let interval = MonitoringPolicy.memoryInterval(visible: visible, lowPower: lowPower, pressure: current.pressure)
        guard timer == nil || samplingInterval != interval else { return }
        samplingInterval = interval
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
        t.setEventHandler { [weak self] in self?.refresh() }
        t.resume()
        timer = t
    }

    func refresh() {
        guard !suspended else { return }
        let sample = Self.smoothed(MemoryReader.sample(), since: last)
        last = sample
        current = sample
        // 歷史依實際時間裁切，取樣頻率改變後仍然是最近 5 分鐘，而非忽然變成 15 分鐘。
        var next = history.filter { sample.date.timeIntervalSince($0.date) < MonitoringPolicy.historyDuration }
        if let recent = next.last, sample.date.timeIntervalSince(recent.date) < 1 {
            next[next.count - 1] = sample
        } else {
            next.append(sample)
        }
        history = Array(next.suffix(160))
        scheduleTimer()
    }

    /// 太短的區間沿用速率；睡眠、時鐘回撥或長空窗後清除舊尖峰，不把睡前的卡頓帶到睡醒後。
    nonisolated static func smoothed(_ input: MemorySample, since previous: MemorySample?) -> MemorySample {
        var sample = input
        guard let prev = previous else { return sample }
        let dt = sample.date.timeIntervalSince(prev.date)
        guard dt >= 0, dt <= 30 else { return sample }
        guard dt > 0.2 else {
            sample.swapInRate = prev.swapInRate
            sample.swapOutRate = prev.swapOutRate
            return sample
        }
        let inRate = Double(sample.swapInsTotal >= prev.swapInsTotal ? sample.swapInsTotal - prev.swapInsTotal : 0) / dt
        let outRate = Double(sample.swapOutsTotal >= prev.swapOutsTotal ? sample.swapOutsTotal - prev.swapOutsTotal : 0) / dt
        let k = 1 - exp(-dt / 10)
        sample.swapInRate = prev.swapInRate + (inRate - prev.swapInRate) * k
        sample.swapOutRate = prev.swapOutRate + (outRate - prev.swapOutRate) * k
        return sample
    }
}

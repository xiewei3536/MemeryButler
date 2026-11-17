import Foundation
import Darwin

/// 面板隱藏時少喚醒 CPU；壓力事件仍由核心即時通知，不靠密集輪詢救急。
enum MonitoringPolicy {
    static func memoryInterval(visible: Bool, lowPower: Bool, pressure: PressureLevel) -> TimeInterval {
        if pressure != .normal { return 2 }
        if visible { return lowPower ? 4 : 2 }
        return lowPower ? 10 : 6
    }

    static func processInterval(visible: Bool, lowPower: Bool) -> TimeInterval {
        lowPower ? 30 : (visible ? 10 : 15)
    }

    static let historyDuration: TimeInterval = 5 * 60
    static let foregroundGrace: TimeInterval = 2 * 60
}

/// PID 會重用，累計 CPU 也會因程序結束而消失。先逐程序核對身分、取差，再依 App 加總，
/// 不能直接相減整組累計值（新分頁加入會暴增、舊分頁結束會把其他分頁的 CPU 抵銷）。
struct ProcessCPUCounter: Equatable, Sendable {
    let started: UInt64
    let time: UInt64

    func delta(since previous: ProcessCPUCounter) -> UInt64? {
        guard started > 0, started == previous.started, time >= previous.time else { return nil }
        return time - previous.time
    }
}

struct ProcessCPUTracker {
    private var previous: [pid_t: ProcessCPUCounter] = [:]
    private var sampledAt: TimeInterval?

    /// 用單調時鐘算速率；第一輪、睡眠後或過長的空窗只重建基準，不猜測當下負載。
    mutating func rates(for processes: [ProcessScanner.ProcCPU], at now: TimeInterval,
                        maxGap: TimeInterval = 75) -> [pid_t: Double]? {
        var next: [pid_t: ProcessCPUCounter] = [:]
        next.reserveCapacity(processes.count)
        for p in processes { next[p.pid] = ProcessCPUCounter(started: p.startTime, time: p.cpuTime) }
        defer { previous = next; sampledAt = now }
        guard let before = sampledAt else { return nil }
        let dt = now - before
        guard dt >= 0.2, dt <= maxGap else { return nil }
        var result: [pid_t: Double] = [:]
        result.reserveCapacity(processes.count)
        for p in processes {
            guard let old = previous[p.pid], let delta = next[p.pid]?.delta(since: old) else { continue }
            result[p.pid] = Double(delta) / 1e9 / dt
        }
        return result
    }

    mutating func reset() {
        previous.removeAll(keepingCapacity: true)
        sampledAt = nil
    }
}

/// 切離 App 的當下才開始緩衝，不能用上次輪詢時間代替（否則會少保護一個取樣週期）。
struct ForegroundProtection {
    private var current: pid_t?
    private var lastUsed: [pid_t: Date] = [:]

    mutating func observe(_ pid: pid_t?, at now: Date) {
        if let current { lastUsed[current] = now }
        if let pid { lastUsed[pid] = now }
        current = pid
        lastUsed = lastUsed.filter { now.timeIntervalSince($0.value) < MonitoringPolicy.foregroundGrace }
    }

    func protects(_ pid: pid_t, frontmost: pid_t?, at now: Date) -> Bool {
        if pid == frontmost { return true }
        return lastUsed[pid].map { now.timeIntervalSince($0) < MonitoringPolicy.foregroundGrace } ?? false
    }
}

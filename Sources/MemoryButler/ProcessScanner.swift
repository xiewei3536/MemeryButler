import Foundation
import AppKit
import Darwin

// MARK: - 誰在佔用記憶體
//
// 8GB 機器真正有效的解法是「關掉最耗記憶體的 App」，不是釋放。
// 這裡把所有程序依「負責的 App」歸併（Chrome 的幾十個輔助程序算給 Chrome、
// Safari 的分頁算給 Safari），用的是活動監視器同一套歸屬邏輯與同一個「記憶體」口徑。

/// 一個使用者看得懂的單位：一個 App（含它所有輔助程序），或全部背景程序的總和
struct AppMemoryUsage: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let footprint: UInt64
    let processCount: Int
    let app: NSRunningApplication?   // nil = 背景與系統程序（不提供結束）
    let cpuFraction: Double?         // 兩次掃描之間的 CPU 佈用（1.0 = 一顆核心跑滿）；第一次為 nil
}

enum ProcessScanner {

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    /// 活動監視器用來把輔助程序歸給母 App 的系統函式；拿不到就退回父程序鏈 + 路徑判斷
    private static let responsiblePid: ResponsibleFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                              "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    struct RunningApp {
        let pid: pid_t
        let bundlePath: String?
        let name: String
        let icon: NSImage?
        let app: NSRunningApplication
    }

    /// 只傳值型別進背景執行緒（嚴格併發檢查安全）
    struct ScanInput: Sendable {
        let pids: [pid_t]            // 與 bundlePaths 平行，索引即 App 編號
        let bundlePaths: [String]
        let selfPid: pid_t
    }

    struct ScanOutput: Sendable {
        var footprints: [UInt64]
        var counts: [Int]
        var cpuTimes: [UInt64]           // 累計 CPU 時間（ns），依 App 加總
        var otherFootprint: UInt64 = 0
        var otherCount: Int = 0
        var otherCpuTime: UInt64 = 0
        var selfFootprint: UInt64 = 0
    }

    /// rusage 的 CPU 時間是 mach 絕對時間單位，Apple Silicon 需換算成 ns
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(max(tb.denom, 1)))
    }()

    /// 主執行緒：拍一張目前 App 的快照（一般 App 與選單列 App；排除自己與純背景程序）
    @MainActor
    static func snapshotApps() -> [RunningApp] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier > 0, app.processIdentifier != me else { return nil }
            switch app.activationPolicy {
            case .regular, .accessory: break
            default: return nil
            }
            return RunningApp(pid: app.processIdentifier,
                              bundlePath: app.bundleURL?.path,
                              name: app.localizedName ?? app.bundleIdentifier ?? "?",
                              icon: app.icon,
                              app: app)
        }
    }

    /// 背景執行緒：列舉所有 pid、讀取實體佔用、歸併到 App（實測 650 個程序約 5ms）
    nonisolated static func scan(_ input: ScanInput) -> ScanOutput {
        var out = ScanOutput(footprints: Array(repeating: 0, count: input.pids.count),
                             counts: Array(repeating: 0, count: input.pids.count),
                             cpuTimes: Array(repeating: 0, count: input.pids.count))

        var byPid: [pid_t: Int] = [:]
        for (i, pid) in input.pids.enumerated() { byPid[pid] = i }
        var byBundle: [String: Int] = [:]
        for (i, path) in input.bundlePaths.enumerated() where !path.isEmpty { byBundle[path] = i }

        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return out }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 128)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return out }

        var pathBuf = [CChar](repeating: 0, count: Int(PATH_MAX))

        for pid in pids.prefix(Int(count)) where pid > 0 {
            // 其他使用者的程序與核心讀不到（EPERM），那些本來就不是使用者能關的
            guard let usage = MemoryReader.usage(of: pid) else { continue }
            let fp = usage.footprint
            let cpu = (usage.cpuTime &* timebase.numer) / timebase.denom
            if pid == input.selfPid { out.selfFootprint = fp; continue }

            var owner = byPid[pid]
            if owner == nil, let f = responsiblePid {
                let r = f(pid)
                if r > 0, r != pid { owner = byPid[r] }
            }
            if owner == nil { owner = ownerByParentChain(pid, byPid) }
            if owner == nil, !byBundle.isEmpty {
                let len = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
                if len > 0, let outer = outermostAppBundle(String(cString: pathBuf)) {
                    owner = byBundle[outer]
                }
            }

            if let o = owner {
                out.footprints[o] &+= fp
                out.counts[o] += 1
                out.cpuTimes[o] &+= cpu
            } else {
                out.otherFootprint &+= fp
                out.otherCount += 1
                out.otherCpuTime &+= cpu
            }
        }
        return out
    }

    // MARK: 歸屬輔助

    private static func parentPid(_ pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let rc = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        return rc == size ? pid_t(info.pbi_ppid) : 0
    }

    /// 沿父程序往上找最多 6 層（Electron / Chromium 的輔助程序都是母 App 的子程序）
    private static func ownerByParentChain(_ pid: pid_t, _ byPid: [pid_t: Int]) -> Int? {
        var p = parentPid(pid)
        var hops = 0
        while p > 1, hops < 6 {
            if let o = byPid[p] { return o }
            p = parentPid(p)
            hops += 1
        }
        return nil
    }

    /// "/Applications/Foo.app/Contents/Frameworks/Bar.app/..." → "/Applications/Foo.app"
    private static func outermostAppBundle(_ path: String) -> String? {
        guard let r = path.range(of: ".app/") else { return nil }
        return String(path[..<r.lowerBound]) + ".app"
    }
}

// MARK: - 可觀察模型（App 分頁可見時每 4 秒刷新）

@MainActor
final class AppUsageModel: ObservableObject {
    enum SortKey: Equatable { case memory, cpu }

    @Published private(set) var rows: [AppMemoryUsage] = []
    @Published private(set) var other: AppMemoryUsage?
    @Published private(set) var selfFootprint: UInt64 = 0
    @Published private(set) var hasScanned = false
    @Published var sortKey: SortKey = .memory { didSet { resort() } }

    private var scanning = false
    private let topLimit = 8
    private var allRows: [AppMemoryUsage] = []
    /// 上一次掃描各 App 的累計 CPU 時間，用來算這段時間的佈用率
    private var lastCpu: [String: (time: UInt64, date: Date)] = [:]

    func refresh() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }

        let apps = ProcessScanner.snapshotApps()
        let input = ProcessScanner.ScanInput(
            pids: apps.map(\.pid),
            bundlePaths: apps.map { $0.bundlePath ?? "" },
            selfPid: ProcessInfo.processInfo.processIdentifier
        )
        let out = await Task.detached(priority: .utility) { ProcessScanner.scan(input) }.value

        let now = Date()
        var nextCpu: [String: (time: UInt64, date: Date)] = [:]
        func fraction(id: String, cpuTime: UInt64) -> Double? {
            nextCpu[id] = (cpuTime, now)
            guard let prev = lastCpu[id], cpuTime >= prev.time else { return nil }
            let wall = now.timeIntervalSince(prev.date)
            guard wall > 0.5 else { return nil }
            return Double(cpuTime - prev.time) / 1e9 / wall
        }

        var result: [AppMemoryUsage] = []
        for (i, app) in apps.enumerated() where out.footprints[i] > 0 {
            let id = "pid-\(app.pid)"
            result.append(AppMemoryUsage(
                id: id, name: app.name, icon: app.icon,
                footprint: out.footprints[i], processCount: out.counts[i], app: app.app,
                cpuFraction: fraction(id: id, cpuTime: out.cpuTimes[i])
            ))
        }
        allRows = result
        other = out.otherCount > 0
            ? AppMemoryUsage(id: "other", name: L("apps.other"), icon: nil,
                             footprint: out.otherFootprint, processCount: out.otherCount, app: nil,
                             cpuFraction: fraction(id: "other", cpuTime: out.otherCpuTime))
            : nil
        lastCpu = nextCpu
        selfFootprint = out.selfFootprint
        resort()
        hasScanned = true
    }

    private func resort() {
        var sorted = allRows
        switch sortKey {
        case .memory: sorted.sort { $0.footprint > $1.footprint }
        case .cpu:    sorted.sort { ($0.cpuFraction ?? 0) > ($1.cpuFraction ?? 0) }
        }
        rows = Array(sorted.prefix(topLimit))
    }
}

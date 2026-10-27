import Foundation
import AppKit
import Combine
import Darwin
import UserNotifications

// MARK: - 卡頓偵測
//
// 記憶體以外，老 Mac 變卡最常見的原因是「某個程序默默吃滿 CPU」：卡住的同步程式（OneDrive、
// Dropbox）、失控的網頁分頁、Siri 建議（suggestd）……它們讓 CPU 變熱 → 降頻 → 前景 App 跟著卡。
// 這裡每 10 秒用 proc_pid_rusage 算一次各程序的 CPU（只讀得到同一使用者的程序，
// 也正好是使用者處理得了的），持續 3 分鐘佔用超過半顆核心就列為「失控」，並提供：
//   • 降到背景優先權：setpriority(PRIO_DARWIN_PROCESS, PRIO_DARWIN_BG)，免 root、可還原。
//     實測（8GB Intel MBP）launchd 生的空迴圈被自動降級後優先權 20→4、CPU 96%→27%；
//     man 2 setpriority：背景狀態同時會節流磁碟 I/O 與新開的網路連線
//   • 重新啟動（同步程式卡住時最有效）／結束
//
// 降級的原則——只是「失控期間」的處置，一定還得回來：
//   • 只還原自己降的程序，並以啟動時間核對身分（pid 會被重用）；本來就在背景的程序不碰
//   • 降級中的項目一直留在卡片上（附「恢復」），不會因為被壓下來 CPU 變低就消失
//   • 自動降級的：閒置 2 分鐘、關掉設定、App 回到前景、群組消失、管家結束時都會還原；
//     降級清單也寫進偏好設定，萬一管家當機，下次啟動先把上次的還原
//   • 自動降級只碰選單列常駐程式（排除通話、遠端桌面、錄影、VPN 類）與已知的 Apple 背景工作者；
//     Dock 上的 App、系統介面、沒有 App 身分的第三方程式（可能是使用者自己的伺服器）只提醒不動手

struct Runaway: Identifiable, Equatable {
    let id: String              // "app-<pid>"（App 及其輔助程序）或 "proc-<pid>"（獨立背景程序）
    let name: String
    let pids: [pid_t]
    let cpu: Double             // 近一分鐘平均；1.0 = 一顆核心跑滿
    let duration: TimeInterval  // 已持續偏高多久（isActive 才有意義）
    let appPid: pid_t?          // 有 App 身分才能重新啟動／結束
    let canQuit: Bool
    let isActive: Bool          // 此刻仍在失控；false = 已降到背景、目前沒在狂吃（仍可「恢復」）
    let isDemoted: Bool
    let isFrontmost: Bool
}

/// CPU 熱壓力讀數（與「系統」分頁同一套判斷）
struct HeatReading: Equatable {
    let level: Int?             // Intel：machdep.xcpm.cpu_thermal_level 0～100
    let speedLimit: Int?        // %；< 100 = 正在降速
    let state: ProcessInfo.ThermalState

    var isThrottling: Bool {
        if let l = speedLimit, l < 100 { return true }
        if let t = level, t >= 70 { return true }
        return state == .serious || state == .critical
    }
    /// 明顯降速：速度被壓到 80% 以下，或系統回報嚴重過熱
    var isSevere: Bool {
        if let l = speedLimit, l < 80 { return true }
        return state == .serious || state == .critical
    }
}

struct LagReport: Equatable {
    var runaways: [Runaway] = []    // 失控中的在前；之後是已降到背景、目前平靜的
    var heat: HeatReading?          // nil = 沒有在降頻
    var highRefreshHz: Int?         // Intel 內顯 + 外接螢幕 > 60Hz
    var rebootDays: Int?            // 久未重開機且交換空間大 → 建議重開機
}

@MainActor
final class LagDetector: ObservableObject {
    @Published private(set) var report = LagReport()
    /// 各項目最近一次操作的狀態（重新啟動中、等待結束…）
    @Published private(set) var notes: [String: ActionNote] = [:]
    /// 最近一次掃描 CPU 最高的幾個程序群組（自我測試與除錯用；刻意不發布）
    private(set) var topCPU: [(name: String, cpu: Double)] = []

    enum ActionNote: Equatable { case restarting, waiting, restarted, quitting, failed }

    /// 開發用：MEMORYBUTLER_LAG_TIMESCALE=0.1 把所有時間常數縮成十分之一（端對端測試不必等 5 分鐘）
    nonisolated static let timeScale: Double = {
        guard let v = ProcessInfo.processInfo.environment["MEMORYBUTLER_LAG_TIMESCALE"].flatMap(Double.init),
              v > 0, v <= 1 else { return 1 }
        return v
    }()
    nonisolated static let interval: TimeInterval = 10 * timeScale
    /// 超過半顆核心算「偏高」；降到 0.3 以下才算恢復（遲滯，避免忽上忽下）
    nonisolated static let busyCPU = 0.5
    nonisolated static let calmCPU = 0.3
    /// CPU 平均的時間常數（近一分鐘）
    nonisolated static let averagingWindow: TimeInterval = 60 * timeScale
    /// 持續 3 分鐘才列為失控（編譯、匯出這類短時間全速是正常的）
    nonisolated static let runawayAfter: TimeInterval = 180 * timeScale
    /// 背景服務持續 5 分鐘失控才自動降級
    nonisolated static let autoDemoteAfter: TimeInterval = 300 * timeScale
    /// 自動降級的群組閒置（< 0.1 核心）2 分鐘就還原。被壓住但仍想狂吃的程序約用 0.2～0.3 核心，不會誤判成閒置
    nonisolated static let idleCPU = 0.1
    nonisolated static let restoreAfterIdle: TimeInterval = 120 * timeScale
    /// 持續 10 分鐘才推播通知，同一個程序 6 小時內只提醒一次
    nonisolated static let notifyAfter: TimeInterval = 600 * timeScale
    nonisolated static let notifyEvery: TimeInterval = 6 * 3600 * timeScale

    /// 降級會讓使用者正在等的事斷斷續續（通話、遠端桌面、播放、錄影、VPN／代理、容器）：只提醒不自動降級
    private static let realtimeHints = [
        "rustdesk", "teamviewer", "anydesk", "parsec", "splashtop", "screens", "vnc",
        "zoom", "teams", "webex", "skype", "facetime", "discord", "slack", "naver.line", "wechat", "telegram",
        "spotify", "music", "audio", "sound", "podcast",
        "obsproject", "record", "capture", "cleanshot", "loom", "screenflow", "camtasia",
        "vpn", "proxy", "clash", "surge", "v2ray", "wireguard", "tailscale", "docker",
    ]
    /// 可以自動降級的 Apple 背景工作者（只做索引、建議、分析、背景下載，不在使用者等待的路徑上）
    private static let autoDemotable: Set<String> = [
        "suggestd", "mdworker", "mdworker_shared", "corespotlightd", "spotlightknowledged",
        "photoanalysisd", "mediaanalysisd", "nsurlsessiond",
    ]

    /// 單一群組的 CPU 追蹤狀態（純值型別：自我檢查可以直接餵假資料驗證）
    struct Track: Equatable {
        var ewma: Double = 0
        var highSince: Date?
        var name: String?

        /// 吃進一段區間的 CPU 佔用（x：這段時間平均用了幾顆核心）
        func stepped(cpu x: Double, dt: TimeInterval, now: Date) -> Track {
            var t = self
            t.ewma += (x - t.ewma) * (1 - exp(-dt / LagDetector.averagingWindow))   // 近一分鐘平均
            if x >= LagDetector.busyCPU {
                if t.highSince == nil { t.highSince = now }
            } else if x < LagDetector.calmCPU {
                t.highSince = nil
            }
            return t
        }

        /// 已持續偏高夠久、平均也夠高，才算失控
        func isRunaway(at now: Date) -> Bool {
            guard let since = highSince else { return false }
            return now.timeIntervalSince(since) >= LagDetector.runawayAfter && ewma >= LagDetector.busyCPU * 0.8
        }
    }

    /// 管家親手降級的一個群組：pid → 啟動時間（還原前核對，pid 會被重用）
    private struct Demotion {
        var pids: [pid_t: UInt64]
        let isAuto: Bool
    }

    private let settings: SettingsStore
    private let monitor: MemoryMonitor
    private var tracks: [String: Track] = [:]
    private var lastCpu: [pid_t: UInt64] = [:]
    private var lastTick: Date?
    private var demoted: [String: Demotion] = [:]
    private var idleSince: [String: Date] = [:]
    private var autoDemotedNotified: Set<String> = []
    /// 使用者親手按過「恢復」的群組：本次執行期間不再自動降級，尊重使用者的決定
    private var userRestored: Set<String> = []
    private var notified: [String: Date] = [:]           // 名稱 → 上次通知時間
    private var restartTasks: [String: Task<Void, Never>] = [:]
    private var timer: DispatchSourceTimer?
    private var ticking = false
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var lastDisplayCheck: Date = .distantPast
    private var highRefreshHz: Int?
    /// 上一次掃描的群組資訊（動作按鈕需要知道群組有哪些 pid、是不是 App）
    private var groupInfo: [String: GroupInfo] = [:]
    /// App 清單快取：逐一讀 NSRunningApplication 的屬性不便宜，執行中的 App 沒變就沿用；每分鐘仍重建一次
    private var appsCache: (pids: [pid_t], apps: [ProcessScanner.RunningApp], at: Date)?

    private static let demotedKey = "lag.demotedPids"

    private struct GroupInfo {
        var pids: [pid_t]
        let app: ProcessScanner.RunningApp?
    }

    /// 自動降級／還原時告訴 AutoPilot 的狀態列（由 AppModel 接上）
    var onAutoDemote: ((String) -> Void)?

    init(settings: SettingsStore, monitor: MemoryMonitor) {
        self.settings = settings
        self.monitor = monitor
        // 關掉「自動壓制」＝不要管家替我降級：把自動降的全部還原
        settings.$autoDemote
            .dropFirst()
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in self?.restoreAutomatic() }
            .store(in: &cancellables)
    }

    func start() {
        guard timer == nil else { return }
        recoverAfterCrash()

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1, repeating: Self.interval, leeway: .milliseconds(Int(Self.interval * 100)))
        t.setEventHandler { [weak self] in self?.scheduleTick() }
        t.resume()
        timer = t

        // 被降級的 App 一回到前景就恢復正常優先權：只壓背景，不拖慢正在用的東西
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .processIdentifier else { return }
            DispatchQueue.main.async { [weak self] in self?.restore(groupId: "app-\(pid)") }
        })
    }

    private func scheduleTick() {
        Task { await tick() }
    }

    // MARK: 取樣

    func tick() async {
        guard !ticking else { return }
        ticking = true
        defer { ticking = false }

        let runningPids = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        let apps: [ProcessScanner.RunningApp]
        if let c = appsCache, c.pids == runningPids, Date().timeIntervalSince(c.at) < 60 {
            apps = c.apps
        } else {
            apps = ProcessScanner.snapshotApps(withIcons: false)
            appsCache = (runningPids, apps, Date())
        }
        let input = ProcessScanner.ScanInput(
            pids: apps.map(\.pid),
            bundlePaths: apps.map { $0.bundlePath ?? "" },
            selfPid: ProcessInfo.processInfo.processIdentifier
        )
        let out = await Task.detached(priority: .utility) { ProcessScanner.scan(input) }.value
        let now = Date()
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now

        // 依群組加總這段時間用掉的 CPU（新出現的程序先建立基準，下一輪才算）
        var groupNs: [String: UInt64] = [:]
        var info: [String: GroupInfo] = [:]
        var nextCpu: [pid_t: UInt64] = [:]
        nextCpu.reserveCapacity(out.procs.count)
        for p in out.procs {
            nextCpu[p.pid] = p.cpuTime
            let key = p.owner >= 0 ? "app-\(apps[p.owner].pid)" : "proc-\(p.pid)"
            if info[key] == nil { info[key] = GroupInfo(pids: [], app: p.owner >= 0 ? apps[p.owner] : nil) }
            info[key]!.pids.append(p.pid)
            if let prev = lastCpu[p.pid], p.cpuTime >= prev { groupNs[key, default: 0] &+= p.cpuTime - prev }
        }
        lastCpu = nextCpu
        groupInfo = info

        // 降級過的群組：群組消失（App 結束、改組）就把還活著的成員還原；還在就補上新生的輔助程序
        var demotionsChanged = false
        for (key, d) in demoted {
            guard let g = info[key] else {
                Self.restore(d.pids)
                demoted[key] = nil
                idleSince[key] = nil
                demotionsChanged = true
                continue
            }
            let fresh = g.pids.filter { d.pids[$0] == nil }
            let added = fresh.isEmpty ? [:] : Self.demote(fresh)
            if !added.isEmpty {
                demoted[key]!.pids.merge(added) { old, _ in old }
                demotionsChanged = true
            }
        }
        if demotionsChanged { persistDemoted() }

        // 間隔太短算不準（第一次只建立基準）
        guard dt >= min(1, Self.interval * 0.5) else {
            if demotionsChanged { updateFlags() }
            return
        }

        var nextTracks: [String: Track] = [:]
        var groupCPU: [String: Double] = [:]
        var top: [(String, Double)] = []
        for (key, g) in info {
            let x = Double(groupNs[key] ?? 0) / 1e9 / dt
            groupCPU[key] = x
            var t = (tracks[key] ?? Track()).stepped(cpu: x, dt: dt, now: now)
            // 沒在用 CPU 的群組不必記（幾百個閒置程序）；降級中的一定要留著，卡片上才看得到
            if t.ewma < 0.005 && t.highSince == nil && demoted[key] == nil { continue }
            if t.name == nil, x >= 0.02 || t.ewma >= 0.02 || t.highSince != nil || demoted[key] != nil {
                t.name = Self.displayName(key: key, info: g)
            }
            nextTracks[key] = t
            if x >= 0.02 { top.append((t.name ?? key, x)) }
        }
        tracks = nextTracks
        topCPU = top.sorted { $0.1 > $1.1 }.prefix(6).map { (name: $0.0, cpu: $0.1) }

        // 自動降級的群組閒置夠久就還原：它已經不失控了，把優先權還給它
        for (key, d) in demoted where d.isAuto {
            if (groupCPU[key] ?? 0) < Self.idleCPU {
                let since = idleSince[key] ?? now
                idleSince[key] = since
                if now.timeIntervalSince(since) >= Self.restoreAfterIdle { restore(groupId: key) }
            } else {
                idleSince[key] = nil
            }
        }

        // 失控清單 + 降級中的項目
        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var active: [Runaway] = []
        var calmed: [Runaway] = []
        for (key, t) in tracks {
            guard let g = info[key] else { continue }
            let isActive = t.isRunaway(at: now)
            let isDemoted = demoted[key] != nil
            guard isActive || isDemoted else { continue }
            let app = g.app
            let r = Runaway(
                id: key, name: t.name ?? key, pids: g.pids, cpu: t.ewma,
                duration: isActive ? now.timeIntervalSince(t.highSince ?? now) : 0,
                appPid: app?.pid, canQuit: app.map { !$0.isSystem } ?? false,
                isActive: isActive, isDemoted: isDemoted,
                isFrontmost: app != nil && app?.pid == frontPid
            )
            if isActive { active.append(r) } else { calmed.append(r) }
        }
        active.sort { $0.cpu > $1.cpu }
        calmed.sort { $0.cpu > $1.cpu }

        for r in active {
            autoDemoteIfAppropriate(r, info: info[r.id])
            notifyIfAppropriate(r)
        }

        // 熱降頻（sysctl + IOKit，各不到 0.1ms）
        let heat = HeatReading(level: SystemReader.thermalLevel(),
                               speedLimit: SystemReader.cpuSpeedLimit(),
                               state: ProcessInfo.processInfo.thermalState)
        // 螢幕設定很少變：每分鐘看一次就好
        if now.timeIntervalSince(lastDisplayCheck) >= 60 {
            lastDisplayCheck = now
            highRefreshHz = SystemReader.isAppleSilicon ? nil
                : SystemReader.displays().first { !$0.isBuiltin && $0.refreshRate > 61 }.map { Int($0.refreshRate.rounded()) }
        }
        let uptimeDays = Int(SystemReader.uptime() / 86400)

        var next = LagReport()
        next.runaways = (Array(active.prefix(3)) + Array(calmed.prefix(3))).map { r in
            let d = demoted[r.id] != nil      // 剛剛可能自動降級了
            return r.isDemoted == d ? r : r.with(demoted: d)
        }
        next.heat = heat.isThrottling ? heat : nil
        next.highRefreshHz = highRefreshHz
        next.rebootDays = uptimeDays >= 5 && HealthInsight.isSwapHeavy(monitor.current) ? uptimeDays : nil
        if next != report { report = next }
    }

    // MARK: 動作

    /// 使用者親手降到背景優先權（可還原；不會因閒置自動還原，直到按「恢復」或該 App 回到前景）
    func demote(_ r: Runaway) {
        let done = Self.demote(groupInfo[r.id]?.pids ?? r.pids)
        guard !done.isEmpty else {
            notes[r.id] = .failed
            clearNoteLater(r.id)
            return
        }
        var pids = demoted[r.id]?.pids ?? [:]
        pids.merge(done) { old, _ in old }
        demoted[r.id] = Demotion(pids: pids, isAuto: false)
        userRestored.remove(r.id)
        persistDemoted()
        updateFlags()
    }

    func restore(_ r: Runaway) {
        userRestored.insert(r.id)
        restore(groupId: r.id)
    }

    private func restore(groupId: String) {
        guard let d = demoted.removeValue(forKey: groupId) else { return }
        Self.restore(d.pids)
        idleSince[groupId] = nil
        autoDemotedNotified.remove(groupId)
        persistDemoted()
        updateFlags()
    }

    /// 把自動降級的全部還原（關掉「自動壓制」時）
    private func restoreAutomatic() {
        for (key, d) in demoted where d.isAuto { restore(groupId: key) }
    }

    /// 管家結束（或更新重啟）前把降級過的程序全部還原，不留下被壓著的程序
    func restoreAll() {
        for d in demoted.values { Self.restore(d.pids) }
        demoted.removeAll()
        persistDemoted()
    }

    func quit(_ r: Runaway) {
        guard r.canQuit, let pid = r.appPid, let app = NSRunningApplication(processIdentifier: pid) else { return }
        notes[r.id] = .quitting
        app.terminate()
        clearNoteLater(r.id, after: 8)
    }

    /// 結束 → 等它真的結束 → 在背景重新打開（不搶走焦點）。
    /// 溫和結束要留時間給 App 問「要儲存嗎？」：10 秒後改顯示「等待中」（可強制或取消），最多等 2 分鐘；
    /// 使用者在對話框按了取消就什麼都不做
    func restart(_ r: Runaway, force: Bool = false) {
        guard r.canQuit, let pid = r.appPid, let app = NSRunningApplication(processIdentifier: pid),
              let url = app.bundleURL else { return }
        let id = r.id
        restartTasks.removeValue(forKey: id)?.cancel()
        notes[id] = .restarting
        if force { app.forceTerminate() } else { app.terminate() }
        restartTasks[id] = Task { [weak self] in
            let steps = force ? 25 : 600                 // × 0.2 秒：強制 5 秒、一般 2 分鐘
            for step in 1...steps {
                if app.isTerminated || Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
                if step == 50, !force, !app.isTerminated, !Task.isCancelled { self?.notes[id] = .waiting }
            }
            guard let self, !Task.isCancelled else { return }
            self.restartTasks[id] = nil
            guard app.isTerminated else {
                self.notes[id] = nil
                return
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            // 用完成回呼版本：async 版會把非 Sendable 的 NSWorkspace／設定帶離主執行緒（Swift 5.10 會警告）
            NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
                let ok = error == nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.notes[id] = ok ? .restarted : .failed
                    self.clearNoteLater(id, after: 6)
                }
            }
        }
    }

    /// 不等了：收起「等待中」，不重新開啟（App 若之後自己結束也不會被重開）
    func cancelRestart(_ r: Runaway) {
        restartTasks.removeValue(forKey: r.id)?.cancel()
        notes[r.id] = nil
    }

    private func updateFlags() {
        var next = report
        next.runaways = next.runaways.compactMap { r in
            let d = demoted[r.id] != nil
            if !r.isActive && !d { return nil }       // 已還原、也沒在失控：從清單拿掉
            return r.isDemoted == d ? r : r.with(demoted: d)
        }
        if next != report { report = next }
    }

    private func clearNoteLater(_ id: String, after seconds: UInt64 = 4) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            self?.notes[id] = nil
        }
    }

    // MARK: 自動處理與通知

    private func autoDemoteIfAppropriate(_ r: Runaway, info: GroupInfo?) {
        guard settings.autoDemote, !r.isFrontmost, demoted[r.id] == nil, !userRestored.contains(r.id),
              r.duration >= Self.autoDemoteAfter, Self.isBackgroundType(info) else { return }
        let done = Self.demote(info?.pids ?? r.pids)
        guard !done.isEmpty else { return }
        demoted[r.id] = Demotion(pids: done, isAuto: true)
        persistDemoted()
        if autoDemotedNotified.insert(r.id).inserted {
            onAutoDemote?(LF("decision.autoDemoted", r.name, Int((r.cpu * 100).rounded())))
        }
    }

    /// 自動降級的資格：選單列常駐的第三方 App（排除即時性類別），或已知的 Apple 背景工作者。
    /// Dock 上的 App 使用者看得到、自己決定；系統 App（Dock、控制中心、輸入法…）一降級介面或打字就卡；
    /// 沒有 App 身分的第三方程式可能是使用者自己的伺服器或遠端桌面代理——都只提醒
    private static func isBackgroundType(_ info: GroupInfo?) -> Bool {
        guard let info else { return false }
        if let app = info.app {
            guard app.isAccessory, !app.isSystem else { return false }
            let id = ((app.bundleID ?? "") + " " + app.name).lowercased()
            return !realtimeHints.contains { id.contains($0) }
        }
        guard let pid = info.pids.first, let path = ProcessScanner.processPath(pid),
              ["/System/", "/usr/", "/Library/Apple/"].contains(where: { path.hasPrefix($0) }) else { return false }
        return autoDemotable.contains((path as NSString).lastPathComponent)
    }

    private func notifyIfAppropriate(_ r: Runaway) {
        guard settings.lagAlerts, Updater.isBundled, !r.isFrontmost, r.duration >= Self.notifyAfter else { return }
        let now = Date()
        if let last = notified[r.name], now.timeIntervalSince(last) < Self.notifyEvery { return }
        notified[r.name] = now

        let content = UNMutableNotificationContent()
        content.title = LF("lag.notif.title", r.name)
        content.body = LF(r.canQuit ? "lag.notif.body.app" : "lag.notif.body",
                          Int((r.cpu * 100).rounded()), Int(r.duration / 60))
        let request = UNNotificationRequest(identifier: "runaway-\(r.name)", content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { center.add(request) }
        }
    }

    // MARK: 降級清單的保存（萬一管家當機，下次啟動先把上次降的還原）

    private func persistDemoted() {
        let all: [[NSNumber]] = demoted.values.flatMap { d in
            d.pids.map { [NSNumber(value: $0.key), NSNumber(value: Int64(clamping: $0.value))] }
        }
        if all.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.demotedKey)
        } else {
            UserDefaults.standard.set(all, forKey: Self.demotedKey)
        }
    }

    private func recoverAfterCrash() {
        guard let saved = UserDefaults.standard.array(forKey: Self.demotedKey) as? [[NSNumber]] else { return }
        var pids: [pid_t: UInt64] = [:]
        for pair in saved where pair.count == 2 { pids[pair[0].int32Value] = UInt64(clamping: pair[1].int64Value) }
        Self.restore(pids)
        UserDefaults.standard.removeObject(forKey: Self.demotedKey)
    }

    // MARK: 低階

    /// 降到背景優先權。本來就在背景（優先權 ≤ 4）的不碰——還原時才不會把它拉得比原本還高。
    /// 回傳成功降級的 pid → 啟動時間
    nonisolated static func demote(_ pids: [pid_t]) -> [pid_t: UInt64] {
        var done: [pid_t: UInt64] = [:]
        for pid in pids where pid > 0 {
            guard let start = ProcessScanner.startTime(pid) else { continue }
            if let p = ProcessScanner.basePriority(pid), p <= 4 { continue }
            if setpriority(PRIO_DARWIN_PROCESS, id_t(pid), PRIO_DARWIN_BG) == 0 { done[pid] = start }
        }
        return done
    }

    /// 還原：只碰啟動時間對得上的（確認還是當初降級的那個程序）
    nonisolated static func restore(_ pids: [pid_t: UInt64]) {
        for (pid, start) in pids where pid > 0 && ProcessScanner.startTime(pid) == start {
            _ = setpriority(PRIO_DARWIN_PROCESS, id_t(pid), 0)
        }
    }

    /// 常見系統背景程序的白話名稱
    private static let friendlyKeys: [String: String] = [
        "suggestd": "proc.suggestd",
        "mds": "proc.spotlight", "mds_stores": "proc.spotlight", "mdworker": "proc.spotlight",
        "mdworker_shared": "proc.spotlight", "corespotlightd": "proc.spotlight", "spotlightknowledged": "proc.spotlight",
        "photoanalysisd": "proc.photos", "mediaanalysisd": "proc.photos", "photolibraryd": "proc.photos",
        "cloudd": "proc.icloud", "bird": "proc.icloud", "fileproviderd": "proc.fileprovider",
        "nsurlsessiond": "proc.download", "backupd": "proc.timemachine", "softwareupdated": "proc.update",
    ]

    private static func displayName(key: String, info: GroupInfo) -> String {
        if let app = info.app { return app.name }
        guard let pid = info.pids.first else { return key }
        let raw = ProcessScanner.processName(pid)
        if let k = friendlyKeys[raw] { return LF(k, raw) }
        return raw
    }

    // MARK: 自我測試用：注入示範資料（只在離屏快照時使用）

    /// waiting: 讓第一個失控項目顯示「等待 App 結束」狀態（檢視強制／取消按鈕的排版）
    func injectDemo(waiting: Bool = false) {
        if waiting { notes["demo-1"] = .waiting }
        var r = LagReport()
        r.runaways = [
            Runaway(id: "demo-1", name: "OneDrive", pids: [], cpu: 0.86, duration: 14 * 60,
                    appPid: nil, canQuit: true, isActive: true, isDemoted: false, isFrontmost: false),
            Runaway(id: "demo-2", name: LF("proc.suggestd", "suggestd"), pids: [], cpu: 0.62, duration: 6 * 60,
                    appPid: nil, canQuit: false, isActive: true, isDemoted: true, isFrontmost: false),
            Runaway(id: "demo-3", name: "Dropbox", pids: [], cpu: 0.24, duration: 0,
                    appPid: nil, canQuit: true, isActive: false, isDemoted: true, isFrontmost: false),
        ]
        r.heat = HeatReading(level: 99, speedLimit: 100, state: .fair)
        r.highRefreshHz = 144
        r.rebootDays = 7
        report = r
    }
}

private extension Runaway {
    func with(demoted: Bool) -> Runaway {
        Runaway(id: id, name: name, pids: pids, cpu: cpu, duration: duration, appPid: appPid,
                canQuit: canQuit, isActive: isActive, isDemoted: demoted, isFrontmost: isFrontmost)
    }
}

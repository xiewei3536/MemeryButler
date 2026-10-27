import Foundation
import Darwin

// MARK: - 自我檢查（開發／CI 用，不開任何視窗）
//
//   MEMORYBUTLER_SELFTEST=checks .build/debug/MemoryButler      → 全部通過回傳 0，否則 1
//
// 只驗證純邏輯：門檻與判讀、釋放前的拒絕條件、無效釋放的學習、失控偵測的遲滯、
// 版本比較、SMC 解碼、三語字串的格式一致性（格式符號對不上會在執行期崩潰）。
// 最後再實際把一個子程序降到背景優先權再還原，確認免 root 的那條路徑在這台機器上可用。

@MainActor
enum Checks {
    private static var failures = 0
    private static var passes = 0

    private static func expect(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("[checks] ✗ \(name) \(detail())")
        }
    }

    static func runAndExit() -> Never {
        insights()
        preflight()
        futility()
        runawayTracking()
        versions()
        formatting()
        smcDecode()
        strings()
        backgroundPriority()
        print("[checks] \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: 樣本

    private static let gb: UInt64 = 1 << 30
    private static let mb: UInt64 = 1 << 20

    private static func sample(compressed: UInt64 = 512 << 20, swap: UInt64 = 0,
                               pressure: PressureLevel = .normal, swapInRate: Double = 0,
                               app: UInt64 = 3 << 30) -> MemorySample {
        var s = MemorySample(date: Date(), total: 8 << 30, appMemory: app, wired: 1 << 30,
                             compressed: compressed, cached: 1 << 30, free: 200 << 20,
                             swapUsed: swap, pressure: pressure)
        s.swapInRate = swapInRate
        return s
    }

    // MARK: 判讀

    private static func insights() {
        expect(HealthInsight.from(sample()) == .healthy, "insight.healthy")
        expect(HealthInsight.from(sample(compressed: 2 * gb)) == .compressing, "insight.compressing")
        expect(HealthInsight.from(sample(swap: 3 * gb)) == .swapping, "insight.swapping.heavy")
        expect(HealthInsight.from(sample(compressed: 2 * gb, swap: 1200 * mb)) == .swapping, "insight.swapping.tight")
        expect(HealthInsight.from(sample(swap: 1200 * mb)) == .healthy, "insight.someSwapButRelaxed")
        expect(HealthInsight.from(sample(swapInRate: 5 * 1_048_576)) == .thrashing, "insight.thrashing")
        expect(HealthInsight.from(sample(swapInRate: 3 * 1_048_576)) == .healthy, "insight.belowThrashing")
        expect(HealthInsight.from(sample(pressure: .critical, swapInRate: 50 * 1_048_576)) == .critical,
               "insight.criticalWins")
    }

    // MARK: 釋放前的拒絕條件

    private static func preflight() {
        typealias E = ReleaseEngine
        expect(E.preflight(sample(), swapGrew: false) == nil, "preflight.healthyRuns")
        expect(E.preflight(sample(pressure: .critical), swapGrew: false) == .critical, "preflight.critical")
        expect(E.preflight(sample(), swapGrew: true) == .swapping, "preflight.swapGrowing")
        expect(E.preflight(sample(), swapGrew: false, swapInRate: 5 * 1_048_576) == .thrashing, "preflight.thrashing")
        // 這台 8GB Mac 的實況：swap 3GB → 一律不出手（1.3 每小時白跑一次的根因）
        expect(E.preflight(sample(swap: 3 * gb), swapGrew: false) == .swapHeavy, "preflight.swapHeavy")
        expect(E.preflight(sample(swap: 1 * gb), swapGrew: false) == nil, "preflight.someSwapOK")
        expect(E.preflight(sample(compressed: 1200 * mb), swapGrew: false) == .compressorFull, "preflight.compressorFull")
    }

    // MARK: 無效釋放的學習

    private static func futility() {
        func ev(_ trigger: ReleaseTrigger, _ reclaimedMB: Int64) -> ReleaseEvent {
            ReleaseEvent(id: UUID(), date: Date(), trigger: trigger, reclaimed: reclaimedMB << 20,
                         duration: 3, ballast: 1 << 30, stopReason: .compressorGrowth, swapDelta: 0)
        }
        let streak = AutoPilot.leadingFutileStreak([
            ev(.schedule, 0), ev(.threshold, 10), ev(.manual, 900), ev(.pressure, 0), ev(.schedule, 1024), ev(.schedule, 0),
        ])
        expect(streak == 3, "futility.streakSkipsManualStopsAtEffective", "got \(streak)")
        expect(AutoPilot.leadingFutileStreak([]) == 0, "futility.empty")
        expect(AutoPilot.leadingFutileStreak([ev(.schedule, 500)]) == 0, "futility.effectiveFirst")
    }

    // MARK: 失控偵測（每 10 秒一筆）

    private static func runawayTracking() {
        let t0 = Date()
        var t = LagDetector.Track()
        var now = t0
        for _ in 0..<17 {                          // 170 秒、85% → 還不算
            now += 10
            t = t.stepped(cpu: 0.85, dt: 10, now: now)
        }
        expect(!t.isRunaway(at: now), "runaway.notBefore3min")
        for _ in 0..<2 {                           // 190 秒 → 算失控
            now += 10
            t = t.stepped(cpu: 0.85, dt: 10, now: now)
        }
        expect(t.isRunaway(at: now), "runaway.after3min", "ewma=\(t.ewma)")
        now += 10
        t = t.stepped(cpu: 0.4, dt: 10, now: now)  // 0.3～0.5 之間：遲滯，維持
        expect(t.highSince != nil, "runaway.hysteresisHolds")
        now += 10
        t = t.stepped(cpu: 0.1, dt: 10, now: now)  // 降到 0.3 以下：解除
        expect(t.highSince == nil && !t.isRunaway(at: now), "runaway.clears")

        // 短暫尖峰（編譯 60 秒）不算
        var b = LagDetector.Track()
        now = t0
        for i in 0..<30 {
            now += 10
            b = b.stepped(cpu: i < 6 ? 3.5 : 0.02, dt: 10, now: now)
        }
        expect(!b.isRunaway(at: now) && b.highSince == nil, "runaway.burstIgnored")
    }

    // MARK: 其他純函式

    private static func versions() {
        expect(Updater.isNewer("1.4.0", than: "1.3.1"), "version.minor")
        expect(Updater.isNewer("1.10.0", than: "1.9.9"), "version.numericNotLexical")
        expect(!Updater.isNewer("1.3", than: "1.3.0"), "version.equalPadded")
        expect(!Updater.isNewer("1.3.1", than: "1.4.0"), "version.older")
    }

    private static func formatting() {
        expect(Fmt.rate(0) == "0 MB/s", "fmt.rate.zero", Fmt.rate(0))
        expect(Fmt.rate(5.5 * 1_048_576) == "5.5 MB/s", "fmt.rate.small", Fmt.rate(5.5 * 1_048_576))
        expect(Fmt.rate(12.4 * 1_048_576) == "12 MB/s", "fmt.rate.large", Fmt.rate(12.4 * 1_048_576))
    }

    private static func smcDecode() {
        let t = SMCReader.decode(type: "sp78", bytes: [0x53, 0x80])          // 83.5°C
        expect(t.map { abs($0 - 83.5) < 0.001 } ?? false, "smc.sp78", "\(String(describing: t))")
        let f = SMCReader.decode(type: "fpe2", bytes: [0x52, 0xD0])          // 5300 rpm
        expect(f.map { abs($0 - 5300) < 0.001 } ?? false, "smc.fpe2", "\(String(describing: f))")
        let bits = Float(12.5).bitPattern
        let flt = SMCReader.decode(type: "flt ", bytes: [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff),
                                                         UInt8(bits >> 16 & 0xff), UInt8(bits >> 24)])
        expect(flt == 12.5, "smc.flt", "\(String(describing: flt))")
    }

    // MARK: 三語字串

    /// 依參數位置整理出格式符號的型別（%2$d 這種指定位置的也算）。照 printf 文法解析：
    /// 旗標、寬度、精度、長度修飾後必須接合法的轉換字元，否則視為字面上的「%」（例如說明文字裡的「100% 表示」）
    private static func specifiers(_ s: String) -> [Int: Character] {
        let conversions = Set("diouxXfFeEgGaAcsSp@")
        let flags = Set(" -+#0'")
        let lengths = Set("hlqLzjt")
        var out: [Int: Character] = [:]
        var next = 1
        let c = Array(s)
        var i = 0
        while i < c.count {
            guard c[i] == "%" else { i += 1; continue }
            var j = i + 1
            if j < c.count, c[j] == "%" { i = j + 1; continue }
            // 指定位置 n$
            var position: Int?
            var k = j
            var digits = ""
            while k < c.count, c[k].isASCII, c[k].isNumber { digits.append(c[k]); k += 1 }
            if k < c.count, c[k] == "$", let p = Int(digits) { position = p; j = k + 1 }
            while j < c.count, flags.contains(c[j]) { j += 1 }
            while j < c.count, c[j].isASCII, c[j].isNumber || c[j] == "*" { j += 1 }
            if j < c.count, c[j] == "." {
                j += 1
                while j < c.count, c[j].isASCII, c[j].isNumber || c[j] == "*" { j += 1 }
            }
            while j < c.count, lengths.contains(c[j]) { j += 1 }
            guard j < c.count, conversions.contains(c[j]) else { i += 1; continue }
            let pos = position ?? next
            if position == nil { next += 1 }
            out[pos] = c[j]
            i = j + 1
        }
        return out
    }

    private static func strings() {
        for (key, row) in L10n.table {
            expect(row.count == 3, "l10n.threeLanguages", key)
            guard row.count == 3 else { continue }
            let en = specifiers(row[0])
            expect(specifiers(row[1]) == en && specifiers(row[2]) == en, "l10n.formatMatches", key)
        }
        // 由列舉值組出來的字串鍵，每一個都要有翻譯
        for r in SkipReason.allCases {
            expect(L10n.table["btn.skipped.\(r.rawValue)"] != nil, "l10n.skipButton", r.rawValue)
            expect(L10n.table["decision.skip.\(r.rawValue)"] != nil, "l10n.skipDecision", r.rawValue)
        }
        for t in ReleaseTrigger.allCases {
            expect(L10n.table["trigger.\(t.rawValue)"] != nil, "l10n.trigger", t.rawValue)
        }
    }

    // MARK: 降到背景優先權（實際對一個子程序操作）

    private static func backgroundPriority() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["5"]
        guard (try? p.run()) != nil else { expect(false, "prio.spawn"); return }
        defer { p.terminate() }
        let pid = p.processIdentifier

        func priority() -> Int32? {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            return proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size ? info.pti_priority : nil
        }
        let before = priority()
        let demoted = LagDetector.demote([pid])
        let during = priority()
        let again = LagDetector.demote([pid])                     // 已在背景：不再碰（還原時才不會拉高）
        var wrongIdentity = demoted
        for k in wrongIdentity.keys { wrongIdentity[k]! &+= 1 }     // 啟動時間對不上＝不是同一個程序
        LagDetector.restore(wrongIdentity)
        let stillLow = priority()
        LagDetector.restore(demoted)
        let after = priority()
        expect(Array(demoted.keys) == [pid], "prio.setpriorityAllowed")
        expect(again.isEmpty, "prio.skipsAlreadyBackground")
        if let b = before, let d = during, let s = stillLow, let a = after {
            print("[checks] background priority on a child process: \(b) → \(d) → \(a)")
            expect(d < b && a == b, "prio.lowersAndRestores", "before=\(b) during=\(d) after=\(a)")
            expect(s == d, "prio.restoreChecksIdentity", "stillLow=\(s)")
        } else {
            expect(false, "prio.readable", "proc_pidinfo failed")
        }
    }
}

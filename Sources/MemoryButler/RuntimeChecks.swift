import Foundation
import Darwin

/// 回歸檢查只餵假資料；驗證不會觸碰其他程式、系統設定或已安裝 App。
@MainActor
extension Checks {
    static func runtimePolicies() {
        expect(MonitoringPolicy.memoryInterval(visible: false, lowPower: false, pressure: .normal) == 6, "poll.hidden6s")
        expect(MonitoringPolicy.memoryInterval(visible: true, lowPower: false, pressure: .normal) == 2, "poll.visible2s")
        expect(MonitoringPolicy.memoryInterval(visible: false, lowPower: true, pressure: .normal) == 10, "poll.lowPower10s")
        expect(MonitoringPolicy.memoryInterval(visible: true, lowPower: true, pressure: .normal) == 4, "poll.lowPowerVisible4s")
        for visible in [false, true] {
            for lowPower in [false, true] {
                for level in [PressureLevel.warning, .critical] {
                    expect(MonitoringPolicy.memoryInterval(visible: visible, lowPower: lowPower, pressure: level) == 2,
                           "poll.pressureAlwaysResponsive")
                }
            }
        }
        expect(MonitoringPolicy.processInterval(visible: false, lowPower: false) == 15, "poll.processHidden15s")
        expect(MonitoringPolicy.processInterval(visible: true, lowPower: false) == 10, "poll.processVisible10s")
        expect(MonitoringPolicy.processInterval(visible: false, lowPower: true) == 30, "poll.processLowPower30s")
        expect(MonitoringPolicy.processInterval(visible: true, lowPower: true) == 30, "poll.processVisibleLowPower30s")
        expect(MonitoringPolicy.historyDuration == 300, "poll.historyFiveMinutes")
        expect(MonitoringPolicy.foregroundGrace == 120, "poll.foregroundGraceTwoMinutes")

        let t = Date(timeIntervalSince1970: 1000)
        var protection = ForegroundProtection()
        protection.observe(100, at: t)
        expect(protection.protects(100, frontmost: 100, at: t + 600), "foreground.currentAlwaysProtected")
        protection.observe(200, at: t + 600)
        expect(protection.protects(100, frontmost: 200, at: t + 719), "foreground.graceStartsWhenLeaving")
        expect(!protection.protects(100, frontmost: 200, at: t + 720), "foreground.graceExpires")
        expect(protection.protects(300, frontmost: 300, at: t + 720), "foreground.liveIdentityBeatsStaleSnapshot")
        expect(!protection.protects(400, frontmost: 200, at: t + 610), "foreground.unknownNotProtected")
        protection.observe(100, at: t + 721)
        protection.observe(200, at: t + 722)
        expect(protection.protects(100, frontmost: 200, at: t + 841), "foreground.revisitingRenewsGrace")
        expect(protection.protects(100, frontmost: 200, at: t - 10), "foreground.clockRollbackFailsSafe")
    }

    static func processCPUAccounting() {
        func p(_ pid: pid_t, _ cpu: UInt64, _ start: UInt64 = 10) -> ProcessScanner.ProcCPU {
            ProcessScanner.ProcCPU(pid: pid, owner: 0, cpuTime: cpu * 1_000_000_000, startTime: start)
        }
        func close(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.00001 } ?? false }
        var tracker = ProcessCPUTracker()
        expect(tracker.rates(for: [p(1, 10)], at: 0) == nil, "cpu.firstIsBaseline")
        let joined = tracker.rates(for: [p(1, 15), p(2, 700, 20)], at: 10)
        expect(close(joined?[1], 0.5), "cpu.existingHelperMeasured")
        expect(joined?[2] == nil, "cpu.newHelperDoesNotAddLifetime")
        let both = tracker.rates(for: [p(1, 20), p(2, 705, 20)], at: 20)
        expect(close(both?[1], 0.5) && close(both?[2], 0.5), "cpu.helpersSumCorrectly")
        let exited = tracker.rates(for: [p(2, 710, 20)], at: 30)
        expect(close(exited?[2], 0.5) && exited?[1] == nil, "cpu.exitedHelperDoesNotCancelOthers")
        let reused = tracker.rates(for: [p(2, 720, 30)], at: 40)
        expect(reused?[2] == nil, "cpu.pidReuseCannotCreateSpike")
        expect(tracker.rates(for: [p(2, 719, 30)], at: 50)?[2] == nil, "cpu.counterResetCannotUnderflow")
        expect(tracker.rates(for: [p(2, 800, 30)], at: 130) == nil, "cpu.longGapResetsBaseline")
        expect(close(tracker.rates(for: [p(2, 805, 30)], at: 140)?[2], 0.5), "cpu.recoversAfterLongGap")
        expect(tracker.rates(for: [p(2, 810, 30)], at: 139) == nil, "cpu.backwardsClockResets")
        tracker.reset()
        expect(tracker.rates(for: [p(2, 900, 30)], at: 150) == nil, "cpu.wakeResetsBaseline")
        expect(tracker.rates(for: [p(2, 901, 30)], at: 150.1) == nil, "cpu.tooShortCannotSpike")
        expect(tracker.rates(for: [], at: 160)?.isEmpty == true, "cpu.emptyScanIsSafe")
        expect(ProcessCPUCounter(started: 0, time: 10).delta(since: .init(started: 0, time: 5)) == nil,
               "cpu.unknownIdentityNotTrusted")
        // 不同數量級的累計值都遵守相同規則，避免大數溢位或 PID 重用回歸。
        for i in UInt64(1)...100 {
            let old = ProcessCPUCounter(started: i, time: i * 1_000_000_000)
            expect(ProcessCPUCounter(started: i, time: old.time + i).delta(since: old) == i, "cpu.deltaInvariant")
            expect(ProcessCPUCounter(started: i + 1, time: old.time + i).delta(since: old) == nil, "cpu.identityInvariant")
        }
        let nearMax = ProcessCPUCounter(started: 1, time: UInt64.max - 2)
        expect(ProcessCPUCounter(started: 1, time: UInt64.max).delta(since: nearMax) == 2, "cpu.largeCounterSafe")
    }

    static func samplingRecovery() {
        func sample(_ t: Double, total: UInt64 = 0, rate: Double = 0) -> MemorySample {
            MemorySample(date: Date(timeIntervalSince1970: t), total: 8 << 30, appMemory: 3 << 30,
                         wired: 1 << 30, compressed: 0, cached: 0, free: 0, swapUsed: 0, pressure: .normal,
                         swapInsTotal: total, swapOutsTotal: total / 2, swapInRate: rate, swapOutRate: rate / 2)
        }
        let before = sample(100, total: 100 << 20, rate: Double(10 << 20))
        let current = sample(102, total: 108 << 20)
        let smooth = MemoryMonitor.smoothed(current, since: before)
        expect(smooth.swapInRate > Double(4 << 20) && smooth.swapInRate < Double(10 << 20), "rate.smoothedBetweenEndpoints")
        expect(abs(smooth.swapOutRate * 2 - smooth.swapInRate) < 0.01, "rate.inAndOutUseSameClock")
        expect(MemoryMonitor.smoothed(sample(100.1), since: before).swapInRate == before.swapInRate, "rate.shortSampleHolds")
        expect(MemoryMonitor.smoothed(sample(140), since: before).swapInRate == 0, "rate.sleepDropsStaleSpike")
        expect(MemoryMonitor.smoothed(sample(90), since: before).swapInRate == 0, "rate.clockRollbackDropsSpike")
        expect(MemoryMonitor.smoothed(current, since: nil).swapInRate == 0, "rate.firstHasNoInventedActivity")
        let rollback = MemoryMonitor.smoothed(sample(102, total: 1), since: before)
        expect(rollback.swapInRate >= 0 && rollback.swapInRate < before.swapInRate, "rate.counterRollbackDoesNotUnderflow")
    }

    static func hostPortLifetime() {
        let host = MemoryReader.hostPort
        func references() -> mach_port_urefs_t? {
            var refs: mach_port_urefs_t = 0
            return mach_port_get_refs(mach_task_self_, host, mach_port_right_t(MACH_PORT_RIGHT_SEND), &refs) == KERN_SUCCESS ? refs : nil
        }
        let before = references()
        for _ in 0..<100 { _ = MemoryReader.vmStatistics(); _ = SystemReader.cpuLoadTicks() }
        let after = references()
        expect(before != nil && before == after, "ports.repeatedSamplingDoesNotLeakSendRights", "before=\(String(describing: before)) after=\(String(describing: after))")
        expect(MemoryReader.vmStatistics() != nil && SystemReader.cpuLoadTicks() != nil, "ports.cachedHostRemainsUsable")
    }

    static func thermalReadings() {
        expect(!HeatReading(level: 100, speedLimit: 100, state: .nominal).isThrottling, "heat.raw100NotProofOfThrottle")
        expect(!HeatReading(level: 99, speedLimit: nil, state: .fair).isThrottling, "heat.privateScaleNotInterpreted")
        expect(HeatReading(level: nil, speedLimit: 90, state: .nominal).isThrottling, "heat.publicSpeedLimit")
        expect(HeatReading(level: nil, speedLimit: 79, state: .nominal).isSevere, "heat.severeSpeedLimit")
        expect(!HeatReading(level: nil, speedLimit: 80, state: .fair).isSevere, "heat.severeBoundary")
        for state in [ProcessInfo.ThermalState.serious, .critical] {
            expect(HeatReading(level: nil, speedLimit: 100, state: state).isThrottling, "heat.publicThermalState")
            expect(HeatReading(level: nil, speedLimit: nil, state: state).isSevere, "heat.severeThermalState")
            expect(ReleaseEngine.preflight(.zero, swapGrew: false, thermalState: state) == .thermal, "heat.manualAlsoProtected")
        }
        func system(cpu: Double, speed: Int = 100, silicon: Bool = false) -> SystemSample {
            SystemSample(date: Date(), cpuUsage: cpu, loadAverage: 1, cpuTemperature: nil,
                         cpuPower: nil, systemPower: nil, fanRPM: nil, fanCount: 0, thermalLevel: 100,
                         thermalState: .nominal, cpuSpeedLimit: speed, battery: nil,
                         displays: [DisplayInfo(id: 1, width: 2560, height: 1440, refreshRate: 144, isBuiltin: false)],
                         uptime: 1000, thirdPartyAgents: 0, isAppleSilicon: silicon)
        }
        expect(!system(cpu: 0.2).isThrottling, "heat.systemUsesSamePolicy")
        expect(SystemInsight.from(system(cpu: 0.2)) == .healthy, "heat.highRefreshAloneNotAnIssue")
        expect(SystemInsight.from(system(cpu: 0.55)) == .highRefresh, "heat.highRefreshUnderLoadOnly")
        expect(SystemInsight.from(system(cpu: 0.55, silicon: true)) == .healthy, "heat.siliconNotAssumedGPULimited")
        expect(SystemInsight.from(system(cpu: 0.9)) == .busy, "heat.busyHasPriorityOverTip")
        expect(SystemInsight.from(system(cpu: 0.9, speed: 75)) == .throttling, "heat.speedLimitHasPriority")
    }

    static func updateSafety() {
        for version in ["", "1..2", "1.5.0-rc1", "1.5.0+dev", "v1.5.0", "-1.2", "1.２", "1.2.", " 1.5.0", "999999999999999999999.0"] {
            expect(!Updater.isNewer(version, than: "1.4.1"), "update.rejectsInvalidVersion", version)
        }
        expect(Updater.isNewer("1.5.0", than: "1.4.1"), "update.stableVersionAccepted")
        expect(!Updater.isNewer("1.5.0", than: "garbage"), "update.invalidCurrentCannotGuess")
        let valid = "https://github.com/xiewei3536/MemeryButler/releases/download/v1.5.0/MemoryButler.dmg"
        expect(Updater.approvedDownloadURL(valid) != nil, "update.officialAssetAccepted")
        for url in [valid.replacingOccurrences(of: "https:", with: "http:"),
                    valid.replacingOccurrences(of: "github.com", with: "github.com.evil.test"),
                    valid.replacingOccurrences(of: "github.com", with: "attacker@github.com"),
                    valid.replacingOccurrences(of: "xiewei3536", with: "someone"),
                    valid.replacingOccurrences(of: "MemoryButler.dmg", with: "DifferentApp.dmg"),
                    valid + "?redirect=evil", valid + "#ignored",
                    valid.replacingOccurrences(of: "/v1.5.0/", with: "/../") ] {
            expect(Updater.approvedDownloadURL(url) == nil, "update.rejectsUntrustedAsset", url)
        }
        let digest = "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        expect(Updater.validDigest(digest), "update.sha256Accepted")
        expect(Updater.validDigest(nil), "update.legacyReleaseWithoutDigest")
        expect(!Updater.validDigest("sha1:abc") && !Updater.validDigest("sha256:invalid"), "update.badDigestRejected")
        expect(Updater.validBundleMetadata(identifier: Updater.bundleID, version: "1.5.0", expectedVersion: "1.5.0"), "update.appIdentityAccepted")
        expect(!Updater.validBundleMetadata(identifier: "com.fake.app", version: "1.5.0", expectedVersion: "1.5.0"), "update.wrongAppRejected")
        expect(!Updater.validBundleMetadata(identifier: Updater.bundleID, version: "1.4.1", expectedVersion: "1.5.0"), "update.downgradeRejected")
        expect(!Updater.validBundleMetadata(identifier: nil, version: nil, expectedVersion: "1.5.0"), "update.missingAppMetadataRejected")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("memorybutler-hash-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try Data("abc".utf8).write(to: file)
            try Updater.validateDownload(at: file, size: 3, digest: digest)
            expect(true, "update.sha256FileVerified")
            func rejects(size: Int64, digest: String?) -> Bool {
                do { try Updater.validateDownload(at: file, size: size, digest: digest); return false }
                catch { return true }
            }
            expect(rejects(size: 4, digest: digest), "update.truncatedDownloadRejected")
            expect(rejects(size: 3, digest: "sha256:" + String(repeating: "0", count: 64)), "update.tamperedDownloadRejected")
            expect(rejects(size: Updater.maxDownloadSize + 1, digest: nil), "update.oversizedDownloadRejected")
            expect(rejects(size: 0, digest: nil), "update.emptyDownloadRejected")
        } catch { expect(false, "update.hashFixture", error.localizedDescription) }
    }
}

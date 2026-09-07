import Foundation
import IOKit
import IOKit.pwr_mgt
import CoreGraphics
import Darwin

// MARK: - 系統健康取樣（CPU、溫度、功耗、風扇、降頻、電池、螢幕、背景服務）
//
// 老 MacBook 變慢的主因常常不是記憶體而是「熱」：CPU 熱到降頻、kernel_task 佈 CPU 逼系統降溫。
// 這裡把這些數據讀出來翻成白話。溫度／功耗／風扇走 SMC（IOKit，免 root），金鑰因機型而異，
// 讀不到就顯示「—」，不猜。

struct BatteryInfo {
    let cycleCount: Int
    let healthFraction: Double?     // 目前最大容量 / 設計容量
    let temperatureC: Double?
    let isCharging: Bool
    let externalPower: Bool
}

struct DisplayInfo: Identifiable {
    let id: UInt32
    let width: Int
    let height: Int
    let refreshRate: Double         // 0 = 系統未回報（內建螢幕常見），視為 60
    let isBuiltin: Bool
}

struct SystemSample {
    let date: Date
    let cpuUsage: Double?           // 0...1（第一次取樣為 nil）
    let loadAverage: Double         // 1 分鐘
    let cpuTemperature: Double?     // °C
    let cpuPower: Double?           // W，CPU 封裝
    let systemPower: Double?        // W，整機
    let fanRPM: Double?
    let fanCount: Int
    let thermalLevel: Int?          // Intel：machdep.xcpm.cpu_thermal_level 0～100
    let thermalState: ProcessInfo.ThermalState
    let cpuSpeedLimit: Int?         // %，IOPMCopyCPUPowerStatus；< 100 = 正在降頻
    let battery: BatteryInfo?
    let displays: [DisplayInfo]
    let uptime: TimeInterval
    let thirdPartyAgents: Int
    let isAppleSilicon: Bool

    /// 熱降頻中：任一訊號成立即算
    var isThrottling: Bool {
        if let l = cpuSpeedLimit, l < 100 { return true }
        if let t = thermalLevel, t >= 70 { return true }
        return thermalState == .serious || thermalState == .critical
    }
    /// 外接螢幕更新率 > 60Hz（Intel 內顯很吃力）
    var highRefreshExternal: DisplayInfo? {
        displays.first { !$0.isBuiltin && $0.refreshRate > 61 }
    }
}

// MARK: - SMC 讀取（AppleSMC via IOKit）

final class SMCReader {
    // 與 AppleSMC 使用者端介面完全對齊的 80-byte 結構（keyInfo 需補齊到 12 bytes）
    private struct KeyData {
        var key: UInt32 = 0
        var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
        var pLimit: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
        var keyInfo: (UInt32, UInt32, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0)  // dataSize, dataType, attrs, pad
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)                      // 32 bytes
    }

    private var connection: io_connect_t = 0
    private let lock = NSLock()
    private var unavailable = Set<String>()   // 探過一次不存在的金鑰不再重試

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    private static func fourcc(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
    private static func string(_ v: UInt32) -> String {
        String(bytes: [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)], encoding: .ascii) ?? ""
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outSize = MemoryLayout<KeyData>.size
        let kr = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<KeyData>.size, &output, &outSize)
        return kr == kIOReturnSuccess ? output : nil
    }

    /// 讀一個金鑰並依其型別解碼；不存在或型別未知回傳 nil
    func read(_ key: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        if unavailable.contains(key) { return nil }

        var q = KeyData(); q.key = Self.fourcc(key); q.data8 = 9          // kSMCGetKeyInfo
        guard let info = call(&q), info.result == 0, info.keyInfo.0 > 0 else { unavailable.insert(key); return nil }
        var r = KeyData(); r.key = Self.fourcc(key); r.keyInfo = info.keyInfo; r.data8 = 5   // kSMCReadKey
        guard let out = call(&r), out.result == 0 else { unavailable.insert(key); return nil }

        let size = Int(info.keyInfo.0)
        let type = Self.string(info.keyInfo.1)
        let b = withUnsafeBytes(of: out.bytes) { Array($0.prefix(size)) }
        return Self.decode(type: type, bytes: b)
    }

    private static func decode(type: String, bytes b: [UInt8]) -> Double? {
        // spXY / fpXY：定點數，X 整數位、Y 小數位（十六進位字元），如 sp78 = 7.8、sp87 = 8.7、fpe2 = 14.2
        if type.count == 4, type.hasPrefix("sp") || type.hasPrefix("fp"), b.count >= 2,
           let frac = Int(String(type.last!), radix: 16) {
            let raw = UInt16(b[0]) << 8 | UInt16(b[1])
            let value = type.hasPrefix("sp") ? Double(Int16(bitPattern: raw)) : Double(raw)
            return value / Double(1 << frac)
        }
        switch type {
        case "flt ": guard b.count >= 4 else { return nil }
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "ui8 ": return b.first.map { Double($0) }
        case "ui16": guard b.count >= 2 else { return nil }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32": guard b.count >= 4 else { return nil }
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        default: return nil
        }
    }

    /// 依序嘗試候選金鑰，回傳第一個合理的值
    func first(_ keys: [String], valid: (Double) -> Bool) -> Double? {
        for k in keys { if let v = read(k), valid(v) { return v } }
        return nil
    }

    /// 多顆感測器取平均（Apple Silicon 的核心溫度一顆一個金鑰）
    func average(_ keys: [String], valid: (Double) -> Bool) -> Double? {
        let vs = keys.compactMap { read($0) }.filter(valid)
        return vs.isEmpty ? nil : vs.reduce(0, +) / Double(vs.count)
    }
}

// MARK: - 讀取器

enum SystemReader {
    static let isAppleSilicon: Bool = {
        var v: Int32 = 0; var n = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &v, &n, nil, 0) == 0 && v == 1
    }()

    // 溫度候選：Intel 用 CPU proximity / die；Apple Silicon 每顆核心一個金鑰，取平均
    private static let intelTempKeys = ["TCXC", "TC0D", "TC0E", "TC0F", "TC0P", "TCAD", "TC1C"]   // PECI 封裝溫度優先，proximity 最後
    private static let asTempKeys = ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
                                     "Tp0f", "Tp0j", "Tp0n", "Tp0r", "Tp0v", "Tp0z", "Tp1h", "Tp1t", "Tp1p", "Tp1l"]
    private static let cpuPowerKeys = ["PCPT", "PCPC", "PC0R", "PC0C", "PCTR", "PCPR"]   // 封裝總功耗優先
    private static let systemPowerKeys = ["PSTR", "PDTR"]

    static func cpuLoadTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), sys = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + sys + nice, user + sys + nice + idle)
    }

    static func thermalLevel() -> Int? {
        var v: Int32 = 0; var n = MemoryLayout<Int32>.size
        guard sysctlbyname("machdep.xcpm.cpu_thermal_level", &v, &n, nil, 0) == 0 else { return nil }
        return Int(v)
    }

    static func cpuSpeedLimit() -> Int? {
        var ref: Unmanaged<CFDictionary>?
        guard IOPMCopyCPUPowerStatus(&ref) == kIOReturnSuccess,
              let dict = ref?.takeRetainedValue() as? [String: Any],
              let limit = dict["CPU_Speed_Limit"] as? Int else { return nil }
        return limit
    }

    static func battery() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        func prop(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        let design = prop("DesignCapacity") as? Int
        let rawMax = prop("AppleRawMaxCapacity") as? Int
        let health: Double? = (design ?? 0) > 0 && rawMax != nil ? Double(rawMax!) / Double(design!) : nil
        let temp = (prop("Temperature") as? Int).map { Double($0) / 100 }   // 百分之一 °C
        return BatteryInfo(
            cycleCount: prop("CycleCount") as? Int ?? 0,
            healthFraction: health,
            temperatureC: (temp ?? 0) > 0 && (temp ?? 200) < 120 ? temp : nil,
            isCharging: prop("IsCharging") as? Bool ?? false,
            externalPower: prop("ExternalConnected") as? Bool ?? false
        )
    }

    static func displays() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).compactMap { id in
            guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
            return DisplayInfo(id: id, width: mode.pixelWidth, height: mode.pixelHeight,
                               refreshRate: mode.refreshRate, isBuiltin: CGDisplayIsBuiltin(id) != 0)
        }
    }

    /// 第三方 LaunchAgents / LaunchDaemons 數量（開機就常駐的背景服務）
    static func thirdPartyAgents() -> Int {
        let dirs = [
            NSHomeDirectory() + "/Library/LaunchAgents",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
        ]
        return dirs.reduce(0) { sum, dir in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            return sum + names.filter { $0.hasSuffix(".plist") && !$0.hasPrefix("com.apple.") }.count
        }
    }

    static func sample(smc: SMCReader?, previousTicks: (busy: UInt64, total: UInt64)?) -> (SystemSample, (busy: UInt64, total: UInt64)?) {
        let ticks = cpuLoadTicks()
        var usage: Double?
        if let t = ticks, let p = previousTicks, t.total > p.total {
            usage = Double(t.busy - p.busy) / Double(t.total - p.total)
        }
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)

        let tempValid: (Double) -> Bool = { $0 > 5 && $0 < 125 }
        let powerValid: (Double) -> Bool = { $0 > 0.05 && $0 < 500 }
        let temp = isAppleSilicon ? smc?.average(asTempKeys, valid: tempValid)
                                  : smc?.first(intelTempKeys, valid: tempValid)
        let fanCount = min(Int(smc?.read("FNum") ?? 0), 4)
        let fanSpeeds = (0..<fanCount).compactMap { smc?.read("F\($0)Ac") }.filter { $0 >= 0 && $0 < 20000 }
        let fan = fanSpeeds.max()

        let s = SystemSample(
            date: Date(),
            cpuUsage: usage,
            loadAverage: load[0],
            cpuTemperature: temp,
            cpuPower: smc?.first(cpuPowerKeys, valid: powerValid),
            systemPower: smc?.first(systemPowerKeys, valid: powerValid),
            fanRPM: fan,
            fanCount: fanCount,
            thermalLevel: thermalLevel(),
            thermalState: ProcessInfo.processInfo.thermalState,
            cpuSpeedLimit: cpuSpeedLimit(),
            battery: battery(),
            displays: displays(),
            uptime: ProcessInfo.processInfo.systemUptime,
            thirdPartyAgents: thirdPartyAgents(),
            isAppleSilicon: isAppleSilicon
        )
        return (s, ticks)
    }
}

// MARK: - 可觀察模型（系統分頁可見時每 2 秒刷新）

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var current: SystemSample?
    private let smc = SMCReader()
    private var ticks: (busy: UInt64, total: UInt64)?
    private var sampling = false

    func refresh() async {
        guard !sampling else { return }
        sampling = true
        defer { sampling = false }
        let smc = self.smc
        let prev = ticks
        let (sample, newTicks) = await Task.detached(priority: .utility) {
            SystemReader.sample(smc: smc, previousTicks: prev)
        }.value
        ticks = newTicks
        current = sample
    }
}

// MARK: - 白話判讀

enum SystemInsight: Equatable {
    case throttling      // 熱降頻中
    case busy            // CPU 很忙
    case highRefresh     // 外接螢幕高更新率拖累內顯
    case healthy

    static func from(_ s: SystemSample) -> SystemInsight {
        if s.isThrottling { return .throttling }
        if let u = s.cpuUsage, u >= 0.7 { return .busy }
        if s.highRefreshExternal != nil, !s.isAppleSilicon { return .highRefresh }
        return .healthy
    }

    var level: PressureLevel {
        switch self {
        case .throttling: return .critical
        case .busy, .highRefresh: return .warning
        case .healthy: return .normal
        }
    }

    var symbol: String {
        switch self {
        case .throttling:  return "thermometer.high"
        case .busy:        return "cpu.fill"
        case .highRefresh: return "display"
        case .healthy:     return "checkmark.seal.fill"
        }
    }
}

import Foundation
import Darwin

// MARK: - 記憶體壓力等級

enum PressureLevel: Int, Codable {
    case normal = 1
    case warning = 2
    case critical = 4

    var label: String {
        switch self {
        case .normal:   return L("pressure.normal")
        case .warning:  return L("pressure.warning")
        case .critical: return L("pressure.critical")
        }
    }
}

// MARK: - 單次取樣

struct MemorySample {
    let date: Date
    let total: UInt64          // 實體記憶體總量
    let appMemory: UInt64      // App 記憶體 (internal - purgeable)
    let wired: UInt64          // 已固定
    let compressed: UInt64     // 已壓縮
    let cached: UInt64         // 快取檔案 (external + purgeable)
    let free: UInt64           // 完全閒置
    let swapUsed: UInt64       // 交換空間已用
    let pressure: PressureLevel

    /// Activity Monitor 定義的「已使用」
    var used: UInt64 { appMemory &+ wired &+ compressed }
    /// 可再取用（含可回收快取）
    var available: UInt64 { total > used ? total - used : 0 }
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

    static let zero = MemorySample(
        date: .distantPast, total: ProcessInfo.processInfo.physicalMemory,
        appMemory: 0, wired: 0, compressed: 0, cached: 0, free: 0,
        swapUsed: 0, pressure: .normal
    )
}

// MARK: - 低階讀取

enum MemoryReader {

    static let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return size == 0 ? 4096 : UInt64(size)
    }()

    static func vmStatistics() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? stats : nil
    }

    static func pressureLevel() -> PressureLevel {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            return PressureLevel(rawValue: Int(level)) ?? .normal
        }
        return .normal
    }

    static func swapUsage() -> xsw_usage {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        return swap
    }

    /// 目前完全閒置的位元組數（釋放引擎用的快速讀取）
    static func freeBytes() -> UInt64 {
        guard let s = vmStatistics() else { return 0 }
        return UInt64(s.free_count) &* pageSize
    }

    /// 交換空間已用位元組數（釋放引擎的煞車依據，sysctl 讀取極快）
    static func swapUsedBytes() -> UInt64 { swapUsage().xsu_used }

    /// 壓縮池目前佈用的位元組數（釋放引擎的煞車依據）
    static func compressedBytes() -> UInt64 {
        guard let s = vmStatistics() else { return 0 }
        return UInt64(s.compressor_page_count) &* pageSize
    }

    /// 單一程序的實體佔用（與「活動監視器」的「記憶體」欄位同口徑）與累計 CPU 時間（mach 絕對時間單位）
    static func usage(of pid: pid_t) -> (footprint: UInt64, cpuTime: UInt64)? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard rc == 0 else { return nil }
        return (info.ri_phys_footprint, info.ri_user_time &+ info.ri_system_time)
    }

    static func sample() -> MemorySample {
        let total = ProcessInfo.processInfo.physicalMemory
        guard let s = vmStatistics() else {
            return MemorySample(
                date: Date(), total: total, appMemory: 0, wired: 0, compressed: 0,
                cached: 0, free: 0, swapUsed: 0, pressure: pressureLevel()
            )
        }
        let p = pageSize
        let free       = UInt64(s.free_count) &* p
        let wired      = UInt64(s.wire_count) &* p
        let compressed = UInt64(s.compressor_page_count) &* p
        let internalB  = UInt64(s.internal_page_count) &* p
        let purgeable  = UInt64(s.purgeable_count) &* p
        let external   = UInt64(s.external_page_count) &* p
        let appMem     = internalB > purgeable ? internalB - purgeable : internalB

        return MemorySample(
            date: Date(),
            total: total,
            appMemory: appMem,
            wired: wired,
            compressed: compressed,
            cached: external &+ purgeable,
            free: free,
            swapUsed: swapUsage().xsu_used,
            pressure: pressureLevel()
        )
    }
}

// MARK: - 白話健康判讀
//
// 把數字翻成「現在順不順、該做什麼」。這裡的門檻是經驗法則，不追求精確，
// 重點是給一般使用者一句聽得懂、做得到的建議。

enum HealthInsight: Equatable {
    case healthy        // 記憶體充足
    case compressing    // 靠壓縮撐著：開始吃緊
    case swapping       // 已在用磁碟頂替：這才是變卡的主因
    case critical       // 極度緊繃

    static func from(_ s: MemorySample) -> HealthInsight {
        guard s.total > 0 else { return .healthy }
        if s.pressure == .critical { return .critical }
        let tightNow  = s.pressure == .warning || s.compressed >= s.total / 5   // 8GB：壓縮 ≥ 1.6GB
        let heavySwap = s.swapUsed >= s.total / 4                                // 8GB：swap ≥ 2GB
        let someSwap  = s.swapUsed >= s.total / 8                                // 8GB：swap ≥ 1GB
        // swap 很大 = 工作集早已超過實體記憶體，就算此刻 free 很多（例如剛釋放完），
        // 切回那些被換出的 App 還是會卡；這時不能報「順暢」，要老實說只有關 App 有用
        if heavySwap || (someSwap && tightNow) { return .swapping }
        if tightNow { return .compressing }
        return .healthy
    }

    var title: String {
        switch self {
        case .healthy:     return L("insight.healthy")
        case .compressing: return L("insight.compressing.title")
        case .swapping:    return L("insight.swapping.title")
        case .critical:    return L("insight.critical.title")
        }
    }

    /// 給使用者的一句話建議（充足時不囉唆）
    var advice: String? {
        switch self {
        case .healthy:     return nil
        case .compressing: return L("insight.compressing.advice")
        case .swapping:    return L("insight.swapping.advice")
        case .critical:    return L("insight.critical.advice")
        }
    }

    var symbol: String {
        switch self {
        case .healthy:     return "checkmark.seal.fill"
        case .compressing: return "arrow.down.right.and.arrow.up.left"
        case .swapping:    return "externaldrive.fill.badge.exclamationmark"
        case .critical:    return "exclamationmark.octagon.fill"
        }
    }

    /// 對應的壓力等級色（沿用系統色，亮/暗模式自動適配）
    var level: PressureLevel {
        switch self {
        case .healthy:     return .normal
        case .compressing: return .warning
        case .swapping:    return .warning
        case .critical:    return .critical
        }
    }
}

// MARK: - 格式化工具

enum Fmt {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        return f
    }()

    static func bytes(_ v: UInt64) -> String { formatter.string(fromByteCount: Int64(v)) }
    static func bytes(_ v: Int64) -> String { formatter.string(fromByteCount: v) }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// 開機時間這類長度：「3 天 4 小時」或「6 小時 20 分」
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86400, hours = (total % 86400) / 3600, minutes = (total % 3600) / 60
        return days > 0 ? LF("fmt.daysHours", days, hours) : LF("fmt.hoursMinutes", hours, minutes)
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let timeWithSeconds: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

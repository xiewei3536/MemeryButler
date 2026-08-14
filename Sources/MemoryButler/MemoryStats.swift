import Foundation
import Darwin

// MARK: - 記憶體壓力等級

enum PressureLevel: Int, Codable {
    case normal = 1
    case warning = 2
    case critical = 4

    var label: String {
        switch self {
        case .normal:   return "良好"
        case .warning:  return "偏高"
        case .critical: return "緊繃"
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

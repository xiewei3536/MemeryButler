import SwiftUI
import AppKit

@main
struct MemoryButlerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if SelfTest.isEnabled { Task { await SelfTest.run() } }
    }
}

// MARK: - 自我測試（開發 / CI 用，不需點 UI）
//
//   MEMORYBUTLER_SELFTEST=1 dist/MemoryButler.app/Contents/MacOS/MemoryButler
//
// 啟動後直接：取樣 → 掃描 App 佔用 → 跑一次釋放 → 印出結果 → 結束。
// MenuBarExtra 面板無法用 System Events 自動化，這是驗證兩條核心路徑最實際的方法。

enum SelfTest {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["MEMORYBUTLER_SELFTEST"] == "1" }

    @MainActor
    static func run() async {
        let model = AppModel.shared
        let s = model.monitor.current
        print("[selftest] total=\(Fmt.bytes(s.total)) used=\(Fmt.percent(s.usedFraction)) "
              + "available=\(Fmt.bytes(s.available)) swap=\(Fmt.bytes(s.swapUsed)) "
              + "pressure=\(s.pressure) insight=\(HealthInsight.from(s))")

        await model.apps.refresh()
        print("[selftest] apps: \(model.apps.rows.count) rows, self=\(Fmt.bytes(model.apps.selfFootprint))")
        for r in model.apps.rows.prefix(5) {
            print("[selftest]   \(Fmt.bytes(r.footprint))  \(r.processCount) proc  \(r.name)")
        }
        if let o = model.apps.other {
            print("[selftest]   \(Fmt.bytes(o.footprint))  \(o.processCount) proc  [\(o.name)]")
        }

        await model.system.refresh()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await model.system.refresh()
        await model.apps.refresh()   // 第二次掃描才有 CPU%
        if let sys = model.system.current {
            print("[selftest] system: cpu=\(sys.cpuUsage.map { Fmt.percent($0) } ?? "-") temp=\(sys.cpuTemperature.map { String(format: "%.1f°C", $0) } ?? "-") "
                  + "cpuPower=\(sys.cpuPower.map { String(format: "%.1fW", $0) } ?? "-") sysPower=\(sys.systemPower.map { String(format: "%.1fW", $0) } ?? "-") "
                  + "fan=\(sys.fanRPM.map { "\(Int($0))rpm" } ?? "-")x\(sys.fanCount) thermalLevel=\(sys.thermalLevel.map(String.init) ?? "-") "
                  + "speedLimit=\(sys.cpuSpeedLimit.map(String.init) ?? "-") state=\(sys.thermalState.rawValue) "
                  + "battery=\(sys.battery.map { "\(Int(($0.healthFraction ?? 0) * 100))%/\($0.cycleCount)cyc" } ?? "-") "
                  + "displays=\(sys.displays.map { "\($0.width)x\($0.height)@\(Int($0.refreshRate))" }) agents=\(sys.thirdPartyAgents) insight=\(SystemInsight.from(sys))")
        }
        for r in model.apps.rows.prefix(3) {
            print("[selftest]   cpu \(r.cpuFraction.map { String(format: "%.0f%%", $0 * 100) } ?? "-")  \(r.name)")
        }

        // MEMORYBUTLER_SNAPSHOT_DIR=/path → 把每個分頁離屏渲染成 PNG（不需螢幕錄製權限即可檢視畫面）
        if let dir = ProcessInfo.processInfo.environment["MEMORYBUTLER_SNAPSHOT_DIR"], !dir.isEmpty {
            renderSnapshots(to: dir)
        }

        switch await model.engine.release(trigger: .manual) {
        case .released(let e):
            print("[selftest] release: reclaimed=\(Fmt.bytes(e.reclaimed)) ballast=\(Fmt.bytes(e.ballast ?? 0)) "
                  + "stop=\(e.stopReason?.rawValue ?? "-") swapDelta=\(Fmt.bytes(e.swapDelta ?? 0)) "
                  + "in \(String(format: "%.1f", e.duration))s")
        case .skipped(let why):
            print("[selftest] release: skipped (\(why.rawValue)) — declined because it could only hurt")
        case .busy:
            print("[selftest] release: engine busy")
        }
        exit(0)
    }

    @MainActor
    private static func renderSnapshots(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for tab in PopoverTab.allCases {
            render(PopoverView(initialTab: tab), name: "\(tab)", dir: dir)
        }
        // ScrollView 內容不會被 ImageRenderer 畫出來，App 列表另外直接渲染（含兩段式確認狀態）
        let apps = AppModel.shared.apps
        render(
            AppRowsView(rows: apps.rows, other: apps.other,
                        confirmingId: .constant(apps.rows.first?.id))
                .padding(14)
                .frame(width: 332),
            name: "apps-rows", dir: dir
        )
    }

    /// AppKit 支援的控制項（分頁選擇器、開關、連結）在 ImageRenderer 裡會是黃色佔位，屬正常現象
    @MainActor
    private static func render<V: View>(_ view: V, name: String, dir: String) {
        let renderer = ImageRenderer(content: view.background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("[snapshot] \(name): render failed")
            return
        }
        let path = "\(dir)/\(name).png"
        try? png.write(to: URL(fileURLWithPath: path))
        print("[snapshot] \(path) \(Int(image.size.width))x\(Int(image.size.height))pt")
    }
}

/// 選單列常駐標籤：晶片圖示 +（可選）即時使用率
struct MenuBarLabel: View {
    @ObservedObject private var monitor = AppModel.shared.monitor
    @ObservedObject private var settings = AppModel.shared.settings

    var body: some View {
        if settings.showPercentInMenuBar {
            HStack(spacing: 3) {
                Image(systemName: "memorychip")
                Text(Fmt.percent(monitor.current.usedFraction))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()   // 71%→72% 時選單列不左右抖動
            }
        } else {
            Image(systemName: "memorychip")
        }
    }
}

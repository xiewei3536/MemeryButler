import SwiftUI
import AppKit

/// 「系統」分頁：CPU、溫度、功耗、風扇、降頻、電池、螢幕、背景服務——老 MacBook 變慢的另一半原因
struct SystemView: View {
    @ObservedObject private var system = AppModel.shared.system
    @ObservedObject private var settings = AppModel.shared.settings

    var body: some View {
        VStack(spacing: 10) {
            if let s = system.current {
                insight(for: s)
                tiles(for: s)
                infoCard(for: s)
            } else {
                placeholder
            }
        }
        .task {
            // 第一次取兩個樣本（CPU 使用率要兩點才算得出），之後每 2 秒；面板關著時不取樣
            await system.refresh()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            while !Task.isCancelled {
                if AppModel.shared.panel.isVisible || system.current?.cpuUsage == nil { await system.refresh() }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L("sys.reading"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: 白話判讀

    private func insight(for s: SystemSample) -> some View {
        let insight = SystemInsight.from(s)
        let title: String
        var advice: String?
        switch insight {
        case .throttling:
            title = L("insight.sys.throttling.title")
            advice = L("insight.sys.throttling.advice")
        case .busy:
            title = L("insight.sys.busy.title")
            advice = L("insight.sys.busy.advice")
        case .highRefresh:
            title = LF("insight.sys.highRefresh.title", Int(s.highRefreshExternal?.refreshRate ?? 0))
            advice = L("sys.display.hint")
        case .healthy:
            title = L("insight.sys.healthy")
        }
        return InsightCard(symbol: insight.symbol, level: insight.level, title: title, advice: advice)
            .animation(.easeInOut(duration: 0.3), value: insight)
    }

    // MARK: 六格數據

    private func tiles(for s: SystemSample) -> some View {
        let dash = L("sys.na")
        // 窄格子裡只放得下一行：等級數字，正在降速時才附上速度
        let throttle: String = {
            let speed = s.cpuSpeedLimit ?? 100
            if let level = s.thermalLevel {
                return speed < 100 ? LF("sys.throttle.value", level, speed) : "\(level)"
            }
            if speed < 100 { return LF("sys.throttle.speedOnly", speed) }
            return s.thermalState == .nominal || s.thermalState == .fair ? L("sys.throttle.none") : L("sys.throttle.hot")
        }()
        // 窄格只放健康百分比；循環次數放到下方資訊卡
        let battery: String = s.battery?.healthFraction.map { Fmt.percent($0) } ?? dash
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            StatTile(title: L("sys.cpu"),
                     value: s.cpuUsage.map { Fmt.percent(min($0, 1)) } ?? dash,
                     symbol: "cpu", help: L("help.sys.cpu"))
            StatTile(title: L("sys.temp"),
                     value: s.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? dash,
                     symbol: "thermometer.medium", help: L("help.sys.temp"))
            StatTile(title: L("sys.power"),
                     value: s.cpuPower.map { String(format: "%.1f W", $0) } ?? dash,
                     symbol: "bolt", help: L("help.sys.power"))
            StatTile(title: L("sys.fan"),
                     value: s.fanRPM.map { LF("sys.fan.value", Int($0)) + (s.fanCount > 1 ? " ×\(s.fanCount)" : "") } ?? dash,
                     symbol: "fanblades", help: L("help.sys.fan"))
            StatTile(title: L("sys.throttle"), value: throttle,
                     symbol: "gauge.with.dots.needle.33percent", help: L("help.sys.throttle"))
            StatTile(title: L("sys.battery"), value: battery,
                     symbol: s.battery?.externalPower == true ? "battery.100percent.bolt" : "battery.75percent",
                     help: L("help.sys.battery"))
        }
    }

    // MARK: 其他資訊

    private func infoCard(for s: SystemSample) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                if let d = s.displays.first(where: { !$0.isBuiltin }) ?? s.displays.first {
                    let hz = d.refreshRate > 0 ? Int(d.refreshRate.rounded()) : 60
                    infoRow(L("sys.display"), "\(d.width)×\(d.height) @ \(hz)Hz",
                            warning: s.highRefreshExternal != nil && !s.isAppleSilicon)
                    if s.highRefreshExternal != nil, !s.isAppleSilicon {
                        Text(L("sys.display.hint"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let w = s.systemPower {
                    infoRow(L("sys.systemPower"), String(format: "%.1f W", w))
                }
                if let b = s.battery, b.cycleCount > 0 {
                    infoRow(L("sys.battery.cycles"), LF("sys.battery.cycles.value", b.cycleCount)
                            + (b.temperatureC.map { String(format: " · %.0f°C", $0) } ?? ""))
                }
                infoRow(L("sys.uptime"), Fmt.duration(s.uptime))
                HStack {
                    infoRow(L("sys.agents"), LF("sys.agents.value", s.thirdPartyAgents))
                    Button(L("sys.agents.open")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.mini)
                    .help(L("help.sys.agents"))
                }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String, warning: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(warning ? Color(nsColor: .systemOrange) : Color.primary)
            Spacer(minLength: 0)
        }
    }
}

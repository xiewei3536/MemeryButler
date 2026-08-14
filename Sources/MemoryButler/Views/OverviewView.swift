import SwiftUI
import Charts

struct OverviewView: View {
    @ObservedObject private var monitor = AppModel.shared.monitor
    @ObservedObject private var engine = AppModel.shared.engine
    @ObservedObject private var autopilot = AppModel.shared.autopilot
    @ObservedObject private var settings = AppModel.shared.settings
    @ObservedObject private var updater = AppModel.shared.updater

    var body: some View {
        VStack(spacing: 10) {
            if updater.updateAvailable { UpdateBanner() }
            gaugeSection
            tileGrid
            HistoryChartCard()
            ReleaseButton()
            autoStatusCard
        }
    }

    // MARK: 儀表 + 摘要

    private var gaugeSection: some View {
        let s = monitor.current
        return HStack(spacing: 14) {
            GaugeRing(
                fraction: s.usedFraction,
                level: s.pressure,
                centerTitle: Fmt.percent(s.usedFraction),
                centerSubtitle: L("gauge.used")
            )
            .frame(width: 116, height: 116)

            VStack(alignment: .leading, spacing: 7) {
                PressureChip(level: s.pressure)
                summaryLine(title: L("sum.available"), value: Fmt.bytes(s.available), emphasized: true)
                summaryLine(title: L("sum.total"), value: Fmt.bytes(s.total))
                summaryLine(title: L("sum.swap"), value: Fmt.bytes(s.swapUsed))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func summaryLine(title: String, value: String, emphasized: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: emphasized ? 13 : 11.5,
                              weight: emphasized ? .semibold : .regular,
                              design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    // MARK: 四格統計

    private var tileGrid: some View {
        let s = monitor.current
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())],
                         spacing: 8) {
            StatTile(title: L("tile.app"), value: Fmt.bytes(s.appMemory), symbol: "square.grid.2x2")
            StatTile(title: L("tile.wired"), value: Fmt.bytes(s.wired), symbol: "lock")
            StatTile(title: L("tile.compressed"), value: Fmt.bytes(s.compressed), symbol: "archivebox")
            StatTile(title: L("tile.cached"), value: Fmt.bytes(s.cached), symbol: "internaldrive")
        }
    }

    // MARK: 自動釋放狀態

    private var autoStatusCard: some View {
        Card {
            HStack(spacing: 9) {
                Image(systemName: settings.autoEnabled ? "bolt.badge.checkmark.fill" : "bolt.slash.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(settings.autoEnabled ? Theme.series : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(settings.autoEnabled ? L("auto.on") : L("auto.off"))
                            .font(.system(size: 12, weight: .medium))
                        if settings.autoEnabled {
                            cooldownBadge
                        }
                    }
                    Text(settings.autoEnabled ? autopilot.lastDecision : L("auto.hint.off"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $settings.autoEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
        }
    }

    private var cooldownBadge: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = autopilot.cooldownRemaining
            if remaining > 0 {
                let t = "\(Int(remaining) / 60):\(String(format: "%02d", Int(remaining) % 60))"
                Text(LF("auto.cooldown", t))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
        }
    }
}

// MARK: - 更新橫幅

struct UpdateBanner: View {
    @ObservedObject private var updater = AppModel.shared.updater
    @ObservedObject private var settings = AppModel.shared.settings

    var body: some View {
        Card {
            HStack(spacing: 9) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.series)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LF("update.banner.title", "v" + (updater.availableVersion ?? "")))
                        .font(.system(size: 12, weight: .semibold))
                    detail
                }
                Spacer(minLength: 0)
                trailing
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch updater.status {
        case .downloading(let p):
            ProgressView(value: p)
                .progressViewStyle(.linear)
                .controlSize(.small)
                .frame(width: 150)
        case .installing:
            Text(L("update.installing"))
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        case .restarting:
            Text(L("update.restarting"))
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch updater.status {
        case .available:
            Button {
                Task { await AppModel.shared.updater.downloadAndInstall() }
            } label: {
                Text(L("update.banner.button"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accentGradient))
            }
            .buttonStyle(.plain)
        case .downloading(let p):
            Text(LF("update.downloading", Int(p * 100)))
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.secondary)
        case .installing, .restarting:
            ProgressView().controlSize(.small)
        default:
            EmptyView()
        }
    }
}

// MARK: - 歷史曲線卡（單一序列:藍;0–100 固定刻度、零基線;懸停讀值）

struct HistoryChartCard: View {
    @ObservedObject private var monitor = AppModel.shared.monitor
    @ObservedObject private var settings = AppModel.shared.settings
    @State private var hovered: MemorySample?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("chart.title"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    readout
                }
                chart
                    .frame(height: 58)
            }
        }
    }

    /// 懸停時顯示該時間點讀值，否則顯示目前值 —— 數值標籤永遠可見
    private var readout: some View {
        let s = hovered ?? monitor.current
        return HStack(spacing: 4) {
            Text(Fmt.timeWithSeconds.string(from: s.date))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
            Text(Fmt.percent(s.usedFraction))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private var chart: some View {
        let samples = monitor.history
        return Chart {
            ForEach(samples, id: \.date) { s in
                AreaMark(
                    x: .value("t", s.date),
                    y: .value("used", s.usedFraction * 100)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.series.opacity(0.30), Theme.series.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("t", s.date),
                    y: .value("used", s.usedFraction * 100)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .foregroundStyle(Theme.series)
            }
            if let h = hovered {
                RuleMark(x: .value("t", h.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.primary.opacity(0.25))
                PointMark(
                    x: .value("t", h.date),
                    y: .value("used", h.usedFraction * 100)
                )
                .symbolSize(46)
                .foregroundStyle(Theme.series)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt):
                            let origin = geo[proxy.plotAreaFrame].origin
                            if let date: Date = proxy.value(atX: pt.x - origin.x) {
                                hovered = samples.min(by: {
                                    abs($0.date.timeIntervalSince(date)) <
                                    abs($1.date.timeIntervalSince(date))
                                })
                            }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
    }
}

// MARK: - 釋放按鈕

struct ReleaseButton: View {
    @ObservedObject private var engine = AppModel.shared.engine
    @ObservedObject private var settings = AppModel.shared.settings

    var body: some View {
        Button(action: { AppModel.shared.manualRelease() }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background)
                label
                    .foregroundStyle(.white)
            }
            .frame(height: 40)
        }
        .buttonStyle(.plain)
        .disabled(engine.isRunning)
        .animation(.easeInOut(duration: 0.25), value: engine.state)
    }

    private var background: AnyShapeStyle {
        switch engine.state {
        case .done:
            return AnyShapeStyle(Color(nsColor: .systemGreen))
        default:
            return AnyShapeStyle(Theme.accentGradient)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch engine.state {
        case .idle:
            HStack(spacing: 7) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                Text(L("btn.release"))
                    .font(.system(size: 13.5, weight: .semibold))
            }
        case .running(let progress):
            HStack(spacing: 9) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 130)
                Text(L("btn.releasing"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
        case .done(let reclaimed):
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(reclaimed > (50 << 20)
                     ? LF("btn.freed", Fmt.bytes(reclaimed))
                     : L("btn.tidied"))
                    .font(.system(size: 13.5, weight: .semibold))
            }
        }
    }
}

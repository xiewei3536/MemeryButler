import SwiftUI
import Charts

struct OverviewView: View {
    /// 卡片上的「看看是哪些 App」「看溫度」：切到對應分頁
    var show: (PopoverTab) -> Void

    // 即時數據只透過節拍器取得：面板關著時不重算（見 PanelFeed）
    @ObservedObject private var feed = AppModel.shared.feed
    @ObservedObject private var autopilot = AppModel.shared.autopilot
    @ObservedObject private var settings = AppModel.shared.settings
    @ObservedObject private var updater = AppModel.shared.updater
    @ObservedObject private var panel = AppModel.shared.panel
    private var monitor: MemoryMonitor { AppModel.shared.monitor }

    init(show: @escaping (PopoverTab) -> Void = { _ in }) {
        self.show = show
    }

    var body: some View {
        // 由上到下依「該做什麼」排：判讀與動作在前，被動的曲線放最後——
        // 小螢幕（1280×720 只有 ~535pt 可放內容）需要捲動時，先被捲掉的是曲線
        VStack(spacing: 9) {
            if updater.updateAvailable { UpdateBanner() }
            gaugeSection
            LagCard(show: show)
            statsStrip
            ReleaseButton()
            autoStatusCard
            HistoryChartCard()
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
            .frame(width: 108, height: 108)

            VStack(alignment: .leading, spacing: 7) {
                PressureChip(level: s.pressure)
                    .help(L("help.pressure"))
                summaryLine(title: L("sum.available"), value: Fmt.bytes(s.available), emphasized: true)
                    .help(L("help.available"))
                summaryLine(title: L("sum.total"), value: Fmt.bytes(s.total))
                swapLine(s)
                    .help(L("help.swap"))
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
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    /// 交換空間：此刻正在換入時附上速率（這才是「現在卡不卡」）
    private func swapLine(_ s: MemorySample) -> some View {
        HStack(spacing: 6) {
            summaryLine(title: L("sum.swap"), value: Fmt.bytes(s.swapUsed))
            if s.swapInRate >= 512 * 1024 {
                HStack(spacing: 1) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text(Fmt.rate(s.swapInRate))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(s.swapInRate >= HealthInsight.thrashingRate
                                 ? Color(nsColor: .systemOrange) : Color.secondary)
                .help(L("help.swapRate"))
            }
        }
    }

    // MARK: 四項細目（一列，數字在上、名稱在下）

    private var statsStrip: some View {
        let s = monitor.current
        return HStack(spacing: 0) {
            stat(L("tile.app"), Fmt.bytes(s.appMemory), help: L("help.app"))
            stripDivider
            stat(L("tile.wired"), Fmt.bytes(s.wired), help: L("help.wired"))
            stripDivider
            stat(L("tile.compressed"), Fmt.bytes(s.compressed), help: L("help.compressed"))
            stripDivider
            stat(L("tile.cached"), Fmt.bytes(s.cached), help: L("help.cached"))
        }
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func stat(_ title: String, _ value: String, help: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
        .help(help)
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 0.5, height: 22)
    }

    // MARK: 自動釋放狀態

    private var autoStatusCard: some View {
        let s = monitor.current
        return Card {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: settings.autoEnabled ? "bolt.badge.checkmark.fill" : "bolt.slash.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(settings.autoEnabled ? Theme.series : .secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(settings.autoEnabled ? L("auto.on") : L("auto.off"))
                            .font(.system(size: 12, weight: .medium))
                        if settings.autoEnabled {
                            if autopilot.isSuspended {
                                badge(L("auto.paused"))
                                    .help(L("help.autoPaused"))
                            } else {
                                cooldownBadge
                            }
                        }
                    }
                    if settings.autoEnabled {
                        // 監督心跳:呼吸燈 + 即時壓力/可用量/檢查次數
                        HStack(spacing: 5) {
                            PulsingDot(color: s.pressure.color)
                            Text(LF("auto.live", s.pressure.label,
                                    Fmt.bytes(s.available), autopilot.evaluationCount))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        // 最近一次決策(帶時間戳)
                        if let at = autopilot.lastDecisionAt {
                            Text("\(Fmt.time.string(from: at))  \(autopilot.lastDecision)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(L("auto.hint.off"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                SwitchToggle(L("set.auto.title"), isOn: $settings.autoEnabled, size: .mini)
            }
        }
    }

    @ViewBuilder
    private var cooldownBadge: some View {
        // 面板看不見時不需要每秒重算倒數
        if panel.isVisible {
            TimelineView(.periodic(from: .now, by: 1)) { _ in cooldownLabel }
        } else {
            cooldownLabel
        }
    }

    @ViewBuilder
    private var cooldownLabel: some View {
        let remaining = autopilot.cooldownRemaining
        if remaining > 0 {
            let t = "\(Int(remaining) / 60):\(String(format: "%02d", Int(remaining) % 60))"
            badge(LF("auto.cooldown", t))
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
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
    @ObservedObject private var feed = AppModel.shared.feed
    @ObservedObject private var settings = AppModel.shared.settings
    @State private var hovered: MemorySample?
    private var monitor: MemoryMonitor { AppModel.shared.monitor }

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
                    .frame(height: 42)
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
                .monospacedDigit()
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
            .frame(height: 38)
        }
        .buttonStyle(.plain)
        .disabled(engine.isRunning)
        .help(L("help.release"))
        .animation(.easeInOut(duration: 0.25), value: engine.state)
    }

    private var background: AnyShapeStyle {
        switch engine.state {
        case .done:
            return AnyShapeStyle(Color(nsColor: .systemGreen))
        case .skipped:
            return AnyShapeStyle(Color(nsColor: .systemOrange))
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
                    .monospacedDigit()
            }
        case .skipped(let why):
            // 老實說：此刻出手只會害到使用者，所以管家不做
            HStack(spacing: 7) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(L("btn.skipped.\(why.rawValue)"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12)
        }
    }
}

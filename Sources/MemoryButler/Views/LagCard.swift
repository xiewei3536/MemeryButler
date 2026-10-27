import SwiftUI
import AppKit

// MARK: - 順暢度：把「記憶體、失控程序、熱、螢幕、久未重開機」合成一個判斷

enum Smoothness: Int, Comparable {
    case smooth = 0, sluggish = 1, laggy = 2

    static func < (a: Smoothness, b: Smoothness) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .smooth:   return L("lag.title.smooth")
        case .sluggish: return L("lag.title.sluggish")
        case .laggy:    return L("lag.title.laggy")
        }
    }

    var level: PressureLevel {
        switch self {
        case .smooth:   return .normal
        case .sluggish: return .warning
        case .laggy:    return .critical
        }
    }

    var symbol: String {
        switch self {
        case .smooth:   return "checkmark.seal.fill"
        case .sluggish: return "exclamationmark.circle.fill"
        case .laggy:    return "exclamationmark.triangle.fill"
        }
    }
}

/// 卡片上的一列：一個讓 Mac 變卡的具體原因，或一條改善建議
struct LagItem: Identifiable {
    enum Kind {
        case memory
        case runaway(Runaway)       // 此刻仍在失控
        case calmed(Runaway)        // 已降到背景、目前平靜（建議區，附「恢復」）
        case heat
        case refresh
        case reboot

        var isHeat: Bool { if case .heat = self { return true } else { return false } }
    }

    let id: String
    let kind: Kind
    let severity: Smoothness      // .smooth = 建議（不影響判斷）
    let symbol: String
    let title: String
    let detail: String

    var isTip: Bool { severity == .smooth }

    static func build(sample s: MemorySample, report: LagReport) -> [LagItem] {
        var items: [LagItem] = []

        switch HealthInsight.from(s) {
        case .critical:
            items.append(LagItem(id: "mem", kind: .memory, severity: .laggy, symbol: HealthInsight.critical.symbol,
                                 title: L("insight.critical.title"), detail: L("insight.critical.advice")))
        case .thrashing:
            items.append(LagItem(id: "mem", kind: .memory,
                                 severity: s.swapInRate >= HealthInsight.severeThrashingRate ? .laggy : .sluggish,
                                 symbol: HealthInsight.thrashing.symbol,
                                 title: L("insight.thrashing.title"),
                                 detail: LF("lag.thrashing.detail", Fmt.rate(s.swapInRate))))
        case .swapping:
            items.append(LagItem(id: "mem", kind: .memory, severity: .sluggish, symbol: HealthInsight.swapping.symbol,
                                 title: L("insight.swapping.title"),
                                 detail: LF("lag.swap.detail", Fmt.bytes(s.swapUsed))))
        case .compressing where s.pressure == .warning:
            items.append(LagItem(id: "mem", kind: .memory, severity: .sluggish, symbol: HealthInsight.compressing.symbol,
                                 title: L("insight.compressing.title"), detail: L("insight.compressing.advice")))
        default:
            break
        }

        let hot = report.heat
        for r in report.runaways.filter(\.isActive).prefix(2) {
            let detail = r.isDemoted
                ? L("lag.runaway.demoted")
                : LF("lag.runaway.detail", max(1, Int(r.duration / 60)))
            items.append(LagItem(
                id: r.id, kind: .runaway(r),
                severity: (hot != nil && r.cpu >= 0.8 && !r.isDemoted) ? .laggy : .sluggish,
                symbol: r.isDemoted ? "tortoise.fill" : "flame.fill",
                title: LF("lag.runaway.title", r.name, Int((r.cpu * 100).rounded())),
                detail: detail))
        }

        if let h = hot {
            let detail: String
            if let limit = h.speedLimit, limit < 100 {
                detail = LF("lag.heat.detail.speed", limit)
            } else if let level = h.level {
                detail = LF("lag.heat.detail", level)
            } else {
                detail = L("lag.heat.detail.generic")
            }
            items.append(LagItem(id: "heat", kind: .heat, severity: h.isSevere ? .laggy : .sluggish,
                                 symbol: "thermometer.high", title: L("lag.heat.title"), detail: detail))
        }

        for r in report.runaways.filter({ !$0.isActive && $0.isDemoted }).prefix(2) {
            items.append(LagItem(id: r.id, kind: .calmed(r), severity: .smooth, symbol: "tortoise.fill",
                                 title: LF("lag.calmed.title", r.name, Int((r.cpu * 100).rounded())), detail: ""))
        }

        if let hz = report.highRefreshHz {
            items.append(LagItem(id: "refresh", kind: .refresh, severity: .smooth, symbol: "display",
                                 title: LF("lag.tip.refresh", hz), detail: ""))
        }
        if let days = report.rebootDays {
            items.append(LagItem(id: "reboot", kind: .reboot, severity: .smooth, symbol: "arrow.clockwise",
                                 title: LF("lag.tip.reboot", days, Fmt.bytes(s.swapUsed)), detail: ""))
        }
        return items
    }

    static func verdict(_ items: [LagItem]) -> Smoothness {
        items.map(\.severity).max() ?? .smooth
    }
}

// MARK: - 總覽的「順暢度」卡片

struct LagCard: View {
    /// 切到其他分頁（看是哪些 App、看溫度）
    var show: (PopoverTab) -> Void = { _ in }

    // 只觀察節拍器：面板看得見時才重繪（LagDetector 的變動也經由它轉發）
    @ObservedObject private var feed = AppModel.shared.feed
    private var lag: LagDetector { AppModel.shared.lag }

    var body: some View {
        let items = LagItem.build(sample: AppModel.shared.monitor.current, report: lag.report)
        let issues = items.filter { !$0.isTip }
        let tips = items.filter(\.isTip)
        let verdict = LagItem.verdict(items)

        VStack(alignment: .leading, spacing: 8) {
            if issues.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    icon(verdict.symbol, verdict.level.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("lag.card.smooth"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(L("lag.smooth.detail"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                ForEach(issues) { issueRow($0) }
            }

            if !tips.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.leading, 26)
                ForEach(tips) { tipRow($0) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(verdict.level.color.opacity(verdict == .smooth ? 0.08 : 0.12))
        )
        .animation(.easeInOut(duration: 0.25), value: verdict)
    }

    private func icon(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 18)
            .padding(.top, 1)
    }

    @ViewBuilder
    private func issueRow(_ item: LagItem) -> some View {
        switch item.kind {
        case .runaway(let r):
            // 失控程序：標題、說明、動作按鈕各一行
            HStack(alignment: .top, spacing: 8) {
                icon(item.symbol, item.severity.level.color)
                VStack(alignment: .leading, spacing: 3) {
                    issueText(item)
                    runawayActions(r)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        default:
            // 記憶體、熱：整列可點，帶右箭頭，直接切到能處理的分頁
            Button { show(item.kind.isHeat ? .system : .apps) } label: {
                HStack(alignment: .center, spacing: 8) {
                    icon(item.symbol, item.severity.level.color)
                        .frame(maxHeight: .infinity, alignment: .top)
                    VStack(alignment: .leading, spacing: 2) { issueText(item) }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.kind.isHeat ? L("lag.action.seeSystem") : L("insight.seeApps"))
        }
    }

    @ViewBuilder
    private func issueText(_ item: LagItem) -> some View {
        Text(item.title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        Text(item.detail)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tipRow(_ item: LagItem) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: item.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(item.title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            switch item.kind {
            case .refresh:
                PillButton(title: L("lag.action.displays")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .calmed(let r):
                PillButton(title: L("lag.action.restore"), symbol: "arrow.uturn.backward") { lag.restore(r) }
                    .help(L("help.flag.demoted"))
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func runawayActions(_ r: Runaway) -> some View {
        HStack(spacing: 6) {
            if let note = lag.notes[r.id] {
                Text(noteText(note))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                if note == .waiting {
                    // App 可能正在問「要儲存嗎？」：讓使用者決定強制或作罷
                    PillButton(title: L("lag.action.forceRestart"), role: .destructive) {
                        lag.restart(r, force: true)
                    }
                    .help(L("help.forceRestart"))
                    PillButton(title: L("lag.action.cancel")) { lag.cancelRestart(r) }
                }
            } else {
                if r.isDemoted {
                    PillButton(title: L("lag.action.restore"), symbol: "arrow.uturn.backward") { lag.restore(r) }
                } else {
                    PillButton(title: L("lag.action.demote"), symbol: "tortoise.fill") { lag.demote(r) }
                }
                if r.canQuit {
                    PillButton(title: L("lag.action.restart"), symbol: "arrow.clockwise", role: .prominent) {
                        lag.restart(r)
                    }
                    PillButton(title: L("lag.action.quit")) { lag.quit(r) }
                }
            }
        }
    }

    private func noteText(_ n: LagDetector.ActionNote) -> String {
        switch n {
        case .restarting:    return L("lag.note.restarting")
        case .waiting:       return L("lag.note.waiting")
        case .restarted:     return L("lag.note.restarted")
        case .quitting:      return L("lag.note.quitting")
        case .failed:        return L("lag.note.failed")
        }
    }
}

// MARK: - 標題列右側的順暢度徽章

struct SmoothnessChip: View {
    @ObservedObject private var feed = AppModel.shared.feed
    private var lag: LagDetector { AppModel.shared.lag }

    var body: some View {
        let verdict = LagItem.verdict(LagItem.build(sample: AppModel.shared.monitor.current, report: lag.report))
        HStack(spacing: 4) {
            Circle()
                .fill(verdict.level.color)
                .frame(width: 6, height: 6)
            Text(verdict.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(verdict.level.color.opacity(0.14)))
        .animation(.easeInOut(duration: 0.25), value: verdict)
        .help(L("help.smoothness"))
    }
}

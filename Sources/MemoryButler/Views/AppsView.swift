import SwiftUI

/// 「App」分頁：誰佔用最多記憶體／CPU，一鍵溫和結束（等同在該 App 按 ⌘Q）
struct AppsView: View {
    @ObservedObject private var usage = AppModel.shared.apps
    @ObservedObject private var settings = AppModel.shared.settings
    @State private var confirmingId: String?

    var body: some View {
        VStack(spacing: 10) {
            header
            if usage.hasScanned {
                // 最多 8 個 App + 1 列背景程序，不需要捲動；視窗高度跟著列數自適應
                AppRowsView(rows: usage.rows, other: usage.other,
                            sortKey: usage.sortKey, confirmingId: $confirmingId)
                footer
            } else {
                placeholder
            }
        }
        .task {
            // 每 4 秒刷新一次；面板關著（視圖仍活著）時跳過，不做沒人看的掃描
            while !Task.isCancelled {
                if AppModel.shared.panel.isVisible || !usage.hasScanned { await usage.refresh() }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    /// 標題跟著排序鍵走；排序切換放標題列右側，副標題獨立一行才不會被擠到截斷
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: usage.sortKey == .cpu ? "cpu.fill" : "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(usage.sortKey == .cpu ? Theme.cpuSeries : Theme.series)
                    .frame(width: 18)
                Text(usage.sortKey == .cpu ? L("apps.title.cpu") : L("apps.title"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Picker("", selection: $usage.sortKey) {
                    Text(L("apps.sort.memory")).tag(AppUsageModel.SortKey.memory)
                    Text(L("apps.sort.cpu")).tag(AppUsageModel.SortKey.cpu)
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .labelsHidden()
                .fixedSize()
                .help(L("help.apps.sort"))
            }
            Text(L("apps.sub"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 26)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L("apps.scanning"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var footer: some View {
        Text(LF("apps.self", Fmt.bytes(usage.selfFootprint)))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - 列表本體（獨立出來：最多 9 列不需要 lazy，離屏渲染也能直接檢視）

struct AppRowsView: View {
    let rows: [AppMemoryUsage]
    let other: AppMemoryUsage?
    let sortKey: AppUsageModel.SortKey
    @Binding var confirmingId: String?

    private var everything: [AppMemoryUsage] { rows + (other.map { [$0] } ?? []) }

    var body: some View {
        // 分母永遠是「所有列的最大值」，條長絕不超過格子
        let maxFootprint = max(everything.map(\.footprint).max() ?? 1, 1)
        let maxCpu = max(everything.compactMap(\.cpuFraction).max() ?? 0, 0.5)   // 至少以半顆核心為滿格，避免 1% 看起來像滿載
        VStack(spacing: 6) {
            ForEach(everything) { row($0, maxFootprint: maxFootprint, maxCpu: maxCpu) }
        }
    }

    private func row(_ r: AppMemoryUsage, maxFootprint: UInt64, maxCpu: Double) -> some View {
        // 主數字、比例條、副行資訊都跟著排序鍵走，看到什麼就是在比什麼
        let byCpu = sortKey == .cpu
        let ratio: Double = byCpu
            ? min(1, (r.cpuFraction ?? 0) / maxCpu)
            : min(1, Double(r.footprint) / Double(maxFootprint))
        let primary: String = byCpu
            ? (r.cpuFraction.map { Fmt.percent($0) } ?? L("sys.na"))
            : Fmt.bytes(r.footprint)
        let secondary: String = byCpu
            ? LF("apps.processes", r.processCount) + " · " + Fmt.bytes(r.footprint)
            : LF("apps.processes", r.processCount)
                + (r.cpuFraction.map { " · " + LF("apps.cpu", Int(($0 * 100).rounded())) } ?? "")
        let barColor: Color = r.app == nil ? Color.secondary.opacity(0.45) : (byCpu ? Theme.cpuSeries : Theme.series)

        return HStack(spacing: 10) {
            icon(for: r)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(r.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(primary)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule().fill(barColor)
                                .frame(width: max(3, geo.size.width * ratio))
                        }
                    }
                    .frame(height: 4)
                    Text(secondary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            if r.canQuit {
                quitControls(for: r)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .animation(.easeInOut(duration: 0.2), value: confirmingId)
        .animation(.easeInOut(duration: 0.35), value: sortKey)
    }

    @ViewBuilder
    private func icon(for r: AppMemoryUsage) -> some View {
        if let img = r.icon {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    /// 兩段式確認：先按「結束」，再按「確定結束」；4 秒沒動作自動收回，避免誤點
    @ViewBuilder
    private func quitControls(for r: AppMemoryUsage) -> some View {
        if confirmingId == r.id {
            HStack(spacing: 4) {
                Button(L("apps.confirmQuit")) {
                    r.app?.terminate()
                    confirmingId = nil
                }
                .controlSize(.mini)
                .tint(Color(nsColor: .systemRed))
                Button(L("apps.cancel")) { confirmingId = nil }
                    .controlSize(.mini)
            }
        } else {
            Button(L("apps.quit")) {
                confirmingId = r.id
                let id = r.id
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if confirmingId == id { confirmingId = nil }
                }
            }
            .controlSize(.mini)
            .help(L("apps.quit.help"))
        }
    }
}

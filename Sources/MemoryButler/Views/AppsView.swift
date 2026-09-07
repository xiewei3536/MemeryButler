import SwiftUI

/// 「App」分頁：誰佔用最多記憶體，一鍵溫和結束（等同在該 App 按 ⌘Q）
struct AppsView: View {
    @ObservedObject private var usage = AppModel.shared.apps
    @ObservedObject private var settings = AppModel.shared.settings
    @State private var confirmingId: String?

    var body: some View {
        VStack(spacing: 10) {
            header
            if usage.hasScanned {
                // 最多 8 個 App + 1 列背景程序，不需要捲動；視窗高度跟著列數自適應
                AppRowsView(rows: usage.rows, other: usage.other, confirmingId: $confirmingId)
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

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "list.bullet.rectangle.portrait.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.series)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("apps.title"))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(L("apps.sub"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // 依記憶體或 CPU 排序：燒記憶體和燒 CPU 的常常不是同一個
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
    @Binding var confirmingId: String?

    var body: some View {
        let maxFootprint = rows.first?.footprint ?? 1
        VStack(spacing: 6) {
            ForEach(rows) { row($0, maxFootprint: maxFootprint) }
            if let other { row(other, maxFootprint: maxFootprint) }
        }
    }

    private func row(_ r: AppMemoryUsage, maxFootprint: UInt64) -> some View {
        let ratio = maxFootprint == 0 ? 0 : Double(r.footprint) / Double(maxFootprint)
        return HStack(spacing: 9) {
            icon(for: r)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(r.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(Fmt.bytes(r.footprint))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    // 比例條：一眼看出誰最大（顏色只是輔助，數字永遠在旁邊）
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule().fill(r.app == nil ? Color.secondary.opacity(0.5) : Theme.series)
                                .frame(width: max(3, geo.size.width * ratio))
                        }
                    }
                    .frame(height: 4)
                    Text(LF("apps.processes", r.processCount)
                         + (r.cpuFraction.map { " · " + LF("apps.cpu", Int(($0 * 100).rounded())) } ?? ""))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                }
            }

            if r.app != nil {
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
    }

    @ViewBuilder
    private func icon(for r: AppMemoryUsage) -> some View {
        if let img = r.icon {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 14))
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

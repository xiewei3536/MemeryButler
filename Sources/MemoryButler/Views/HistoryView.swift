import SwiftUI

struct HistoryView: View {
    @ObservedObject private var engine = AppModel.shared.engine
    @ObservedObject private var settings = AppModel.shared.settings
    @State private var confirmingClear = false

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 10) {
            if engine.events.isEmpty {
                emptyState
            } else {
                summaryCard
                eventList
                clearButton
            }
        }
    }

    /// 兩段式清除：第一下變成「確定清除？」，4 秒內沒再按就收回
    private var clearButton: some View {
        Button(confirmingClear ? L("hist.clear.confirm") : L("hist.clear")) {
            if confirmingClear {
                engine.clearEvents()
                confirmingClear = false
            } else {
                confirmingClear = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    confirmingClear = false
                }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: confirmingClear ? .semibold : .regular))
        .foregroundStyle(confirmingClear ? Color(nsColor: .systemRed) : Color.secondary)
        .animation(.easeInOut(duration: 0.15), value: confirmingClear)
    }

    /// 提早停止的原因（只在值得說明時出現）
    private func note(for e: ReleaseEvent) -> String? {
        switch e.stopReason {
        case .swapGrowth:                       return L("hist.note.swap")
        case .compressorGrowth, .compressorCap: return L("hist.note.compressor")
        case .critical:                         return L("hist.note.critical")
        case .thermal:                          return L("hist.note.thermal")
        default:                                return nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(L("hist.empty.title"))
                .font(.system(size: 12.5, weight: .medium))
            Text(L("hist.empty.sub"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var summaryCard: some View {
        let total = engine.events.reduce(Int64(0)) { $0 + $1.reclaimed }
        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("hist.total"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text(Fmt.bytes(total))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("hist.count"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text("\(engine.events.count)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(engine.events) { e in
                    HStack(spacing: 9) {
                        Image(systemName: e.trigger.symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.trigger.displayName)
                                .font(.system(size: 12, weight: .medium))
                            Text(Self.dateFmt.string(from: e.date)
                                 + (note(for: e).map { " · " + $0 } ?? ""))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(e.reclaimed > 0 ? "+" + Fmt.bytes(e.reclaimed) : "—")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
            }
        }
        .frame(maxHeight: 240)
    }
}

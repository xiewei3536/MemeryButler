import SwiftUI

struct HistoryView: View {
    @ObservedObject private var engine = AppModel.shared.engine

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
                Button("清除紀錄") { engine.clearEvents() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("還沒有釋放紀錄")
                .font(.system(size: 12.5, weight: .medium))
            Text("手動釋放或等管家自動出手後,\n每一次整理都會記在這裡。")
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
                    Text("累計釋放")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text(Fmt.bytes(total))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("次數")
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
                            Text(e.trigger.rawValue)
                                .font(.system(size: 12, weight: .medium))
                            Text(Self.dateFmt.string(from: e.date))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(e.reclaimed > 0 ? "+" + Fmt.bytes(e.reclaimed) : "—")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
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

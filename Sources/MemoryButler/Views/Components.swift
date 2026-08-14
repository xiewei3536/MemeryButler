import SwiftUI

// MARK: - 卡片容器

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }
}

// MARK: - 壓力狀態徽章（顏色永遠伴隨文字，不單靠色彩傳達）

struct PressureChip: View {
    let level: PressureLevel
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: level.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(level.color)
            Text(LF("chip.pressure", level.label))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(level.color.opacity(0.14)))
    }
}

// MARK: - 儀表環

struct GaugeRing: View {
    let fraction: Double          // 0...1
    let level: PressureLevel
    let centerTitle: String       // 大字（墨色，不用序列色）
    let centerSubtitle: String

    private let lineWidth: CGFloat = 11

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth))
            Circle()
                .trim(from: 0, to: max(0.003, fraction))
                .stroke(
                    level.color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: fraction)
                .animation(.easeOut(duration: 0.5), value: level)

            VStack(spacing: 1) {
                Text(centerTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(centerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 統計小磚

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

// MARK: - 設定列小標

struct SettingRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Content

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

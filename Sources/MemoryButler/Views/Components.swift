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
    @ObservedObject private var panel = AppModel.shared.panel

    private let lineWidth: CGFloat = 11
    /// 面板看不見時不做過場動畫（每 2 秒一次 0.5 秒的動畫在隱藏狀態下純粹燒 CPU）
    private var transition: Animation? { panel.isVisible ? .easeOut(duration: 0.5) : nil }

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
                .animation(transition, value: fraction)
                .animation(transition, value: level)

            VStack(spacing: 1) {
                Text(centerTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()   // 數字跳動時寬度不抖
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
    var help: String? = nil       // 懸停說明：把術語翻成白話

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
                    .monospacedDigit()
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
        .help(help ?? title)
    }
}

// MARK: - 開關（帶可存取性標籤）
//
// Toggle("") + labelsHidden 會讓螢幕閱讀器唸不出這是哪個設定；
// 這裡把標題交給 Toggle 當 accessibility label，視覺上仍只顯示開關本體。

struct SwitchToggle: View {
    let title: String
    @Binding var isOn: Bool
    var size: ControlSize = .small

    init(_ title: String, isOn: Binding<Bool>, size: ControlSize = .small) {
        self.title = title
        self._isOn = isOn
        self.size = size
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(size)
            .labelsHidden()
            .accessibilityLabel(title)
    }
}

// MARK: - 呼吸燈（監督中的視覺心跳）

struct PulsingDot: View {
    let color: Color
    @ObservedObject private var panel = AppModel.shared.panel

    var body: some View {
        // 用 12fps 的 TimelineView 取代 repeatForever 隱式動畫：
        // 後者在 144Hz 螢幕上每秒重排版 144 次，且面板關著時仍持續；這裡隱藏時完全暫停
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !panel.isVisible)) { ctx in
            let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
            let wave = 0.5 - 0.5 * cos(phase * 2 * .pi)          // 0 → 1 → 0，平滑呼吸
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .opacity(0.3 + 0.7 * wave)
        }
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

// MARK: - 白話判讀卡（總覽／系統分頁共用）

struct InsightCard: View {
    let symbol: String
    let level: PressureLevel
    let title: String
    var advice: String? = nil
    var actionTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(level.color)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                if let advice {
                    Text(advice)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle {
                    Button(action: action) {
                        HStack(spacing: 2) {
                            Text(actionTitle)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.series)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(level.color.opacity(level == .normal ? 0.08 : 0.13))
        )
    }
}


// MARK: - 膠囊小按鈕（卡片內的動作：降到背景、重新啟動…）
//
// 自繪而非 AppKit 按鈕：大小、顏色與卡片一致，離屏快照也畫得出來

struct PillButton: View {
    enum Role { case normal, prominent, destructive }

    let title: String
    var symbol: String? = nil
    var role: Role = .normal
    var action: () -> Void

    @State private var hovering = false

    private var tint: Color {
        switch role {
        case .normal:      return Theme.series
        case .prominent:   return Theme.series
        case .destructive: return Color(nsColor: .systemRed)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 8.5, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(role == .prominent ? Color.white : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule().fill(role == .prominent
                               ? AnyShapeStyle(Theme.accentGradient)
                               : AnyShapeStyle(tint.opacity(hovering ? 0.2 : 0.12)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .fixedSize()
    }
}

// MARK: - 小型分段選擇（自繪，與分頁列同一套視覺）

struct MiniSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let selected = options[i].value == selection
                Button { selection = options[i].value } label: {
                    Text(options[i].title)
                        .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                                .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 1, y: 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
        .fixedSize()
    }
}

// MARK: - 分頁列（圖示 + 標籤；選中的分頁以淡藍底滑動標示）

struct TabBar: View {
    @Binding var selection: PopoverTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PopoverTab.allCases, id: \.self) { tab in
                let selected = tab == selection
                Button { selection = tab } label: {
                    VStack(spacing: 2.5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(height: 15)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Theme.series : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.series.opacity(0.13))
                                .matchedGeometryEffect(id: "selection", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        // 只讓選取底色滑動；分頁內容本身不做動畫（面板會依內容調整大小，動畫會讓視窗抖動）
        .animation(.easeInOut(duration: 0.18), value: selection)
    }
}

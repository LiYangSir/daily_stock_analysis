import SwiftUI

/// 列表行右侧涨跌胶囊（Stocks 同款）。
public struct ChangeChip: View {
    let percent: Double?
    let market: Market
    let scheme: StockColorScheme

    public init(percent: Double?, market: Market, scheme: StockColorScheme) {
        self.percent = percent
        self.market = market
        self.scheme = scheme
    }

    public var body: some View {
        let pct = percent ?? 0
        Text(formatted(pct))
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 80, minHeight: 28)
            .padding(.horizontal, 10)
            .background(DSColor.change(pct, market: market, scheme: scheme),
                        in: RoundedRectangle(cornerRadius: 6))
    }

    private func formatted(_ p: Double) -> String {
        let sign = p > 0 ? "+" : (p < 0 ? "−" : "")
        return "\(sign)\(String(format: "%.2f", abs(p)))%"
    }
}

/// Action 中性胶囊（不携涨跌色）。
public struct ActionChip: View {
    let action: DecisionAction?
    let label: String?

    public init(action: DecisionAction?, label: String? = nil) {
        self.action = action
        self.label = label
    }

    public var body: some View {
        Text(label ?? action?.label ?? "—")
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10).frame(height: 24)
            .background(Color.dsSystemFill, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// 价格 Display + 涨跌行。
public struct PriceCell: View {
    let price: Double
    let change: Double?
    let changePct: Double?
    let market: Market
    let scheme: StockColorScheme
    let timeLabel: String?

    public init(price: Double, change: Double?, changePct: Double?, market: Market, scheme: StockColorScheme, timeLabel: String? = nil) {
        self.price = price
        self.change = change
        self.changePct = changePct
        self.market = market
        self.scheme = scheme
        self.timeLabel = timeLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(market.currencySymbol)\(price, format: .number.precision(.fractionLength(2)))")
                .font(DSFont.display(38))
                .monospacedDigit()
            HStack(spacing: 10) {
                Image(systemName: (change ?? 0) >= 0 ? "triangle.fill" : "triangle.fill")
                    .rotationEffect((change ?? 0) >= 0 ? .zero : .degrees(180))
                    .imageScale(.small)
                if let c = change {
                    Text((c >= 0 ? "+" : "") + String(format: "%.2f", c))
                }
                if let pct = changePct {
                    Text("(\((pct >= 0 ? "+" : "") + String(format: "%.2f", pct))%)")
                }
                if let t = timeLabel {
                    Text(t).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .font(.callout.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(DSColor.change(changePct ?? 0, market: market, scheme: scheme))
        }
    }
}

/// shadcn-style Card 组件：描边 + 圆角 + header/content 分区
public struct ModuleCard<Content: View>: View {
    let title: String
    let leading: AnyView?
    let trailing: AnyView?
    let content: Content

    public init(_ title: String, leading: AnyView? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.leading = leading
        self.trailing = trailing
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                leading
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().padding(.horizontal, 12)

            // Content
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }
}

/// 浮空玻璃返回按钮。
public struct FloatingBackButton: View {
    let action: () -> Void
    public init(action: @escaping () -> Void) { self.action = action }
    public var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DSColor.accent)
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
        }
    }
}

/// 浮空胶囊标题。
public struct CapsuleTitle: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
    }
}

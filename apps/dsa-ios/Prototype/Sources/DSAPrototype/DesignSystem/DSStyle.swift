import SwiftUI

public enum DSColor {
    public static let accent = Color(red: 184/255, green: 137/255, blue: 90/255)
    public static let accentDark = Color(red: 212/255, green: 163/255, blue: 123/255)

    /// 涨跌色：根据 market + 用户偏好计算。
    public static func up(_ market: Market, scheme: StockColorScheme) -> Color {
        scheme.upIsRed(for: market) ? .red : .green
    }

    public static func down(_ market: Market, scheme: StockColorScheme) -> Color {
        scheme.upIsRed(for: market) ? .green : .red
    }

    public static func change(_ value: Double, market: Market, scheme: StockColorScheme) -> Color {
        if value > 0 { return up(market, scheme: scheme) }
        if value < 0 { return down(market, scheme: scheme) }
        return .secondary
    }
}

public enum DSFont {
    public static func display(_ size: CGFloat = 34, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

#if canImport(UIKit)
import UIKit
public extension Color {
    static let dsGroupedBackground = Color(UIColor.systemGroupedBackground)
    static let dsSecondaryGrouped = Color(UIColor.secondarySystemGroupedBackground)
    static let dsSystemFill = Color(UIColor.systemFill)
}
#else
public extension Color {
    static let dsGroupedBackground = Color(NSColor.windowBackgroundColor)
    static let dsSecondaryGrouped = Color(NSColor.controlBackgroundColor)
    static let dsSystemFill = Color.gray.opacity(0.18)
}
#endif

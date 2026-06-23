import Foundation

/// 市场归属。决定涨跌色与货币符号。
public enum Market: String, Codable, Sendable, CaseIterable {
    case cn, hk, us, jp, kr, unknown

    public init(stockCode: String) {
        let upper = stockCode.uppercased()
        if upper.hasSuffix(".HK") || upper.range(of: #"^\d{5}$"#, options: .regularExpression) != nil {
            self = .hk
        } else if upper.hasSuffix(".T") {
            self = .jp
        } else if upper.hasSuffix(".KS") || upper.hasSuffix(".KQ") {
            self = .kr
        } else if upper.range(of: #"^\d{6}$"#, options: .regularExpression) != nil {
            self = .cn
        } else if upper.range(of: #"^[A-Z]{1,5}$"#, options: .regularExpression) != nil {
            self = .us
        } else {
            self = .unknown
        }
    }

    public var currencySymbol: String {
        switch self {
        case .cn: return "¥"
        case .hk: return "HK$"
        case .us: return "$"
        case .jp: return "¥"
        case .kr: return "₩"
        case .unknown: return ""
        }
    }
}

/// 涨跌颜色方案。
public enum StockColorScheme: String, Codable, CaseIterable, Sendable {
    case auto, redUp, greenUp

    public func upIsRed(for market: Market) -> Bool {
        switch self {
        case .redUp: return true
        case .greenUp: return false
        case .auto: return market == .cn || market == .hk
        }
    }
}

/// 决策动作（与后端 DecisionAction 对齐）。
public enum DecisionAction: String, Codable, Sendable {
    case buy, add, hold, reduce, sell, watch, avoid, alert

    public var label: String {
        switch self {
        case .buy: return "买入"
        case .add: return "加仓"
        case .hold: return "持有"
        case .reduce: return "减仓"
        case .sell: return "卖出"
        case .watch: return "观望"
        case .avoid: return "回避"
        case .alert: return "警示"
        }
    }
}

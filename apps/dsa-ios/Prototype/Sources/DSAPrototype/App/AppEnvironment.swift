import SwiftUI

/// 应用环境：注入 AuthService、当前 Tab 选中、涨跌色方案、报告详情导航。
@MainActor
public final class AppEnvironment: ObservableObject {
    @Published public var selectedTab: Int = 0
    @Published public var colorScheme: StockColorScheme = .auto {
        didSet { UserDefaults.standard.set(colorScheme.rawValue, forKey: "dsa.colorScheme") }
    }
    @Published public var presentedReport: HistoryItem?

    public let auth: AuthService

    public init() {
        self.auth = AuthService()
        if let raw = UserDefaults.standard.string(forKey: "dsa.colorScheme"),
           let s = StockColorScheme(rawValue: raw) {
            self.colorScheme = s
        }
    }
}

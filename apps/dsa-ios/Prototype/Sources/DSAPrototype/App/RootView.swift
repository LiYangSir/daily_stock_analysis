import SwiftUI

public struct RootView: View {
    @StateObject private var env = AppEnvironment()
    @StateObject private var taskStream = TaskStreamStore()

    public init() {}

    public var body: some View {
        Group {
            if env.useMockData || env.auth.status.loggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .environmentObject(env)
        .environmentObject(env.auth)
        .environmentObject(taskStream)
        .task {
            if !env.useMockData {
                await env.auth.refreshStatus()
            }
        }
        .sheet(item: $env.presentedReport) { item in
            ReportDetailView(history: item)
                .environmentObject(env)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var env: AppEnvironment

    private let items: [CapsuleTabBar.Item] = [
        .init(id: 0, title: "行情", symbol: "chart.bar.fill"),
        .init(id: 1, title: "分析", symbol: "doc.text.magnifyingglass"),
        .init(id: 2, title: "助手", symbol: "bubble.left.and.bubble.right.fill"),
        .init(id: 3, title: "组合", symbol: "briefcase.fill"),
        .init(id: 4, title: "我的", symbol: "person.crop.circle.fill")
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            currentScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            CapsuleTabBar(selection: $env.selectedTab, items: items)
        }
        .ignoresSafeArea(.keyboard)
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch env.selectedTab {
        case 0: MarketsView()
        case 1: AnalysisView()
        case 2: ChatView()
        case 3: PortfolioView()
        default: ProfileView()
        }
    }
}

@available(iOS 16.0, *)
public struct DSAPrototypeApp: App {
    public init() {}
    public var body: some Scene {
        WindowGroup { RootView() }
    }
}

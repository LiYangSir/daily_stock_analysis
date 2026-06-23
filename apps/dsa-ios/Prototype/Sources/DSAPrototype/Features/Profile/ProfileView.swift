import SwiftUI

public struct ProfileView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var auth: AuthService

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("账户") {
                    HStack {
                        Image(systemName: env.useMockData ? "person.circle.dashed" : "person.crop.circle.fill")
                            .foregroundStyle(DSColor.accent)
                        Text(env.useMockData ? "Mock 数据模式" : (auth.status.loggedIn ? "已登录" : "未登录"))
                        Spacer()
                        if !env.useMockData && auth.status.loggedIn {
                            Button("退出") { Task { await auth.logout(); env.useMockData = true } }
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("服务器") {
                    LabeledContent("Base URL") {
                        let field = TextField("https://dsa.example.com", text: $auth.baseURLString)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                        #if os(iOS)
                        field.textInputAutocapitalization(.never)
                        #else
                        field
                        #endif
                    }
                    Toggle("使用 Mock 数据", isOn: $env.useMockData)
                }

                Section("外观") {
                    Picker("涨跌颜色", selection: $env.colorScheme) {
                        Text("跟随市场").tag(StockColorScheme.auto)
                        Text("红涨绿跌").tag(StockColorScheme.redUp)
                        Text("绿涨红跌").tag(StockColorScheme.greenUp)
                    }
                }

                Section("工具") {
                    NavigationLink {
                        ScreeningView().environmentObject(env)
                    } label: { Label("选股 (AlphaSift)", systemImage: "magnifyingglass.circle.fill") }
                    NavigationLink {
                        BacktestView().environmentObject(env)
                    } label: { Label("回测", systemImage: "chart.line.uptrend.xyaxis.circle.fill") }
                    NavigationLink {
                        UsageView().environmentObject(env)
                    } label: { Label("Token 用量", systemImage: "gauge.with.dots.needle.50percent") }
                    NavigationLink {
                        IntelligentImportView().environmentObject(env)
                    } label: { Label("智能导入自选", systemImage: "square.and.arrow.down.on.square") }
                }

                Section("系统配置") {
                    NavigationLink {
                        LLMChannelsView().environmentObject(env)
                    } label: { Label("LLM 通道", systemImage: "sparkles") }
                    NavigationLink {
                        NotificationChannelsView().environmentObject(env)
                    } label: { Label("通知通道", systemImage: "bell.badge") }
                    NavigationLink {
                        SchedulerView().environmentObject(env)
                    } label: { Label("定时调度", systemImage: "clock.arrow.circlepath") }
                    NavigationLink {
                        AuthBackupView().environmentObject(env).environmentObject(auth)
                    } label: { Label("认证 · 配置备份", systemImage: "lock.shield") }
                }

                Section("关于") {
                    LabeledContent("版本", value: "0.1.0 (prototype)")
                    Link("项目 GitHub", destination: URL(string: "https://github.com/ZhuLinsen/daily_stock_analysis")!)
                }

                Section { Color.clear.frame(height: 90).listRowBackground(Color.clear) }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .navigationTitle("我的")
        }
    }
}

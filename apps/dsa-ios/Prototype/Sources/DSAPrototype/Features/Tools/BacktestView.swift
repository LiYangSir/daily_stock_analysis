import SwiftUI

@MainActor
final class BacktestViewModel: ObservableObject {
    @Published var window: Int = 5
    @Published var phase: String = "all"
    @Published var dateRange: String = "近 90 天"
    @Published var forceRerun: Bool = false
    @Published var performance: BacktestPerformance?
    @Published var results: [BacktestResult] = []
    @Published var loading = false
    @Published var errorMessage: String?

    func load(env: AppEnvironment) async {
        self.performance = try? await env.auth.api.send(.get("/backtest/performance"))
        struct BtResp: Decodable { let items: [BacktestResult]? }; self.results = (try? await env.auth.api.send(.get("/backtest/results", query: ["limit": "30"])) as BtResp?)?.items ?? []
    }

    func run(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        // 真实接入应 POST /backtest/run，原型简化
    }
}

public struct BacktestView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = BacktestViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                paramsCard
                runButton
                if let perf = vm.performance {
                    performanceGrid(perf)
                    phaseDistributionCard(perf.phaseDistribution ?? [])
                }
                resultsCard
                Color.clear.frame(height: 80)
            }
            .padding(.top, 8)
        }
        .background(Color.dsGroupedBackground)
        .navigationTitle("回测")
        .dsInlineTitle()
        .task { await vm.load(env: env) }
    }

    private var paramsCard: some View {
        ModuleCard("参数") {
            paramRow("评估窗口", value: "\(vm.window) 日")
            paramRow("阶段", value: phaseLabel)
            paramRow("日期范围", value: vm.dateRange)
            Toggle("强制重跑", isOn: $vm.forceRerun).font(.subheadline)
        }
        .padding(.horizontal, 16)
    }

    private var runButton: some View {
        Button { Task { await vm.run(env: env) } } label: {
            HStack {
                if vm.loading { ProgressView().tint(.white) }
                Text("运行回测").font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(DSColor.accent, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .disabled(vm.loading)
    }

    private func performanceGrid(_ perf: BacktestPerformance) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 10) {
            statCard("平均收益", String(format: "%+.2f%%", (perf.avgReturn ?? 0) * 100), color: (perf.avgReturn ?? 0) >= 0 ? .red : .green)
            statCard("胜率", String(format: "%.1f%%", (perf.winRate ?? 0) * 100), color: .primary)
            statCard("平均收益", String(format: "%+.2f%%", (perf.avgReturn ?? 0) * 100), color: (perf.avgReturn ?? 0) >= 0 ? .red : .green)
            statCard("止损率", String(format: "%.1f%%", (perf.stopLossRate ?? 0) * 100), color: .red)
        }
        .padding(.horizontal, 16)
    }

    private func statCard(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 14))
    }

    private func phaseDistributionCard(_ items: [PhaseDistribution]) -> some View {
        let maxCount = (items.compactMap { $0.count }.max() ?? 1)
        return ModuleCard("阶段分布") {
            VStack(spacing: 6) {
                ForEach(items) { it in
                    HStack(spacing: 8) {
                        Text(it.phase).font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Color.gray.opacity(0.16))
                            Capsule().fill(color(for: it.phase))
                                .frame(width: geo.size.width * CGFloat(it.count ?? 0) / CGFloat(maxCount))
                        }
                        .frame(height: 8)
                        Text("\(it.count) 次").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func color(for phase: String) -> Color {
        switch phase {
        case "盘前": return .blue
        case "盘中": return DSColor.accent
        case "盘后": return .purple
        default: return .gray
        }
    }

    private var resultsCard: some View {
        ModuleCard("个股结果 · \(vm.results.count)") {
            VStack(spacing: 0) {
                ForEach(vm.results) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.stockName ?? r.stockCode ?? "").font(.system(size: 15, weight: .medium))
                            Text("\(r.date) · \(r.phase ?? "—") · 预测 \(r.predicted)\(r.actual.map { " · 实际 \($0)" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        outcomeBadge(r.outcome ?? "—")
                    }
                    .padding(.vertical, 8)
                    if r.id != vm.results.last?.id { Divider() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func outcomeBadge(_ outcome: String) -> some View {
        let color: Color = {
            switch outcome {
            case "命中", "止盈": return .green
            case "未命中", "止损": return .red
            default: return .secondary
            }
        }()
        return Text(outcome)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color == .secondary ? Color.secondary : color)
    }

    private var phaseLabel: String {
        ["all": "全部", "premarket": "盘前", "intraday": "盘中", "postmarket": "盘后"][vm.phase] ?? vm.phase
    }

    private func paramRow(_ label: String, value: String) -> some View {
        HStack { Text(label).font(.subheadline); Spacer(); Text("\(value) ›").font(.subheadline).foregroundStyle(.secondary) }
    }
}

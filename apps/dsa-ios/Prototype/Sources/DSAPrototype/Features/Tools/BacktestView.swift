import SwiftUI

@MainActor
final class BacktestViewModel: ObservableObject {
    @Published var window: Int = 5
    @Published var phase: String = "all"
    @Published var forceRerun: Bool = false
    @Published var performance: BacktestPerformance?
    @Published var results: [BacktestResult] = []
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var runMessage: String?

    func load(env: AppEnvironment) async {
        self.performance = try? await env.auth.api.send(.get("/backtest/performance"))
        struct BtResp: Decodable { let items: [BacktestResult]? }; self.results = (try? await env.auth.api.send(.get("/backtest/results", query: ["limit": "30"])) as BtResp?)?.items ?? []
    }

    /// 运行回测：POST /backtest/run（字段映射 window→eval_window_days、forceRerun→force）。
    /// 传 min_age_days=0：后端默认 14 天会过滤掉近期报告，导致交互式回测静默返回 0。
    func run(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        struct Body: Encodable {
            let code: String?
            let force: Bool
            let evalWindowDays: Int
            let minAgeDays: Int
            let limit: Int
        }
        do {
            let body = Body(code: nil, force: forceRerun,
                            evalWindowDays: max(1, min(120, window)), minAgeDays: 0, limit: 200)
            let resp: BacktestRunResponse = try await env.auth.api.send(
                Endpoint(path: "/backtest/run", method: .POST, body: try JSONEncoder.dsa.encode(body)))
            var msg = "处理 \(resp.processed ?? 0) · 完成 \(resp.completed ?? 0) · 写入 \(resp.saved ?? 0)"
            if (resp.insufficient ?? 0) > 0 { msg += " · 数据不足 \(resp.insufficient ?? 0)" }
            if (resp.errors ?? 0) > 0 { msg += " · 错误 \(resp.errors ?? 0)" }
            runMessage = msg
            errorMessage = nil
            await load(env: env)
        } catch {
            errorMessage = "回测失败：\((error as? APIError)?.errorDescription ?? "")"
        }
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
                if let m = vm.runMessage {
                    Text(m).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                }
                if let err = vm.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal, 16)
                }
                if let perf = vm.performance {
                    performanceGrid(perf)
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
            HStack {
                Text("评估窗口").font(.subheadline)
                Spacer()
                Stepper(value: $vm.window, in: 1...120) {
                    Text("\(vm.window) 交易日").font(.subheadline)
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            paramRow("阶段", value: phaseLabel)
            paramRow("计算时间", value: formatTime(vm.performance?.computedAt))
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
        return VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 10) {
                statCard("个股均收", String(format: "%+.1f%%", perf.avgStockReturnPct ?? 0),
                         color: (perf.avgStockReturnPct ?? 0) >= 0 ? .red : .green)
                statCard("模拟均收", String(format: "%+.1f%%", perf.avgSimulatedReturnPct ?? 0),
                         color: (perf.avgSimulatedReturnPct ?? 0) >= 0 ? .red : .green)
                statCard("胜率", String(format: "%.1f%%", perf.winRatePct ?? 0), color: .primary)
                statCard("方向准确", String(format: "%.1f%%", perf.directionAccuracyPct ?? 0), color: .primary)
                statCard("止损触发", String(format: "%.1f%%", perf.stopLossTriggerRate ?? 0), color: .red)
                statCard("止盈触发", String(format: "%.1f%%", perf.takeProfitTriggerRate ?? 0), color: .green)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                statCard("完成 / 总数", "\(perf.completedCount ?? 0) / \(perf.totalEvaluations ?? 0)", color: .primary)
                statCard("胜 / 负 / 平", "\(perf.winCount ?? 0) / \(perf.lossCount ?? 0) / \(perf.neutralCount ?? 0)", color: .primary)
                statCard("首次命中", perf.avgDaysToFirstHit.map { String(format: "%.1f 天", $0) } ?? "—", color: .primary)
                statCard("数据不足", String(perf.insufficientCount ?? 0), color: .secondary)
            }
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

    private var resultsCard: some View {
        ModuleCard("个股结果 · \(vm.results.count)") {
            VStack(spacing: 0) {
                ForEach(vm.results) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.stockName ?? r.code).font(.system(size: 15, weight: .medium))
                            Text("\(r.analysisDate ?? "—") · \(r.marketPhase ?? "—") · 预期 \(r.directionExpected ?? "—")\(r.actualMovement.map { " · 实际 \($0)" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 8) {
                                if let ret = r.stockReturnPct {
                                    Text("个股 \(String(format: "%+.1f%%", ret))")
                                }
                                if let sim = r.simulatedReturnPct {
                                    Text("模拟 \(String(format: "%+.1f%%", sim))")
                                }
                                if r.hitStopLoss == true { Text("触及止损").foregroundStyle(.red) }
                                if r.hitTakeProfit == true { Text("触及止盈").foregroundStyle(.green) }
                                Spacer()
                            }
                            .font(.caption2).foregroundStyle(.secondary)
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

    private func formatTime(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        return String(raw.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

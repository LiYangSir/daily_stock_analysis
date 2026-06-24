import SwiftUI

@MainActor
final class ReportDetailViewModel: ObservableObject {
    @Published var report: AnalysisReport?
    @Published var bars: [KLineData] = []
    @Published var loading = false
    @Published var errorMessage: String?

    func load(env: AppEnvironment, history: HistoryItem) async {
        loading = true
        defer { loading = false }
        do {
            async let report: AnalysisReport = env.auth.api.send(.get("/history/\(history.id)"))
            async let barsResp: StockHistoryResponse = env.auth.api.send(.get("/stocks/\(history.stockCode)/history", query: ["period": "daily", "days": "120"]))
            self.report = try await report
            self.bars = (try? await barsResp)?.data ?? []
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

public struct ReportDetailView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = ReportDetailViewModel()
    let history: HistoryItem

    enum SheetKind: Identifiable { case runFlow, markdown, trend
        var id: Int { hashValue }
    }
    @State private var presentedSheet: SheetKind?

    public init(history: HistoryItem) { self.history = history }

    public var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 90)
                    headerArea
                    if !vm.bars.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            KLineChart(bars: vm.bars, market: history.market, scheme: env.colorScheme)
                            MACDChart(bars: vm.bars, market: history.market, scheme: env.colorScheme)
                        }
                        .padding(.horizontal, 16)
                    }
                    if let summary = vm.report?.summary {
                        ModuleCard("操作建议", trailing: AnyView(
                            ActionChip(action: summary.action, label: summary.actionLabel)
                        )) {
                            if let s = summary.analysisSummary {
                                Text(s).font(.callout).foregroundStyle(.secondary).lineSpacing(2)
                            }
                            if let advice = summary.operationAdvice {
                                Text(advice).font(.subheadline).padding(.top, 4)
                            }
                        }.padding(.horizontal, 16)
                    }
                    if let strategy = vm.report?.strategy {
                        ModuleCard("策略点位") {
                            HStack {
                                strategyItem("理想买入", strategy.idealBuy, color: .primary)
                                Spacer()
                                strategyItem("止损", strategy.stopLoss, color: DSColor.down(history.market, scheme: env.colorScheme))
                            }
                            HStack {
                                strategyItem("次优买入", strategy.secondaryBuy, color: .primary)
                                Spacer()
                                strategyItem("止盈", strategy.takeProfit, color: DSColor.up(history.market, scheme: env.colorScheme))
                            }.padding(.top, 6)
                        }.padding(.horizontal, 16)
                    }
                    if let s = vm.report?.summary, let score = s.sentimentScore {
                        ModuleCard("市场情绪", trailing: AnyView(Text("\(Int(score))").font(.headline).monospacedDigit())) {
                            sentimentBar(score)
                            HStack {
                                Text("悲观").foregroundStyle(.secondary).font(.footnote)
                                Spacer()
                                Text(s.sentimentLabel ?? "—").font(.footnote)
                            }.padding(.top, 4)
                        }.padding(.horizontal, 16)
                    }
                    if let trend = vm.report?.summary?.trendPrediction {
                        ModuleCard("趋势预测") {
                            Text(trend).font(.callout).lineSpacing(2)
                        }.padding(.horizontal, 16)
                    }
                    Color.clear.frame(height: 100)
                }
            }
            VStack {
                HStack {
                    FloatingBackButton { dismiss() }
                    Spacer()
                    CapsuleTitle("\(vm.report?.meta?.stockName ?? history.stockName ?? history.stockCode) · \(history.stockCode)")
                    Spacer()
                    Menu {
                        Button { presentedSheet = .runFlow } label: { Label("运行流", systemImage: "point.3.connected.trianglepath.dotted") }
                        Button { presentedSheet = .markdown } label: { Label("完整报告 (Markdown)", systemImage: "doc.text") }
                        Button { presentedSheet = .trend } label: { Label("历史趋势", systemImage: "chart.line.uptrend.xyaxis") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DSColor.accent)
                            .frame(width: 36, height: 36)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 8)
                Spacer()
            }
        }
        .background(Color.dsGroupedBackground.ignoresSafeArea())
        .task { await vm.load(env: env, history: history) }
        .sheet(item: $presentedSheet) { kind in
            switch kind {
            case .runFlow:
                RunFlowSheet(recordId: history.id)
                    .environmentObject(env)
                    .presentationDetents([.medium, .large])
            case .markdown:
                MarkdownReportSheet(recordId: history.id, stockName: history.stockName ?? history.stockCode)
                    .environmentObject(env)
                    .presentationDetents([.large])
            case .trend:
                HistoryTrendSheet(stockCode: history.stockCode)
                    .environmentObject(env)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            PriceCell(price: vm.report?.meta?.currentPrice ?? history.currentPrice ?? 0,
                      change: nil,
                      changePct: vm.report?.meta?.changePct ?? history.changePct,
                      market: history.market, scheme: env.colorScheme,
                      timeLabel: vm.report?.meta?.createdAt ?? history.createdAt)
        }
        .padding(.horizontal, 20)
    }

    private func strategyItem(_ label: String, _ value: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "—").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(color)
        }
    }

    private func sentimentBar(_ score: Double) -> some View {
        let pct = max(0, min(100, score)) / 100
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [.green, .gray.opacity(0.3), .red],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4).opacity(0.5)
                Circle().fill(Color.primary).frame(width: 12, height: 12)
                    .offset(x: geo.size.width * pct - 6)
            }
        }.frame(height: 12)
    }
}

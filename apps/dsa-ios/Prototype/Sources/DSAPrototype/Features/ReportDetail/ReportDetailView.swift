import SwiftUI
import MarkdownUI

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
            async let report: AnalysisReport = env.auth.api.send(.get("/history/\(history.recordId)"))
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

                    if vm.loading {
                        ContentSkeleton(lines: 6)
                    }

                    if let err = vm.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal, 20)
                    }

                    if let report = vm.report {
                        headerArea(report)
                        chartArea
                        summaryCard(report)
                        strategyCard(report)
                        sentimentCard(report)
                        trendCard(report)
                        metaCard(report)
                    }

                    Color.clear.frame(height: 100)
                }
            }

            // 顶部浮空栏
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
                RunFlowSheet(recordId: history.recordId)
                    .environmentObject(env)
                    .presentationDetents([.medium, .large])
            case .markdown:
                MarkdownReportSheet(recordId: history.recordId, stockName: history.stockName ?? history.stockCode)
                    .environmentObject(env)
                    .presentationDetents([.large])
            case .trend:
                HistoryTrendSheet(stockCode: history.stockCode)
                    .environmentObject(env)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Header

    private func headerArea(_ report: AnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PriceCell(price: report.meta?.currentPrice ?? history.currentPrice ?? 0,
                      change: nil,
                      changePct: report.meta?.changePct ?? history.changePct,
                      market: history.market, scheme: env.colorScheme,
                      timeLabel: formatTime(report.meta?.createdAt ?? history.createdAt))
            HStack(spacing: 8) {
                if let phase = report.meta?.marketPhaseSummary?.phase {
                    Text(phaseLabel(phase))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.blue)
                }
                if let rt = report.meta?.reportType {
                    Text(reportTypeLabel(rt))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let model = report.meta?.modelUsed {
                    Text(model)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartArea: some View {
        if !vm.bars.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                KLineChart(bars: vm.bars, market: history.market, scheme: env.colorScheme)
                MACDChart(bars: vm.bars, market: history.market, scheme: env.colorScheme)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Summary (核心分析摘要)

    @ViewBuilder
    private func summaryCard(_ report: AnalysisReport) -> some View {
        if let summary = report.summary {
            ModuleCard("分析摘要", trailing: AnyView(
                ActionChip(action: summary.action, label: summary.actionLabel ?? summary.operationAdvice)
            )) {
                if let text = summary.analysisSummary, !text.isEmpty {
                    Markdown(text)
                        .markdownTextStyle { FontSize(14) }
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let advice = summary.operationAdvice, advice != summary.actionLabel {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.point.right.fill").font(.caption).foregroundStyle(DSColor.accent)
                        Text("操作建议：\(advice)")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Strategy

    @ViewBuilder
    private func strategyCard(_ report: AnalysisReport) -> some View {
        if let strategy = report.strategy {
            ModuleCard("策略点位") {
                VStack(alignment: .leading, spacing: 10) {
                    if let v = strategy.idealBuy, !v.isEmpty {
                        strategyRow("理想买入", v, icon: "arrow.down.circle", color: .green)
                    }
                    if let v = strategy.secondaryBuy, !v.isEmpty {
                        strategyRow("次优买入", v, icon: "arrow.down.circle.dotted", color: .blue)
                    }
                    if let v = strategy.stopLoss, !v.isEmpty {
                        strategyRow("止损", v, icon: "exclamationmark.triangle", color: DSColor.down(history.market, scheme: env.colorScheme))
                    }
                    if let v = strategy.takeProfit, !v.isEmpty {
                        strategyRow("止盈", v, icon: "star.circle", color: DSColor.up(history.market, scheme: env.colorScheme))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func strategyRow(_ label: String, _ value: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Markdown(value)
                    .markdownTextStyle { FontSize(13) }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Sentiment

    @ViewBuilder
    private func sentimentCard(_ report: AnalysisReport) -> some View {
        if let s = report.summary, let score = s.sentimentScore {
            ModuleCard("市场情绪") {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("\(Int(score))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(s.sentimentLabel ?? "—")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 60)
                    VStack(alignment: .leading, spacing: 6) {
                        sentimentBar(score)
                        HStack {
                            Text("极度悲观").font(.system(size: 9)).foregroundStyle(.secondary)
                            Spacer()
                            Text("中性").font(.system(size: 9)).foregroundStyle(.secondary)
                            Spacer()
                            Text("极度乐观").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Trend

    @ViewBuilder
    private func trendCard(_ report: AnalysisReport) -> some View {
        if let trend = report.summary?.trendPrediction, !trend.isEmpty {
            ModuleCard("趋势预测") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: trendIcon(trend))
                        .font(.title2)
                        .foregroundStyle(trendColor(trend))
                    Markdown(trend)
                        .markdownTextStyle { FontSize(14) }
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Meta info

    @ViewBuilder
    private func metaCard(_ report: AnalysisReport) -> some View {
        ModuleCard("报告信息") {
            VStack(alignment: .leading, spacing: 6) {
                metaRow("报告类型", reportTypeLabel(report.meta?.reportType ?? ""))
                metaRow("分析时间", formatTime(report.meta?.createdAt))
                metaRow("模型", report.meta?.modelUsed ?? "—")
                metaRow("Report ID", report.meta?.queryId ?? "—")
            }
        }
        .padding(.horizontal, 16)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Text(value).font(.caption).lineLimit(1)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func sentimentBar(_ score: Double) -> some View {
        let pct = max(0, min(100, score)) / 100
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [.green, .yellow, .orange, .red],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6).opacity(0.35)
                Circle().fill(Color.primary).frame(width: 14, height: 14)
                    .shadow(radius: 2)
                    .offset(x: geo.size.width * pct - 7)
            }
        }.frame(height: 14)
    }

    private func trendIcon(_ trend: String) -> String {
        if trend.contains("多") || trend.contains("涨") || trend.contains("bullish") { return "arrow.up.right.circle.fill" }
        if trend.contains("空") || trend.contains("跌") || trend.contains("bearish") { return "arrow.down.right.circle.fill" }
        return "arrow.right.circle.fill"
    }

    private func trendColor(_ trend: String) -> Color {
        if trend.contains("多") || trend.contains("涨") { return DSColor.up(history.market, scheme: env.colorScheme) }
        if trend.contains("空") || trend.contains("跌") { return DSColor.down(history.market, scheme: env.colorScheme) }
        return .secondary
    }

    private func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "premarket": return "盘前"
        case "intraday": return "盘中"
        case "postmarket": return "盘后"
        default: return phase
        }
    }

    private func reportTypeLabel(_ type: String) -> String {
        switch type {
        case "full": return "完整报告"
        case "detailed": return "详细报告"
        case "simple": return "简要报告"
        case "brief": return "速览"
        case "market_review": return "大盘复盘"
        default: return type
        }
    }

    private func formatTime(_ raw: String?) -> String {
        guard let raw else { return "—" }
        return String(raw.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

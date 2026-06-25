import SwiftUI
import MarkdownUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ReportDetailViewModel: ObservableObject {
    @Published var report: AnalysisReport?
    @Published var bars: [KLineData] = []
    @Published var markdownContent: String = ""
    @Published var diagnostics: RunDiagnosticSummaryResponse?
    @Published var news: [NewsIntelItem] = []
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var copiedField: String?

    /// 复制文本到剪贴板并短暂高亮对应字段。
    func flashCopy(_ text: String, field: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        copiedField = field
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); self.copiedField = nil }
    }

    func load(env: AppEnvironment, history: HistoryItem) async {
        loading = true
        defer { loading = false }

        // 并发请求报告详情 + K线 + Markdown全文 + 运行诊断 + 相关新闻
        struct MdResp: Decodable { let content: String? }

        async let reportTask: AnalysisReport? = try? env.auth.api.send(.get("/history/\(history.recordId)"))
        async let barsTask: StockHistoryResponse? = try? env.auth.api.send(.get("/stocks/\(history.stockCode)/history", query: ["period": "daily", "days": "120"]))
        async let mdTask: MdResp? = try? env.auth.api.send(.get("/history/\(history.recordId)/markdown"))
        async let diagTask: RunDiagnosticSummaryResponse? = try? env.auth.api.send(.get("/history/\(history.recordId)/diagnostics"))
        async let newsTask: NewsIntelResponse? = try? env.auth.api.send(.get("/history/\(history.recordId)/news", query: ["limit": "20"]))

        self.report = await reportTask
        self.bars = (await barsTask)?.data ?? []
        self.markdownContent = (await mdTask)?.content ?? ""
        self.diagnostics = await diagTask
        self.news = (await newsTask)?.items ?? []

        if report == nil && markdownContent.isEmpty {
            errorMessage = "报告加载失败 (id=\(history.recordId))"
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
    @State private var showRawResult = false
    @State private var showContextSnapshot = false

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

                    // 大盘复盘使用专用 Hero 卡，不渲染通用的 PriceCell 头（其会显示无意义的 ¥0.00）
                    if let report = vm.report, history.reportType != "market_review" {
                        headerArea(report)
                    }

                    // 大盘复盘 or 有 markdown 全文
                    if history.reportType == "market_review" {
                        marketReviewContent
                    } else if vm.report == nil && !vm.markdownContent.isEmpty {
                        MarkdownCards(text: vm.markdownContent)
                            .padding(.horizontal, 16)
                    } else if let report = vm.report {
                        // 普通个股报告：结构化卡片展示
                        chartArea
                        summaryCard(report)
                        strategyCard(report)
                        sentimentCard(report)
                        trendCard(report)
                        relatedBoardsCard(report)
                        analysisContextCard(report)
                        newsCard
                        diagnosticsCard
                        transparencyCard(report)
                        metaCard(report)
                    } else if !vm.loading && vm.errorMessage == nil {
                        Text("报告为空 (recordId=\(history.recordId))")
                            .font(.caption).foregroundStyle(.orange).padding(.horizontal, 20)
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
                if report.meta?.marketPhaseSummary?.isPartialBar == true {
                    Text("盘中·未完成")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.orange)
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
                    MarkdownCards(text: text)
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
                    .reportMarkdown()
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
                        .reportMarkdown()
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

    // MARK: - Related boards (板块联动，对齐 webui ReportOverview)

    @ViewBuilder
    private func relatedBoardsCard(_ report: AnalysisReport) -> some View {
        let boards = report.details?.belongBoards ?? []
        let sectors = report.details?.sectorRankings
        let hasSectors = (sectors?.top?.isEmpty == false) || (sectors?.bottom?.isEmpty == false)
        if !boards.isEmpty || hasSectors {
            ModuleCard("板块联动", leading: AnyView(iconChip("square.stack.3d.up"))) {
                if !boards.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(boards) { b in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.name ?? "—").font(.system(size: 13, weight: .medium))
                                    if let t = b.type, !t.isEmpty {
                                        Text(t).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
                            }
                        }
                    }
                    .padding(.bottom, hasSectors ? 8 : 0)
                }
                if hasSectors, let sectors {
                    sectorRankingList("领涨", sectors.top)
                    sectorRankingList("领跌", sectors.bottom)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func sectorRankingList(_ title: String, _ items: [SectorItem]?) -> some View {
        if let items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(items) { s in
                            HStack(spacing: 4) {
                                Text(s.name ?? "—").font(.system(size: 12))
                                if let pct = s.changePct {
                                    Text(String(format: "%+.2f%%", pct))
                                        .font(.system(size: 11).monospacedDigit())
                                        .foregroundStyle(DSColor.change(pct, market: history.market, scheme: env.colorScheme))
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.dsSecondaryGrouped, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Analysis context (分析输入与数据质量，对齐 webui AnalysisContextSummary)

    @ViewBuilder
    private func analysisContextCard(_ report: AnalysisReport) -> some View {
        if let ctx = report.details?.analysisContextPackOverview {
            ModuleCard("分析输入与数据质量", leading: AnyView(iconChip("checkmark.shield"))) {
                if let dq = ctx.dataQuality {
                    HStack(spacing: 10) {
                        if let score = dq.overallScore {
                            VStack(spacing: 0) {
                                Text("\(score)").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                                Text("质量分").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(dataQualityColor(dq.level).opacity(0.15)))
                            .foregroundStyle(dataQualityColor(dq.level))
                        }
                        if let level = dq.level {
                            Text(dataQualityLabel(level))
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(dataQualityColor(level).opacity(0.15), in: Capsule())
                                .foregroundStyle(dataQualityColor(level))
                        }
                        Spacer()
                    }
                    .padding(.bottom, 6)
                    if let limits = dq.limitations?.filter({ !$0.isEmpty }), !limits.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(limits, id: \.self) { l in
                                Text("• \(l)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 6)
                    }
                }
                if let counts = ctx.counts {
                    statusCountChips(counts).padding(.bottom, 6)
                }
                if let blocks = ctx.blocks, !blocks.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { idx, blk in
                            blockRow(blk)
                            if idx < blocks.count - 1 { Divider() }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func statusCountChips(_ counts: AnalysisContextPackOverviewCounts) -> some View {
        let items: [(String, Int?, Color)] = [
            ("可用", counts.available, .green), ("缺失", counts.missing, .red),
            ("不支持", counts.notSupported, .secondary), ("降级", counts.fallback, .orange),
            ("过期", counts.stale, .orange), ("估算", counts.estimated, .blue),
            ("部分", counts.partial, .orange), ("失败", counts.fetchFailed, .red),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    let n = it.1 ?? 0
                    if n > 0 {
                        HStack(spacing: 3) {
                            Text(it.0).font(.system(size: 11))
                            Text("\(n)").font(.system(size: 11, weight: .bold).monospacedDigit())
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(it.2.opacity(0.14), in: Capsule())
                        .foregroundStyle(it.2)
                    }
                }
            }
        }
    }

    private func blockRow(_ blk: AnalysisContextPackOverviewBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(blockStatusColor(blk.status)).frame(width: 7, height: 7)
                Text(blk.label ?? blk.key ?? "—").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(blockStatusLabel(blk.status ?? ""))
                    .font(.caption2).foregroundStyle(blockStatusColor(blk.status))
                if let src = blk.source, !src.isEmpty {
                    Text(src).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let reasons = blk.missingReasons?.filter({ !$0.isEmpty }), !reasons.isEmpty {
                Text(reasons.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private func dataQualityColor(_ level: String?) -> Color {
        switch level {
        case "good": return .green
        case "usable": return .blue
        case "limited": return .orange
        case "poor": return .red
        default: return .secondary
        }
    }

    private func dataQualityLabel(_ level: String) -> String {
        ["good": "良好", "usable": "可用", "limited": "受限", "poor": "差"][level] ?? level
    }

    private func blockStatusColor(_ s: String?) -> Color {
        switch s ?? "" {
        case "available": return .green
        case "missing", "fetch_failed": return .red
        case "fallback", "stale", "partial", "estimated": return .orange
        default: return .secondary
        }
    }

    private func blockStatusLabel(_ s: String) -> String {
        ["available": "可用", "missing": "缺失", "not_supported": "不支持", "fallback": "降级",
         "stale": "过期", "estimated": "估算", "partial": "部分", "fetch_failed": "失败"][s] ?? s
    }

    // MARK: - Related news (相关新闻，对齐 webui ReportNews)

    @ViewBuilder
    private var newsCard: some View {
        if !vm.news.isEmpty {
            let visible = Array(vm.news.prefix(20))
            ModuleCard("相关新闻 · \(vm.news.count)", leading: AnyView(iconChip("newspaper"))) {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { idx, item in
                        newsRow(item)
                        if idx < visible.count - 1 { Divider() }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func newsRow(_ item: NewsIntelItem) -> some View {
        Button {
            #if canImport(UIKit)
            if let urlString = item.url, let url = URL(string: urlString) { UIApplication.shared.open(url) }
            #endif
        } label: {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title ?? "—").font(.system(size: 13, weight: .medium)).foregroundStyle(.primary).lineLimit(2)
                    if let snippet = item.snippet, !snippet.isEmpty {
                        Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right.square").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Run diagnostics (运行诊断，对齐 webui ReportDiagnostics)

    @ViewBuilder
    private var diagnosticsCard: some View {
        if let d = vm.diagnostics {
            ModuleCard("运行诊断", leading: AnyView(iconChip("stethoscope")), trailing: AnyView(
                Button { vm.flashCopy(d.copyText ?? "", field: "diag") } label: {
                    Image(systemName: vm.copiedField == "diag" ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13)).foregroundStyle(DSColor.accent)
                }.buttonStyle(.plain)
            )) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(diagStatusLabel(d.status ?? ""))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(diagStatusColor(d.status ?? "").opacity(0.15), in: Capsule())
                            .foregroundStyle(diagStatusColor(d.status ?? ""))
                        if let label = d.statusLabel, !label.isEmpty {
                            Text(label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let reason = d.reason, !reason.isEmpty {
                        Text(reason).font(.subheadline).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    idChips(trace: d.traceId, task: d.taskId, query: d.queryId, trigger: d.triggerSource)
                    if let comps = d.components, !comps.isEmpty {
                        let ordered = comps.sorted { ($0.value.key ?? "") < ($1.value.key ?? "") }.map { $0.value }
                        VStack(spacing: 0) {
                            ForEach(Array(ordered.enumerated()), id: \.offset) { idx, c in
                                diagComponentRow(c)
                                if idx < ordered.count - 1 { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func idChips(trace: String?, task: String?, query: String?, trigger: String?) -> some View {
        let chips: [(String, String?)] = [("trace", trace), ("task", task), ("query", query), ("来源", trigger)]
        let visible = chips.filter { v in let s = v.1; return s != nil && !(s?.isEmpty ?? true) }
        if !visible.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, c in
                        Text("\(c.0): \(c.1 ?? "")").font(.system(size: 10).monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.gray.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func diagComponentRow(_ c: RunDiagnosticComponent) -> some View {
        HStack(spacing: 8) {
            Circle().fill(diagComponentColor(c.status ?? "")).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.label ?? c.key ?? "—").font(.system(size: 13, weight: .medium))
                if let msg = c.message, !msg.isEmpty {
                    Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Text(c.status ?? "").font(.caption2).foregroundStyle(diagComponentColor(c.status ?? ""))
        }
        .padding(.vertical, 6)
    }

    private func diagStatusColor(_ s: String) -> Color {
        switch s { case "normal": return .green; case "degraded": return .orange; case "failed": return .red; default: return .secondary }
    }
    private func diagStatusLabel(_ s: String) -> String {
        ["normal": "正常", "degraded": "部分降级", "failed": "失败", "unknown": "未知"][s] ?? s
    }
    private func diagComponentColor(_ s: String) -> Color {
        switch s { case "ok": return .green; case "degraded": return .orange; case "failed": return .red; default: return .secondary }
    }

    // MARK: - Transparency (原始数据，对齐 webui ReportDetails)

    @ViewBuilder
    private func transparencyCard(_ report: AnalysisReport) -> some View {
        let raw = report.details?.rawResult
        let snap = report.details?.contextSnapshot
        if raw != nil || snap != nil {
            ModuleCard("原始数据", leading: AnyView(iconChip("doc.text"))) {
                if raw != nil {
                    DisclosureGroup(isExpanded: $showRawResult) {
                        jsonBlock(prettyJSON(raw), field: "raw")
                    } label: {
                        Text("原始分析结果 (raw_result)").font(.subheadline.weight(.medium))
                    }
                }
                if snap != nil {
                    DisclosureGroup(isExpanded: $showContextSnapshot) {
                        jsonBlock(prettyJSON(snap), field: "snap")
                    } label: {
                        Text("上下文快照 (context_snapshot)").font(.subheadline.weight(.medium))
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func jsonBlock(_ text: String, field: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text.isEmpty ? "—" : text)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            HStack { Spacer(); copyButton(text, field: field) }
        }
    }

    private func copyButton(_ text: String, field: String) -> some View {
        Button { vm.flashCopy(text, field: field) } label: {
            Label(vm.copiedField == field ? "已复制" : "复制",
                  systemImage: vm.copiedField == field ? "checkmark" : "doc.on.doc")
                .font(.caption).foregroundStyle(DSColor.accent)
        }
        .buttonStyle(.plain)
    }

    private func prettyJSON(_ value: JSONValue?) -> String {
        guard let value, let data = try? JSONEncoder().encode(value) else { return "—" }
        if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
           let str = String(data: pretty, encoding: .utf8) {
            return str
        }
        return String(data: data, encoding: .utf8) ?? "—"
    }

    // MARK: - Market Review (大盘复盘，与 webui MarketReviewReportView 对齐)

    @ViewBuilder
    private var marketReviewContent: some View {
        let report = vm.report
        let summary = report?.summary
        let payload = report?.details?.marketReviewPayload

        // 0. Hero 卡（替代通用 PriceCell 头）
        if let report {
            marketReviewHero(payload, report)
        }

        // 1. 四个洞察小卡片（summary 存在才显示，与 web 一致）
        if let summary {
            insightCards(summary)
        }

        // 2. 结构化大盘数据（breadth + indices）
        if let payload, (payload.breadth != nil || !(payload.indices ?? []).isEmpty) {
            structuredMarketDataCard(payload)
        }

        // 2b. 多区域：markets 存在时逐区域渲染结构化数据（对齐 web 多市场迭代）
        if let markets = payload?.markets, !markets.isEmpty {
            ForEach(Array(markets.keys.sorted()), id: \.self) { region in
                if let rp = markets[region], rp.breadth != nil || !(rp.indices ?? []).isEmpty {
                    Text(regionLabel(region) ?? region)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                    structuredMarketDataCard(rp)
                }
            }
        }

        // 3. Section 卡片（来自 payload.sections 或 fallback 到 markdown 切分）
        let sections = payload?.sections?.filter { !($0.markdown ?? "").isEmpty } ?? []
        if !sections.isEmpty {
            ForEach(sections) { section in
                sectionCard(section)
            }
        } else if !vm.markdownContent.isEmpty {
            MarkdownCards(text: vm.markdownContent)
                .padding(.horizontal, 16)
        }
    }

    /// 大盘复盘 Hero 卡：眉标 + 标题 + 区域/代码 chip + 时间，渐变背景对齐 web home-report-hero。
    private func marketReviewHero(_ payload: MarketReviewPayload?, _ report: AnalysisReport) -> some View {
        let title = payload?.rootTitle ?? payload?.title ?? report.meta?.stockName ?? "大盘复盘"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold))
                Text("MARKET REVIEW")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.4)
                Spacer()
                Button { vm.flashCopy(vm.markdownContent, field: "mr-md") } label: {
                    Image(systemName: vm.copiedField == "mr-md" ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(DSColor.accent)

            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let region = regionLabel(payload?.region) {
                    heroChip(region)
                }
                if let code = report.meta?.stockCode, !code.isEmpty {
                    heroChip(code)
                }
                let time = formatTime(report.meta?.createdAt ?? payload?.generatedAt)
                if time != "—" {
                    Text(time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(colors: [DSColor.accent.opacity(0.12), Color.dsSecondaryGrouped],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DSColor.accent.opacity(0.22), lineWidth: 0.5))
        .padding(.horizontal, 16)
    }

    private func heroChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(DSColor.accent.opacity(0.14), in: Capsule())
            .foregroundStyle(DSColor.accent)
    }

    private func regionLabel(_ region: String?) -> String? {
        switch region?.lowercased() {
        case "cn": return "A股"
        case "us": return "美股"
        case "hk": return "港股"
        default: return nil
        }
    }

    /// 28×28 accent 图标 chip，对齐 web 的 `bg-primary/10` 图标容器。
    private func iconChip(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DSColor.accent)
            .frame(width: 28, height: 28)
            .background(DSColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func insightCards(_ summary: ReportSummary) -> some View {
        // 与 web 一致：复盘摘要展示完整 analysisSummary（lineLimit 4 截断），不再只取首段。
        let items: [(icon: String, label: String, value: String)] = [
            ("doc.text.fill", "复盘摘要", summary.analysisSummary?.isEmpty == false ? summary.analysisSummary! : "暂无摘要"),
            ("gauge.with.dots.needle.50percent", "市场情绪", summary.sentimentScore.map { "\(Int($0)) / 100 · \(summary.sentimentLabel ?? "")" } ?? "暂无评分"),
            ("arrow.triangle.swap", "轮动与资金", summary.operationAdvice ?? "暂无观点"),
            ("exclamationmark.shield.fill", "风险与观察", summary.trendPrediction ?? "暂无观察")
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    iconChip(item.icon)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(item.value)
                            .font(.system(size: 13))
                            .lineLimit(4)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                .padding(12)
                .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 16)
    }

    private func structuredMarketDataCard(_ payload: MarketReviewPayload) -> some View {
        ModuleCard("结构化大盘数据", leading: AnyView(iconChip("chart.bar.xaxis"))) {
            // Breadth：描边中性瓦片，保留 A 股红涨绿跌语义色
            if let b = payload.breadth {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    breadthCell("上涨家数", "\(b.upCount ?? 0)", color: DSColor.up(history.market, scheme: env.colorScheme))
                    breadthCell("下跌家数", "\(b.downCount ?? 0)", color: DSColor.down(history.market, scheme: env.colorScheme))
                    breadthCell("涨停/跌停", "\(b.limitUpCount ?? 0) / \(b.limitDownCount ?? 0)", color: .orange)
                    breadthCell("成交额", b.totalAmount.map { String(format: "%.0f", $0) + (b.turnoverUnit ?? "") } ?? "—", color: .blue)
                }
            }
            // Indices：4 列表（指数 / 最新 / 涨跌幅 / 高低），对齐 web
            if let indices = payload.indices, !indices.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Text("指数").frame(maxWidth: .infinity, alignment: .leading)
                        Text("最新").frame(width: 52, alignment: .trailing)
                        Text("涨跌幅").frame(width: 56, alignment: .trailing)
                        Text("高/低").frame(width: 68, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)

                    ForEach(indices) { idx in
                        HStack(spacing: 4) {
                            Text(idx.name ?? "—")
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(idx.current.map { String(format: "%.0f", $0) } ?? "—")
                                .font(.system(size: 12).monospacedDigit())
                                .frame(width: 52, alignment: .trailing)
                            Text(idx.changePct.map { String(format: "%+.2f%%", $0) } ?? "—")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(DSColor.change(idx.changePct ?? 0, market: history.market, scheme: env.colorScheme))
                                .frame(width: 56, alignment: .trailing)
                            Text(highLowText(idx))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 68, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func highLowText(_ idx: MarketIndex) -> String {
        switch (idx.high, idx.low) {
        case let (h?, l?): return "\(String(format: "%.0f", h))/\(String(format: "%.0f", l))"
        case let (h?, nil): return "\(String(format: "%.0f", h))/—"
        case let (nil, l?): return "—/\(String(format: "%.0f", l))"
        default: return "—"
        }
    }

    private func breadthCell(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func sectionCard(_ section: MarketReviewSection) -> some View {
        ModuleCard(section.title ?? "Section", leading: AnyView(iconChip(sectionIcon(section.title ?? "")))) {
            if let md = section.markdown, !md.isEmpty {
                Markdown(md)
                    .reportMarkdown()
            }
        }
        .padding(.horizontal, 16)
    }

    private func sectionIcon(_ title: String) -> String {
        let t = title.lowercased()
        if t.contains("指数") || t.contains("index") || t.contains("大盘") || t.contains("overview") { return "chart.bar.fill" }
        if t.contains("情绪") || t.contains("赚钱") || t.contains("sentiment") { return "gauge.with.dots.needle.50percent" }
        if t.contains("板块") || t.contains("行业") || t.contains("轮动") || t.contains("sector") { return "arrow.up.right" }
        if t.contains("资金") || t.contains("成交") || t.contains("量能") { return "banknote.fill" }
        if t.contains("风险") || t.contains("观察") || t.contains("risk") { return "exclamationmark.shield.fill" }
        if t.contains("计划") || t.contains("明日") || t.contains("plan") { return "calendar" }
        if t.contains("消息") || t.contains("催化") || t.contains("news") { return "newspaper.fill" }
        return "doc.text.fill"
    }
}

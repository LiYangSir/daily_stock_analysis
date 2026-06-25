import SwiftUI

@MainActor
final class MarketsViewModel: ObservableObject {
    @Published var watchlist: [StockQuote] = []
    @Published var stockBar: [StockBarItem] = []
    @Published var history: [HistoryItem] = []
    @Published var loading = false
    @Published var errorMessage: String?

    func load(env: AppEnvironment) async {
        loading = true
        errorMessage = nil

        struct WatchlistResp: Decodable { let stockCodes: [String]? }

        // 并发：自选清单 + 个股汇总 + 历史报告（均为快速元数据请求）
        async let watchlistTask: WatchlistResp? = try? env.auth.api.send(.get("/stocks/watchlist"))
        async let barTask: StockBarResponse? = try? env.auth.api.send(.get("/history/stocks", query: ["limit": "200"]))
        async let historyTask: HistoryListResponse? = try? env.auth.api.send(.get("/history", query: ["limit": "20"]))

        let watchlistResp = await watchlistTask
        let barResp = await barTask
        let historyResp = await historyTask

        let codes = watchlistResp?.stockCodes ?? []
        self.stockBar = barResp?.items ?? []
        self.history = historyResp?.items ?? []

        // 元数据就绪后立即结束 loading：历史报告 / 个股汇总先行渲染；
        // 自选实时行情（逐只 /quote，可能较慢）改为后台逐只刷新，不再阻塞整页。
        loading = false
        if watchlistResp == nil && historyResp == nil && barResp == nil {
            errorMessage = "加载失败，请检查网络或下拉刷新"
        }

        await loadWatchlistQuotes(env: env, codes: codes)
    }

    /// 并发拉取自选个股实时行情；单只设 12s 上限，避免某只停牌/超时拖慢整组。
    /// 每只返回即按原始清单顺序刷新 watchlist，实现“逐只填入”的渐进效果。
    private func loadWatchlistQuotes(env: AppEnvironment, codes: [String]) async {
        guard !codes.isEmpty else { self.watchlist = []; return }
        let ordered = Array(codes.prefix(20))
        var collected: [String: StockQuote] = [:]
        await withTaskGroup(of: (String, StockQuote?).self) { group in
            for code in ordered {
                group.addTask { (code, await Self.fetchQuote(env: env, code: code)) }
            }
            for await (code, quote) in group {
                // 行情拉取失败也保留占位行（currentPrice=0 标记），避免「添加成功却看不到、也无法移除」。
                collected[code.lowercased()] = quote ?? Self.placeholder(code: code)
                self.watchlist = ordered.compactMap { collected[$0.lowercased()] }
            }
        }
    }

    /// 行情不可用时的占位：仅保留代码，便于用户查看与移除。
    private static func placeholder(code: String) -> StockQuote {
        StockQuote(stockCode: code, currentPrice: 0)
    }

    /// 单只行情请求与 12s 超时赛跑，先返回者胜；避免某只股票长时间挂起。
    private static func fetchQuote(env: AppEnvironment, code: String) async -> StockQuote? {
        await withTaskGroup(of: StockQuote?.self) { group in
            group.addTask { try? await env.auth.api.send(.get("/stocks/\(code)/quote")) }
            group.addTask { try? await Task.sleep(nanoseconds: 12_000_000_000); return nil }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// 添加自选：POST /stocks/watchlist/add。
    func addWatchlist(env: AppEnvironment, code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        struct Body: Encodable { let stockCode: String }
        do {
            try await env.auth.api.sendVoid(
                Endpoint(path: "/stocks/watchlist/add", method: .POST,
                         body: try JSONEncoder.dsa.encode(Body(stockCode: trimmed))))
            await load(env: env)
        } catch {
            errorMessage = "添加失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 移除自选：POST /stocks/watchlist/remove。
    func removeWatchlist(env: AppEnvironment, code: String) async {
        struct Body: Encodable { let stockCode: String }
        do {
            try await env.auth.api.sendVoid(
                Endpoint(path: "/stocks/watchlist/remove", method: .POST,
                         body: try JSONEncoder.dsa.encode(Body(stockCode: code))))
            watchlist.removeAll { $0.stockCode.lowercased() == code.lowercased() }
        } catch {
            errorMessage = "移除失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }
}

public struct MarketsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var auth: AuthService
    @StateObject private var vm = MarketsViewModel()
    @State private var noReport = false
    @State private var showAdd = false
    @State private var newCode = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CompactPageTitle("行情") {
                        Image(systemName: "ellipsis").foregroundStyle(DSColor.accent)
                    }

                    if vm.loading {
                        WatchlistSkeleton()
                        ContentSkeleton(lines: 3)
                    }

                    if let err = vm.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                            .padding(.horizontal, 20).padding(.top, 8)
                    }

                    if !vm.loading && vm.watchlist.isEmpty && vm.history.isEmpty && vm.errorMessage == nil {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(.secondary)
                            Text("暂无数据，下拉刷新").font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 40)
                    }

                    watchlistHeader
                    if !vm.watchlist.isEmpty {
                        groupedCard {
                            ForEach(vm.watchlist) { quote in
                                watchlistRow(quote)
                                    .contentShape(Rectangle())
                                    .onTapGesture { presentLatestReport(code: quote.stockCode) }
                                    .contextMenu {
                                        Button("移除自选", role: .destructive) {
                                            Task { await vm.removeWatchlist(env: env, code: quote.stockCode) }
                                        }
                                    }
                                if quote.id != vm.watchlist.last?.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                    }

                    if !vm.stockBar.isEmpty {
                        let bars = Array(vm.stockBar.prefix(30))
                        sectionHeader("个股汇总 · \(vm.stockBar.count)")
                        groupedCard {
                            ForEach(bars) { bar in
                                Button { presentLatestReport(code: bar.stockCode) } label: {
                                    stockBarRow(bar)
                                }
                                .buttonStyle(.plain)
                                if bar.id != bars.last?.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                    }

                    if !vm.history.isEmpty {
                        sectionHeader("历史报告")
                        groupedCard {
                            ForEach(vm.history) { item in
                                Button { env.presentedReport = item } label: {
                                    historyRow(item)
                                }
                                .buttonStyle(.plain)
                                if item.id != vm.history.last?.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                    }

                    Color.clear.frame(height: 100)
                }
            }
            .background(Color.dsGroupedBackground)
            .hideNavBar()
            .task(id: auth.status.loggedIn) { await vm.load(env: env) }
            .refreshable { await vm.load(env: env) }
            .alert("暂无报告", isPresented: $noReport) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("该股票暂无历史分析报告，可在「分析」页生成。")
            }
            .alert("添加自选", isPresented: $showAdd) {
                TextField("股票代码", text: $newCode)
                    .autocorrectionDisabled()
                Button("添加") {
                    let code = newCode
                    Task { await vm.addWatchlist(env: env, code: code) }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("输入代码，如 600519、hk00700、AAPL")
            }
        }
    }

    /// 点击自选 / 个股汇总中的股票：拉取该股最新一份报告并以详情页打开。
    private func presentLatestReport(code: String) {
        Task { @MainActor in
            let resp: HistoryListResponse? = try? await env.auth.api.send(
                .get("/history", query: ["stock_code": code, "limit": "1"]))
            if let item = resp?.items?.first {
                env.presentedReport = item
            } else {
                noReport = true
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.footnote)
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, -8)
    }

    private var watchlistHeader: some View {
        HStack {
            Text("关注".uppercased())
                .font(.footnote).tracking(0.5).foregroundStyle(.secondary)
            Spacer()
            Button { newCode = ""; showAdd = true } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(DSColor.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, -8)
    }

    @ViewBuilder
    private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func watchlistRow(_ quote: StockQuote) -> some View {
        let unavailable = quote.currentPrice == 0   // 占位行：行情拉取失败
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.stockName ?? quote.stockCode).font(.system(size: 16, weight: .medium))
                    Text(quote.stockCode).font(.footnote).foregroundStyle(.secondary).tracking(0.4)
                }
                Spacer()
                if unavailable {
                    Label("行情暂不可用", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("\(quote.market.currencySymbol)\(quote.currentPrice, format: .number.precision(.fractionLength(2)))")
                        .font(.system(size: 17, weight: .medium)).monospacedDigit()
                    ChangeChip(percent: quote.changePercent, market: quote.market, scheme: env.colorScheme)
                }
            }
            // OHLCV 明细：展示后端已返回但此前被丢弃的字段（对齐 web）
            if !unavailable {
                let hasDetail = [quote.open, quote.high, quote.low, quote.volume].contains { $0 != nil }
                if hasDetail {
                    HStack(spacing: 10) {
                        ohlcLabel("开", quote.open)
                        ohlcLabel("高", quote.high)
                        ohlcLabel("低", quote.low)
                        if let vol = quote.volume { ohlcText("量", abbreviateVolume(vol)) }
                        if let amt = quote.amount { ohlcText("额", abbreviateVolume(amt)) }
                        Spacer(minLength: 0)
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func stockBarRow(_ bar: StockBarItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bar.stockName ?? bar.stockCode).font(.system(size: 16, weight: .medium))
                HStack(spacing: 6) {
                    Text(bar.stockCode).font(.caption).foregroundStyle(.secondary)
                    if let n = bar.analysisCount {
                        Text("· 分析 \(n) 次").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ActionChip(action: bar.action, label: bar.actionLabel)
                if let t = bar.lastAnalysisTime {
                    Text(formatTime(t)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func historyRow(_ item: HistoryItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.stockName ?? item.stockCode)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                    if let phase = item.marketPhaseSummary?.phase {
                        Text(phaseLabel(phase))
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.blue)
                    }
                }
                Text("\(formatTime(item.createdAt)) · \(reportTypeLabel(item.reportType ?? ""))")
                    .font(.caption).foregroundStyle(.secondary)
                if let model = item.modelUsed, !model.isEmpty {
                    Text(model).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ActionChip(action: item.action, label: item.actionLabel)
                if let score = item.sentimentScore {
                    HStack(spacing: 4) {
                        sentimentMiniBar(score)
                        Text("\(Int(score))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.footnote)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func ohlcLabel(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.tertiary)
            Text(value.map { String(format: "%.2f", $0) } ?? "—").monospacedDigit()
        }
    }

    private func ohlcText(_ label: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.tertiary)
            Text(value).monospacedDigit()
        }
    }

    private func abbreviateVolume(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1e8 { return String(format: "%.2f亿", v / 1e8) }
        if a >= 1e4 { return String(format: "%.2f万", v / 1e4) }
        return String(format: "%.0f", v)
    }

    private func sentimentMiniBar(_ score: Double) -> some View {
        let pct = max(0, min(100, score)) / 100
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.2)).frame(height: 4)
                Capsule().fill(sentimentColor(score)).frame(width: max(2, geo.size.width * pct), height: 4)
            }
        }
        .frame(width: 44, height: 6)
    }

    private func sentimentColor(_ score: Double) -> Color {
        if score <= 20 { return .red }
        if score <= 40 { return .orange }
        if score <= 60 { return .yellow }
        if score <= 80 { return .mint }
        return .green
    }

    private func phaseLabel(_ phase: String) -> String {
        ["premarket": "盘前", "intraday": "盘中", "lunch_break": "午休",
         "closing_auction": "尾盘", "postmarket": "盘后", "non_trading": "休市"][phase] ?? phase
    }

    private func reportTypeLabel(_ type: String) -> String {
        ["full": "完整", "detailed": "详细", "simple": "简要",
         "brief": "速览", "market_review": "大盘复盘"][type] ?? type
    }

    private func formatTime(_ raw: String?) -> String {
        guard let raw, raw.count >= 10 else { return raw ?? "—" }
        let date = String(raw.dropFirst(5).prefix(5))   // "01-01"
        let time = raw.count >= 16 ? String(raw.dropFirst(11).prefix(5)) : ""
        return time.isEmpty ? date : "\(date) \(time)"
    }
}

import SwiftUI

@MainActor
final class MarketsViewModel: ObservableObject {
    @Published var watchlist: [StockQuote] = []
    @Published var history: [HistoryItem] = []
    @Published var loading = false
    @Published var errorMessage: String?

    func load(env: AppEnvironment) async {
        loading = true
        defer { loading = false }
        var firstError: String?

        struct WatchlistResp: Decodable { let stockCodes: [String]? }

        // 并发：watchlist + history 同时发起
        async let watchlistTask: WatchlistResp? = try? env.auth.api.send(.get("/stocks/watchlist"))
        async let historyTask: HistoryListResponse? = try? env.auth.api.send(.get("/history", query: ["limit": "20"]))

        let watchlistResp = await watchlistTask
        let historyResp = await historyTask

        let codes = watchlistResp?.stockCodes ?? []
        self.history = historyResp?.items ?? []

        // 并发拉所有 quote
        var quotes: [StockQuote] = []
        await withTaskGroup(of: StockQuote?.self) { group in
            for code in codes.prefix(20) {
                group.addTask {
                    try? await env.auth.api.send(.get("/stocks/\(code)/quote"))
                }
            }
            for await result in group {
                if let q = result { quotes.append(q) }
            }
        }
        // 保持原顺序
        self.watchlist = codes.compactMap { code in quotes.first { $0.stockCode.lowercased() == code.lowercased() } }

        if watchlistResp == nil && historyResp == nil {
            firstError = "加载失败，请检查网络或下拉刷新"
        }
        errorMessage = firstError
    }
}

public struct MarketsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var auth: AuthService
    @StateObject private var vm = MarketsViewModel()

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

                    if !vm.watchlist.isEmpty {
                        sectionHeader("关注")
                        groupedCard {
                            ForEach(vm.watchlist) { quote in
                                watchlistRow(quote)
                                if quote.id != vm.watchlist.last?.id {
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

    @ViewBuilder
    private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func watchlistRow(_ quote: StockQuote) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.stockName ?? "").font(.system(size: 17, weight: .medium))
                Text(quote.stockCode).font(.footnote).foregroundStyle(.secondary).tracking(0.4)
            }
            Spacer()
            Text("\(quote.market.currencySymbol)\(quote.currentPrice, format: .number.precision(.fractionLength(2)))")
                .font(.system(size: 17, weight: .medium)).monospacedDigit()
            ChangeChip(percent: quote.changePercent, market: quote.market, scheme: env.colorScheme)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func historyRow(_ item: HistoryItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.stockName ?? item.stockCode)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                Text("\(item.createdAt) · \(item.reportType ?? "report")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            ActionChip(action: item.action, label: item.actionLabel)
            Image(systemName: "chevron.right").foregroundStyle(Color.secondary).font(.footnote)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

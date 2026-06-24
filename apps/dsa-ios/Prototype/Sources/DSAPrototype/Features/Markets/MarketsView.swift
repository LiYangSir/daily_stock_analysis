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
        var codes: [String] = []
        do {
            let resp: WatchlistResp = try await env.auth.api.send(.get("/stocks/watchlist"))
            codes = resp.stockCodes ?? []
        } catch {
            firstError = "/watchlist · " + ((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }

        var quotes: [StockQuote] = []
        for code in codes.prefix(20) {
            if let q: StockQuote = try? await env.auth.api.send(.get("/stocks/\(code)/quote")) {
                quotes.append(q)
            }
        }
        self.watchlist = quotes

        // 3) 历史报告（后端返回 { total, page, limit, items: [...] }）
        do {
            let resp: HistoryListResponse = try await env.auth.api.send(.get("/history", query: ["limit": "20"]))
            self.history = resp.items ?? []
        } catch {
            let msg = "/history · " + ((error as? APIError)?.errorDescription ?? error.localizedDescription)
            firstError = firstError.map { "\($0)\n\(msg)" } ?? msg
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

                    if let err = vm.errorMessage {
                        Text(err).font(.footnote).foregroundStyle(.red).padding(.horizontal, 20)
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

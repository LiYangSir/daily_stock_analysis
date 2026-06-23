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
        if env.useMockData {
            watchlist = MockData.watchlist
            history = MockData.history
            return
        }
        do {
            // 简单串行加载；正式版应并发。
            let watchlistRaw: [WatchlistItem] = try await env.auth.api.send(.get("/stocks/watchlist"))
            var quotes: [StockQuote] = []
            for w in watchlistRaw.prefix(20) {
                if let q: StockQuote = try? await env.auth.api.send(.get("/stocks/\(w.stockCode)/quote")) {
                    quotes.append(q)
                }
            }
            self.watchlist = quotes
            self.history = try await env.auth.api.send(.get("/history", query: ["limit": "20"]))
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

public struct MarketsView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = MarketsViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if !vm.watchlist.isEmpty {
                    Section("关注") {
                        ForEach(vm.watchlist) { quote in
                            watchlistRow(quote)
                        }
                    }
                }
                if !vm.history.isEmpty {
                    Section("历史报告") {
                        ForEach(vm.history) { item in
                            historyRow(item)
                                .contentShape(Rectangle())
                                .onTapGesture { env.presentedReport = item }
                        }
                    }
                }
                if let err = vm.errorMessage {
                    Section { Text(err).foregroundStyle(.red) }
                }
                Section { Color.clear.frame(height: 90).listRowBackground(Color.clear) }
            }
            .navigationTitle("行情")
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .task { await vm.load(env: env) }
            .refreshable { await vm.load(env: env) }
        }
    }

    @ViewBuilder
    private func watchlistRow(_ quote: StockQuote) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.stockName).font(.system(size: 17, weight: .medium))
                Text(quote.stockCode).font(.footnote).foregroundStyle(.secondary).tracking(0.4)
            }
            Spacer()
            Text("\(quote.market.currencySymbol)\(quote.currentPrice, format: .number.precision(.fractionLength(2)))")
                .font(.system(size: 17, weight: .medium)).monospacedDigit()
            ChangeChip(percent: quote.changePercent, market: quote.market, scheme: env.colorScheme)
        }
    }

    @ViewBuilder
    private func historyRow(_ item: HistoryItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.stockName ?? item.stockCode).font(.system(size: 17, weight: .medium))
                Text("\(item.createdAt) · \(item.reportType ?? "report")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            ActionChip(action: item.action, label: item.actionLabel)
            Image(systemName: "chevron.right").foregroundStyle(Color.secondary).font(.footnote)
        }
    }
}

import SwiftUI

@MainActor
final class PortfolioViewModel: ObservableObject {
    @Published var snapshot: PortfolioSnapshotResponse?
    @Published var risk: PortfolioRiskResponse?
    @Published var loading = false
    @Published var errorMessage: String?

    func load(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        do {
            self.snapshot = try await env.auth.api.send(.get("/portfolio/snapshot"))
        } catch {
            errorMessage = "/snapshot · " + ((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
        do {
            self.risk = try await env.auth.api.send(.get("/portfolio/risk"))
        } catch {
            let msg = "/risk · " + ((error as? APIError)?.errorDescription ?? error.localizedDescription)
            errorMessage = errorMessage.map { "\($0)\n\(msg)" } ?? msg
        }
    }
}

public struct PortfolioView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var segment: Int = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CompactPageTitle("组合")
                segmentControl
                Group {
                    switch segment {
                    case 0: ScreeningView()
                    case 1: DecisionSignalsView()
                    default: AlertsView()
                    }
                }
            }
            .background(Color.dsGroupedBackground)
            .hideNavBar()
        }
    }

    private var segmentControl: some View {
        HStack(spacing: 6) {
            segChip("选股", index: 0)
            segChip("决策信号", index: 1)
            segChip("预警", index: 2)
        }
        .padding(.horizontal, 16)
    }

    private func segChip(_ title: String, index: Int) -> some View {
        Button {
            withAnimation(.snappy) { segment = index }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(segment == index ? DSColor.accent.opacity(0.14) : Color.gray.opacity(0.1),
                            in: Capsule())
                .foregroundStyle(segment == index ? DSColor.accent : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overview

struct PortfolioOverviewView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = PortfolioViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let snap = vm.snapshot {
                    totalsBlock(snap)
                    if let accounts = snap.accounts, accounts.count > 1 {
                        accountsCard(accounts)
                    }
                    if let accounts = snap.accounts {
                        let positions = accounts.flatMap { $0.positions ?? [] }
                        if !positions.isEmpty { positionsCard(positions) }
                    }
                }
                if let risk = vm.risk { riskCard(risk) }
                if let err = vm.errorMessage {
                    Text(err).font(.footnote).foregroundStyle(.red).padding(.horizontal, 20)
                }
                Color.clear.frame(height: 100)
            }
            .padding(.top, 6)
        }
        .task { await vm.load(env: env) }
        .refreshable { await vm.load(env: env) }
    }

    private func totalsBlock(_ snap: PortfolioSnapshotResponse) -> some View {
        let pnl = snap.unrealizedPnl ?? 0
        let equity = snap.totalEquity ?? 0
        let pnlPct = equity > 0 ? pnl / equity * 100 : 0
        let market = Market.cn
        return VStack(alignment: .leading, spacing: 4) {
            Text("总权益").font(.caption).foregroundStyle(.secondary).tracking(0.5)
            Text("\(snap.currency ?? "¥")\(equity, format: .number.precision(.fractionLength(2)))")
                .font(DSFont.display(38)).monospacedDigit()
            HStack(spacing: 8) {
                Image(systemName: pnl >= 0 ? "triangle.fill" : "triangle.fill")
                    .rotationEffect(pnl >= 0 ? .zero : .degrees(180))
                    .imageScale(.small)
                Text((pnl >= 0 ? "+" : "") + String(format: "%.0f", pnl))
                Text("(\(String(format: "%+.2f%%", pnlPct)))")
                Text("未实现").font(.footnote).foregroundStyle(.secondary)
            }
            .font(.callout.weight(.medium)).monospacedDigit()
            .foregroundStyle(DSColor.change(pnl, market: market, scheme: env.colorScheme))
        }
        .padding(.horizontal, 20)
    }

    private func accountsCard(_ accounts: [PortfolioAccountSnapshot]) -> some View {
        ModuleCard("账户 · \(accounts.count)") {
            VStack(spacing: 0) {
                ForEach(accounts) { acct in
                    HStack {
                        Text(acct.accountName ?? "账户 \(acct.accountId ?? 0)")
                            .font(.system(size: 15, weight: .medium))
                        Spacer()
                        Text("\(acct.baseCurrency ?? "")\(acct.totalEquity ?? 0, format: .number.precision(.fractionLength(0)))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    if acct.id != accounts.last?.id { Divider() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func positionsCard(_ positions: [PortfolioPositionItem]) -> some View {
        ModuleCard("持仓 · \(positions.count)") {
            VStack(spacing: 0) {
                ForEach(positions) { p in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.symbol).font(.system(size: 16, weight: .medium))
                            Text("\(Int(p.quantity ?? 0)) 股 · 成本 \(String(format: "%.2f", p.avgCost ?? 0))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(p.marketEnum.currencySymbol)\(Int(p.marketValueBase ?? 0))")
                                .font(.system(size: 15, weight: .medium)).monospacedDigit()
                            let pct = p.unrealizedPnlPct ?? 0
                            Text("\((pct >= 0 ? "+" : "") + String(format: "%.1f%%", pct))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DSColor.change(pct, market: p.marketEnum, scheme: env.colorScheme))
                        }
                    }
                    .padding(.vertical, 8)
                    if p.id != positions.last?.id { Divider() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func riskCard(_ risk: PortfolioRiskResponse) -> some View {
        ModuleCard("风险报告") {
            Text("成本方法: \(risk.costMethod ?? "—") · 截至 \(risk.asOf ?? "—")")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }
}

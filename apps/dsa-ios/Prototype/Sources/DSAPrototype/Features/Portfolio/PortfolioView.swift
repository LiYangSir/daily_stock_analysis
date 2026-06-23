import SwiftUI

@MainActor
final class PortfolioViewModel: ObservableObject {
    @Published var snapshot: PortfolioSnapshot?
    @Published var risk: PortfolioRisk?
    @Published var loading = false
    @Published var errorMessage: String?

    func load(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        if env.useMockData {
            snapshot = MockData.portfolio
            risk = MockData.portfolioRisk
            return
        }
        do {
            async let s: PortfolioSnapshot = env.auth.api.send(.get("/portfolio/snapshot"))
            async let r: PortfolioRisk = env.auth.api.send(.get("/portfolio/risk"))
            self.snapshot = try await s
            self.risk = try await r
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
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
                segmentControl.padding(.top, 4)
                Group {
                    switch segment {
                    case 0: PortfolioOverviewView()
                    case 1: DecisionSignalsView()
                    default: AlertsView()
                    }
                }
            }
            .background(Color.dsGroupedBackground)
            .navigationTitle("组合")
        }
    }

    private var segmentControl: some View {
        HStack(spacing: 6) {
            segChip("总览", index: 0)
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
                    if let alloc = snap.sectorAllocation, !alloc.isEmpty {
                        allocationCard(alloc)
                    }
                    positionsCard(snap.positions)
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

    private func totalsBlock(_ snap: PortfolioSnapshot) -> some View {
        let market = Market.cn // 总览以 A 股惯例显示
        return VStack(alignment: .leading, spacing: 4) {
            Text("总权益").font(.caption).foregroundStyle(.secondary).tracking(0.5)
            Text("¥\(snap.totalEquity, format: .number.precision(.fractionLength(2)))")
                .font(DSFont.display(38)).monospacedDigit()
            HStack(spacing: 8) {
                Image(systemName: snap.dailyPnl >= 0 ? "triangle.fill" : "triangle.fill")
                    .rotationEffect(snap.dailyPnl >= 0 ? .zero : .degrees(180))
                    .imageScale(.small)
                Text((snap.dailyPnl >= 0 ? "+" : "") + String(format: "¥%.0f", snap.dailyPnl))
                Text("(\((snap.dailyPnlPct >= 0 ? "+" : "") + String(format: "%.2f%%", snap.dailyPnlPct)))")
                Text("今日").font(.footnote).foregroundStyle(.secondary)
            }
            .font(.callout.weight(.medium)).monospacedDigit()
            .foregroundStyle(DSColor.change(snap.dailyPnl, market: market, scheme: env.colorScheme))
        }
        .padding(.horizontal, 20)
    }

    private func allocationCard(_ alloc: [SectorWeight]) -> some View {
        ModuleCard("仓位分布") {
            HStack(spacing: 14) {
                AllocationRing(items: alloc).frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(alloc) { item in
                        HStack(spacing: 8) {
                            Circle().fill(color(for: item.sector)).frame(width: 8, height: 8)
                            Text(item.sector).font(.footnote)
                            Spacer()
                            Text("\(Int(item.weight * 100))%").font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func positionsCard(_ positions: [Position]) -> some View {
        ModuleCard("持仓 · \(positions.count)") {
            VStack(spacing: 0) {
                ForEach(positions) { p in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.stockName ?? p.stockCode).font(.system(size: 16, weight: .medium))
                            Text("\(Int(p.quantity)) 股 · 成本 \(String(format: "%.2f", p.avgCost))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(p.market.currencySymbol)\(Int(p.marketValue))").font(.system(size: 15, weight: .medium)).monospacedDigit()
                            Text("\((p.pnlPct >= 0 ? "+" : "") + String(format: "%.1f%%", p.pnlPct))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DSColor.change(p.pnlPct, market: p.market, scheme: env.colorScheme))
                        }
                    }
                    .padding(.vertical, 8)
                    if p.id != positions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func riskCard(_ risk: PortfolioRisk) -> some View {
        ModuleCard("风险报告") {
            HStack(spacing: 16) {
                if let dd = risk.maxDrawdown {
                    statBlock("最大回撤", String(format: "%.1f%%", dd), color: .red)
                }
                if let sl = risk.stopLossLine {
                    statBlock("止损线", String(format: "¥%.0f", sl), color: .primary)
                }
                if let cov = risk.analysisCoverage {
                    statBlock("分析覆盖", String(format: "%.0f%%", cov * 100), color: .green)
                }
            }
            if let alerts = risk.alerts, !alerts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(alerts, id: \.self) { Text("· \($0)").font(.footnote) }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 16)
    }

    private func statBlock(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for sector: String) -> Color {
        switch sector {
        case "白酒消费": return DSColor.accent
        case "科技互联": return .blue
        case "新能源": return .purple
        case "医药": return .green
        case "现金": return .gray
        default: return .orange
        }
    }
}

// MARK: - Allocation Ring

struct AllocationRing: View {
    let items: [SectorWeight]

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.16), lineWidth: 9)
            let cumulative = computeRanges()
            ForEach(Array(cumulative.enumerated()), id: \.offset) { idx, range in
                Circle()
                    .trim(from: range.lowerBound, to: range.upperBound)
                    .stroke(palette[idx % palette.count], style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("\(items.count)").font(.system(size: 18, weight: .bold, design: .rounded))
                Text("类").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var palette: [Color] {
        [DSColor.accent, .blue, .purple, .green, .gray, .orange, .teal]
    }

    private func computeRanges() -> [Range<CGFloat>] {
        var ranges: [Range<CGFloat>] = []
        var acc: CGFloat = 0
        for it in items {
            let w = CGFloat(it.weight)
            ranges.append(acc..<(acc + w))
            acc += w
        }
        return ranges
    }
}

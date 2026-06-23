import SwiftUI

@MainActor
final class DecisionSignalsViewModel: ObservableObject {
    @Published var signals: [DecisionSignal] = []
    @Published var stats: DecisionSignalStats?
    @Published var filterAction: String = "all"
    @Published var loading = false
    @Published var errorMessage: String?

    func load(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        if env.useMockData {
            signals = MockData.decisionSignals
            stats = MockData.decisionStats
            return
        }
        do {
            self.signals = try await env.auth.api.send(.get("/decision-signals", query: ["limit": "30"]))
            self.stats = try? await env.auth.api.send(.get("/decision-signals/outcomes/stats"))
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func sendFeedback(env: AppEnvironment, signal: DecisionSignal, useful: Bool) async {
        if env.useMockData { return }
        struct Body: Encodable { let useful: Bool }
        let ep = (try? Endpoint.post("/decision-signals/\(signal.id)/feedback", body: Body(useful: useful)))
            ?? Endpoint(path: "/decision-signals/\(signal.id)/feedback", method: .PUT)
        try? await env.auth.api.sendVoid(ep)
    }

    var filtered: [DecisionSignal] {
        guard filterAction != "all" else { return signals }
        return signals.filter { $0.action.rawValue == filterAction }
    }
}

struct DecisionSignalsView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = DecisionSignalsViewModel()
    @State private var presented: DecisionSignal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filterRow
                if let stats = vm.stats { statsCard(stats) }
                signalListCard
                if let err = vm.errorMessage {
                    Text(err).font(.footnote).foregroundStyle(.red).padding(.horizontal, 20)
                }
                Color.clear.frame(height: 100)
            }
            .padding(.top, 6)
        }
        .task { await vm.load(env: env) }
        .sheet(item: $presented) { signal in
            DecisionSignalDetailSheet(signal: signal) { useful in
                Task { await vm.sendFeedback(env: env, signal: signal, useful: useful) }
            }
            .presentationDetents([.medium, .large])
            .environmentObject(env)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip("全部", value: "all")
                filterChip("买入", value: "buy")
                filterChip("加仓", value: "add")
                filterChip("减仓", value: "reduce")
                filterChip("卖出", value: "sell")
                filterChip("观望", value: "watch")
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterChip(_ title: String, value: String) -> some View {
        let active = vm.filterAction == value
        return Button { vm.filterAction = value } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(active ? DSColor.accent.opacity(0.16) : Color.gray.opacity(0.10),
                            in: Capsule())
                .foregroundStyle(active ? DSColor.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func statsCard(_ stats: DecisionSignalStats) -> some View {
        ModuleCard("统计") {
            HStack(spacing: 14) {
                stat("总数", String(stats.total))
                stat("命中率", String(format: "%.1f%%", stats.hitRate * 100), color: .green)
                stat("命中", String(stats.hit), color: .green)
                stat("未命中", String(stats.miss), color: .red)
            }
        }
        .padding(.horizontal, 16)
    }

    private func stat(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signalListCard: some View {
        ModuleCard("最近信号 · \(vm.filtered.count)") {
            VStack(spacing: 0) {
                ForEach(vm.filtered) { s in
                    Button { presented = s } label: {
                        signalRow(s)
                    }.buttonStyle(.plain)
                    if s.id != vm.filtered.last?.id { Divider() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func signalRow(_ s: DecisionSignal) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(s.stockName ?? s.stockCode) · \(s.stockCode)")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                Text("\(s.createdAt ?? "—") · \(phaseLabel(s.phase)) \(s.sourceReportId.map { "· #\($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ActionChip(action: s.action, label: s.actionLabel)
            statusBadge(s.status)
        }
        .padding(.vertical, 8)
    }

    private func phaseLabel(_ phase: String?) -> String {
        switch phase {
        case "premarket": return "盘前"
        case "intraday": return "盘中"
        case "postmarket": return "盘后"
        default: return phase ?? ""
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "active": return ("活跃", .green)
            case "closed": return ("已关闭", .secondary)
            case "expired": return ("过期", .secondary)
            case "invalidated": return ("作废", .red)
            case "archived": return ("归档", .secondary)
            default: return (status, .secondary)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color == .secondary ? Color.secondary : color)
    }
}

// MARK: - Detail Sheet

struct DecisionSignalDetailSheet: View {
    @EnvironmentObject var env: AppEnvironment
    let signal: DecisionSignal
    let onFeedback: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(signal.stockName ?? signal.stockCode) · \(signal.action.label)")
                        .font(.title3.bold())
                    Text("置信 \(String(format: "%.2f", signal.confidence ?? 0)) · \(signal.phase ?? "—") · \(signal.createdAt ?? "—")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ModuleCard("价格计划") {
                HStack {
                    pricePoint("入场", value: signal.entry, color: .primary)
                    pricePoint("止损", value: signal.stopLoss, color: DSColor.down(signal.market, scheme: env.colorScheme))
                    pricePoint("目标", value: signal.target, color: DSColor.up(signal.market, scheme: env.colorScheme))
                }
            }
            HStack(spacing: 8) {
                feedbackButton("👍 有用") { onFeedback(true) }
                feedbackButton("👎 无效") { onFeedback(false) }
                feedbackButton("关闭信号") {} 
            }
            Spacer()
        }
        .padding(20)
        .presentationBackground(.regularMaterial)
    }

    private func pricePoint(_ label: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feedbackButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(Color.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

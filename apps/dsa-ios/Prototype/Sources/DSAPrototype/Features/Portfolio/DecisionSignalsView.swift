import SwiftUI

@MainActor
final class DecisionSignalsViewModel: ObservableObject {
    @Published var signals: [DecisionSignal] = []
    @Published var stats: DecisionSignalStats?
    @Published var filterAction: String = "all"
    @Published var loading = false
    @Published var errorMessage: String?
    @Published private(set) var page: Int = 1
    @Published private(set) var hasMore: Bool = true

    private let pageSize = 30

    func load(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        page = 1; hasMore = true
        do {
            struct SigResp: Decodable { let items: [DecisionSignal]? }
            let sResp: SigResp = try await env.auth.api.send(.get("/decision-signals", query: ["limit": "\(pageSize)", "page": "1"]))
            self.signals = sResp.items ?? []
            if (sResp.items ?? []).count < pageSize { hasMore = false }
            self.stats = try? await env.auth.api.send(.get("/decision-signals/outcomes/stats"))
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMore(env: AppEnvironment) async {
        guard hasMore, !loading else { return }
        let next = page + 1
        struct SigResp: Decodable { let items: [DecisionSignal]? }
        let sResp: SigResp? = try? await env.auth.api.send(.get("/decision-signals", query: ["limit": "\(pageSize)", "page": "\(next)"]))
        let new = sResp?.items ?? []
        signals.append(contentsOf: new)
        page = next
        if new.count < pageSize { hasMore = false }
    }

    /// 对齐 DecisionSignalFeedbackRequest：feedback_value="useful"/"not_useful"，PUT。
    func sendFeedback(env: AppEnvironment, signal: DecisionSignal, useful: Bool) async {
        let body = DecisionSignalFeedbackRequest(feedbackValue: useful ? "useful" : "not_useful", source: "web")
        guard let data = try? JSONEncoder.dsa.encode(body) else { return }
        try? await env.auth.api.sendVoid(Endpoint(path: "/decision-signals/\(signal.id)/feedback", method: .PUT, body: data))
    }

    /// 更新决策信号状态：PATCH /decision-signals/{id}/status。
    /// status ∈ {closed, invalidated, archived}（终态，无法再回 active）。成功后刷新列表。
    func setStatus(env: AppEnvironment, signalId: Int, status: String) async {
        let body = DecisionSignalStatusUpdateRequest(status: status)
        do {
            let data = try JSONEncoder.dsa.encode(body)
            try await env.auth.api.sendVoid(Endpoint(path: "/decision-signals/\(signalId)/status", method: .PATCH, body: data))
            await load(env: env)
        } catch {
            errorMessage = "更新失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    var filtered: [DecisionSignal] {
        guard filterAction != "all" else { return signals }
        return signals.filter { $0.action?.rawValue == filterAction }
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
            DecisionSignalDetailSheet(signal: signal,
                onFeedback: { useful in
                    Task { await vm.sendFeedback(env: env, signal: signal, useful: useful) }
                },
                onStatus: { status in
                    presented = nil
                    Task { await vm.setStatus(env: env, signalId: signal.id, status: status) }
                })
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
                filterChip("持有", value: "hold")
                filterChip("减仓", value: "reduce")
                filterChip("卖出", value: "sell")
                filterChip("观望", value: "watch")
                filterChip("回避", value: "avoid")
                filterChip("警示", value: "alert")
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
                stat("总数", String(stats.total ?? 0))
                stat("命中率", String(format: "%.1f%%", stats.hitRatePct ?? 0), color: .green)
                stat("命中", String(stats.hit ?? 0), color: .green)
                stat("未命中", String(stats.miss ?? 0), color: .red)
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
        VStack(spacing: 10) {
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
            if vm.hasMore {
                Button { Task { await vm.loadMore(env: env) } } label: {
                    Text("加载更多").font(.caption.weight(.medium)).foregroundStyle(DSColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func signalRow(_ s: DecisionSignal) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(s.stockName ?? s.stockCode) · \(s.stockCode)")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                Text("\(s.createdAt ?? "—") · \(phaseLabel(s.marketPhase)) \(s.sourceReportId.map { "· #\($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ActionChip(action: s.action, label: s.actionLabel)
            statusBadge(s.status ?? "")
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
    @Environment(\.dismiss) private var dismiss
    let signal: DecisionSignal
    let onFeedback: (Bool) -> Void
    let onStatus: (String) -> Void
    @State private var outcomes: [DecisionSignalOutcomeItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerBlock
                planCard
                metricsStrip
                textSection("决策理由", signal.reason)
                textSection("催化剂", signal.catalystSummary)
                textSection("观察条件", signal.watchConditions)
                textSection("风险提示", signal.riskSummary, color: .orange)
                textSection("失效条件", signal.invalidation, color: .red)
                outcomesCard
                statusActions
                HStack(spacing: 8) {
                    feedbackButton("👍 有用") { onFeedback(true) }
                    feedbackButton("👎 无效") { onFeedback(false) }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationBackground(.regularMaterial)
        .task(id: signal.id) { await loadOutcomes() }
    }

    /// 生命周期操作：仅活跃信号允许流转到终态（closed/invalidated/archived）。
    @ViewBuilder
    private var statusActions: some View {
        if (signal.status ?? "active") == "active" {
            ModuleCard("生命周期") {
                VStack(spacing: 8) {
                    statusButton("关闭信号", system: "checkmark.circle", color: .secondary) { confirm("closed") }
                    statusButton("标记作废", system: "xmark.circle", color: .red) { confirm("invalidated") }
                    statusButton("归档", system: "archivebox", color: .secondary) { confirm("archived") }
                }
            }
        }
    }

    private func statusButton(_ title: String, system: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: system).foregroundStyle(color)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func confirm(_ status: String) {
        // 终态操作（closed/invalidated/archived）后端不可逆；执行后刷新列表。
        onStatus(status)
        dismiss()
    }


    private var headerBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(signal.stockName ?? signal.stockCode) · \(signal.action?.label ?? "—")")
                    .font(.title3.bold())
                Text("置信 \(String(format: "%.2f", signal.confidence ?? 0)) · \(phaseLabel(signal.marketPhase)) · \(signal.createdAt ?? "—")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(signal.status ?? "")
        }
    }

    private var planCard: some View {
        ModuleCard("价格计划") {
            HStack {
                pricePoint("入场", value: signal.entryLow, color: .primary)
                pricePoint("止损", value: signal.stopLoss, color: DSColor.down(signal.marketEnum, scheme: env.colorScheme))
                pricePoint("目标", value: signal.targetPrice, color: DSColor.up(signal.marketEnum, scheme: env.colorScheme))
            }
        }
    }

    @ViewBuilder
    private var metricsStrip: some View {
        let items: [(String, String?)] = [
            ("评分", signal.score.map { "\($0)" }),
            ("周期", horizonLabel(signal.horizon)),
            ("计划质量", planQualityLabel(signal.planQuality)),
            ("到期", signal.expiresAt.map { String($0.prefix(10)) }),
        ]
        let visible = items.filter { $0.1 != nil }
        if !visible.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, it in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(it.0).font(.system(size: 10)).foregroundStyle(.tertiary)
                        Text(it.1 ?? "—").font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private func textSection(_ title: String, _ text: String?, color: Color = .primary) -> some View {
        if let text, !text.isEmpty {
            ModuleCard(title) {
                Text(text).font(.subheadline).foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var outcomesCard: some View {
        if !outcomes.isEmpty {
            ModuleCard("历史兑现") {
                VStack(spacing: 0) {
                    ForEach(Array(outcomes.enumerated()), id: \.offset) { idx, o in
                        outcomeRow(o)
                        if idx < outcomes.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private func outcomeRow(_ o: DecisionSignalOutcomeItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(horizonLabel(o.horizon) ?? "—") · \(o.evalStatus ?? "—")").font(.caption.weight(.medium))
                if let ret = o.stockReturnPct {
                    Text("收益 \(String(format: "%+.2f%%", ret))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(o.outcome ?? "—")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(outcomeColor(o.outcome).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(outcomeColor(o.outcome))
        }
        .padding(.vertical, 6)
    }

    private func loadOutcomes() async {
        struct Resp: Decodable { let items: [DecisionSignalOutcomeItem]? }
        let resp: Resp? = try? await env.auth.api.send(.get("/decision-signals/\(signal.id)/outcomes"))
        outcomes = resp?.items ?? []
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

    private func phaseLabel(_ phase: String?) -> String {
        ["premarket": "盘前", "intraday": "盘中", "lunch_break": "午休", "closing_auction": "尾盘",
         "postmarket": "盘后", "non_trading": "休市"][phase ?? ""] ?? (phase ?? "—")
    }

    private func horizonLabel(_ h: String?) -> String? {
        guard let h else { return nil }
        return ["intraday": "日内", "1d": "1日", "3d": "3日", "5d": "5日", "10d": "10日",
                "swing": "波段", "long": "长线"][h] ?? h
    }

    private func planQualityLabel(_ q: String?) -> String? {
        guard let q else { return nil }
        return ["complete": "完整", "partial": "部分", "minimal": "最小", "unknown": "未知"][q] ?? q
    }

    private func outcomeColor(_ o: String?) -> Color {
        switch o ?? "" { case "hit": return .green; case "miss": return .red; default: return .secondary }
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

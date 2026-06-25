import SwiftUI

/// AlphaSift 选股页 ViewModel —— 与 Web `StockScreeningPage` 保持功能对齐：
/// 状态/启用/热点/异步任务轮询/候选明细。
@MainActor
final class ScreeningViewModel: ObservableObject {
    @Published var status: AlphaSiftStatus?
    @Published var hotspots: [AlphaSiftHotspot] = []
    @Published var hotspotDetails: [String: AlphaSiftHotspotDetail] = [:]
    @Published var hotspotsUpdatedAt: String?
    @Published var hotspotsLoading = false
    @Published var hotspotsError: String?

    @Published var strategies: [ScreeningStrategy] = []
    @Published var selectedStrategy: String = "dual_low"
    @Published var selectedMarket: String = "cn"
    @Published var maxResults: Int = 20

    @Published var screening = false
    @Published var screenStatusMessage: String?
    @Published var screenProgress: Int = 0
    @Published var screenError: String?
    @Published var screenResult: AlphaSiftScreenResponse?
    @Published var taskId: String?
    @Published var enabling = false
    @Published var expandedCandidate: String?
    @Published var expandedHotspot: String?

    private var pollTask: Task<Void, Never>?

    var enabled: Bool { status?.enabled ?? false }
    var available: Bool { status?.available ?? false }

    func loadAll(env: AppEnvironment) async {
        await refreshStatus(env: env)
        async let s: Void = loadStrategies(env: env)
        async let h: Void = refreshHotspots(env: env, force: false)
        _ = await (s, h)
    }

    func refreshStatus(env: AppEnvironment) async {
        do {
            self.status = try await env.auth.api.send(.get("/alphasift/status"))
        } catch {
            self.status = AlphaSiftStatus(enabled: false, available: false, installSpecIsDefault: nil,
                                          contractVersion: nil, version: nil, strategyCount: nil,
                                          diagnostics: ["reason": (error as? APIError)?.errorDescription ?? "unknown"])
        }
    }

    func loadStrategies(env: AppEnvironment) async {
        guard enabled else { strategies = []; return }
        do {
            let resp: ScreeningStrategiesResponse = try await env.auth.api.send(.get("/alphasift/strategies"))
            self.strategies = resp.strategies ?? []
            if let first = self.strategies.first(where: { $0.key == selectedStrategy }) ?? self.strategies.first {
                self.selectedStrategy = first.key
            }
        } catch {
            self.strategies = []
        }
    }

    func refreshHotspots(env: AppEnvironment, force: Bool) async {
        guard enabled else { hotspots = []; return }
        hotspotsLoading = true; defer { hotspotsLoading = false }
        do {
            let resp: AlphaSiftHotspotsResponse = try await env.auth.api.send(.get(
                "/alphasift/hotspots",
                query: ["provider": "akshare", "top": "12", "refresh": force ? "true" : "false", "include_details": "true"]
            ))
            self.hotspots = resp.hotspots ?? []
            self.hotspotDetails = resp.details ?? [:]
            self.hotspotsUpdatedAt = resp.cachedAt
            self.hotspotsError = nil
        } catch {
            self.hotspotsError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func toggleHotspot(_ topic: String, env: AppEnvironment) {
        if expandedHotspot == topic {
            expandedHotspot = nil
            return
        }
        expandedHotspot = topic
        if hotspotDetails[topic] == nil {
            Task { await fetchHotspotDetail(topic: topic, env: env) }
        }
    }

    func fetchHotspotDetail(topic: String, env: AppEnvironment) async {
        guard let encoded = topic.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        do {
            let detail: AlphaSiftHotspotDetail = try await env.auth.api.send(
                .get("/alphasift/hotspots/\(encoded)", query: ["provider": "akshare"])
            )
            hotspotDetails[topic] = detail
        } catch {
            // ignore; UI will show "暂无详情"
        }
    }

    func enableAlphaSift(env: AppEnvironment) async {
        enabling = true; defer { enabling = false }
        do {
            _ = try await ConfigWriter.update(api: env.auth.api,
                                              items: [(key: "ALPHASIFT_ENABLED", value: "true")])
            await refreshStatus(env: env)
            if !available {
                let reason = status?.diagnostics?["reason"] ?? "适配层不可用"
                screenError = "AlphaSift 已开启但运行环境不就绪（\(reason)）。请在后端执行 uv sync --frozen 或重建 Docker。"
                return
            }
            await loadStrategies(env: env)
            await refreshHotspots(env: env, force: false)
        } catch {
            screenError = "启用 AlphaSift 失败：\((error as? APIError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    func runScreen(env: AppEnvironment) async {
        guard enabled, available else {
            screenError = "AlphaSift 未启用或适配层不可用"
            return
        }
        cancelPolling()
        screening = true
        screenError = nil
        screenResult = nil
        screenProgress = 5
        screenStatusMessage = "提交选股任务中"
        expandedCandidate = nil

        struct Body: Encodable {
            let market: String
            let strategy: String
            let maxResults: Int
        }
        let body = Body(market: selectedMarket, strategy: selectedStrategy, maxResults: maxResults)
        do {
            let ep = try Endpoint.post("/alphasift/screen/tasks", body: body)
            let accepted: AlphaSiftScreenAccepted = try await env.auth.api.send(ep)
            self.taskId = accepted.taskId
            self.screenStatusMessage = accepted.message ?? "任务已提交，等待执行"
            startPolling(taskId: accepted.taskId, env: env)
        } catch {
            screening = false
            screenError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func startPolling(taskId: String, env: AppEnvironment) {
        pollTask = Task { [weak self] in
            guard let self else { return }
            // 与 Web `pollScreenTask` 一致的 ~2s 节拍；最多轮询 5 分钟。
            let deadline = Date().addingTimeInterval(300)
            while !Task.isCancelled, Date() < deadline {
                do {
                    let status: AlphaSiftScreenTaskStatus = try await env.auth.api.send(
                        .get("/alphasift/screen/tasks/\(taskId)")
                    )
                    await MainActor.run {
                        self.screenStatusMessage = status.message
                        self.screenProgress = status.progress ?? self.screenProgress
                    }
                    switch status.status {
                    case "completed":
                        await MainActor.run {
                            self.screenResult = status.result
                            self.screenProgress = 100
                            self.screening = false
                        }
                        return
                    case "failed":
                        await MainActor.run {
                            self.screenError = status.error ?? "选股任务失败"
                            self.screening = false
                        }
                        return
                    default:
                        break
                    }
                } catch {
                    await MainActor.run {
                        self.screenError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                        self.screening = false
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            await MainActor.run {
                if self.screening {
                    self.screenError = "选股任务超时，请稍后重试"
                    self.screening = false
                }
            }
        }
    }

    func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}

public struct ScreeningView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = ScreeningViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusBanner
                if vm.enabled {
                    hotspotsCard
                    paramsCard
                    runButton
                    if let err = vm.screenError {
                        InlineAlertView(text: err, kind: .danger)
                            .padding(.horizontal, 16)
                    }
                    if vm.screening || vm.screenResult != nil {
                        progressCard
                    }
                    candidatesCard
                }
                Color.clear.frame(height: 80)
            }
            .padding(.top, 8)
        }
        .background(Color.dsGroupedBackground)
        .navigationTitle("选股 (AlphaSift)")
        .dsInlineTitle()
        .task { await vm.loadAll(env: env) }
        .refreshable {
            await vm.refreshStatus(env: env)
            await vm.refreshHotspots(env: env, force: true)
        }
        .onDisappear { vm.cancelPolling() }
    }

    // MARK: - Status / Enable

    @ViewBuilder
    private var statusBanner: some View {
        if vm.status == nil {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.vertical, 12)
        } else if !vm.enabled {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(Color.gray).frame(width: 8, height: 8)
                    Text("AlphaSift 未开启")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text("启用后将拉取热点题材与候选股清单，可能消耗外部数据源调用次数。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    Task { await vm.enableAlphaSift(env: env) }
                } label: {
                    HStack {
                        if vm.enabling { ProgressView().scaleEffect(0.7).tint(.white) }
                        Text(vm.enabling ? "启用中…" : "启用 AlphaSift")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(DSColor.accent, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(vm.enabling)
            }
            .padding(14)
            .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        } else if !vm.available {
            let reason = vm.status?.diagnostics?["reason"]
            InlineAlertView(
                text: "AlphaSift 适配层不可用" + (reason.map { "（\($0)）" } ?? "") + "。请确认后端依赖已安装。",
                kind: .warning
            )
            .padding(.horizontal, 16)
        } else {
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("AlphaSift 已启用")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let count = vm.status?.strategyCount {
                    Text("\(count) 策略").font(.caption2).foregroundStyle(.secondary)
                }
                if let v = vm.status?.version {
                    Text("v\(v)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Hotspots

    private var hotspotsCard: some View {
        ModuleCard(
            "热点题材",
            trailing: AnyView(
                Button {
                    Task { await vm.refreshHotspots(env: env, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DSColor.accent)
                }
                .disabled(vm.hotspotsLoading)
            )
        ) {
            if vm.hotspotsLoading && vm.hotspots.isEmpty {
                HStack { Spacer(); ProgressView().scaleEffect(0.8); Spacer() }
                    .padding(.vertical, 16)
            } else if let err = vm.hotspotsError, vm.hotspots.isEmpty {
                Text(err).font(.footnote).foregroundStyle(.red)
            } else if vm.hotspots.isEmpty {
                Text("暂无热点数据").font(.footnote).foregroundStyle(.secondary)
            } else {
                if let updated = vm.hotspotsUpdatedAt {
                    Text("更新时间：\(updated)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(vm.hotspots) { h in hotspotCell(h) }
                }
                if let topic = vm.expandedHotspot, let detail = vm.hotspotDetails[topic] {
                    hotspotDetailView(detail)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func hotspotCell(_ h: AlphaSiftHotspot) -> some View {
        let pct = h.changePct ?? 0
        let up = pct >= 0
        let color: Color = up ? .red : .green
        let isExpanded = vm.expandedHotspot == h.topic
        return Button {
            vm.toggleHotspot(h.topic, env: env)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let rank = h.rank { Text("#\(rank)").font(.caption2).foregroundStyle(.secondary) }
                    Text(h.name ?? h.topic)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if let count = h.sampleStockCount ?? h.observations {
                        Text("\(count) 只").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text((up ? "↑ +" : "↓ ") + String(format: "%.1f%%", abs(pct)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(color)
                }
                if h.heatScore != nil || h.trendScore != nil || h.persistenceScore != nil {
                    HStack(spacing: 8) {
                        if let heat = h.heatScore { scoreMini("热", heat) }
                        if let trend = h.trendScore { scoreMini("势", trend) }
                        if let persist = h.persistenceScore { scoreMini("续", persist) }
                        Spacer()
                    }
                }
                if let leaders = h.leaders, !leaders.isEmpty {
                    Text("龙头：\(leaders.prefix(3).joined(separator: " · "))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(isExpanded ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func hotspotDetailView(_ detail: AlphaSiftHotspotDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.name ?? detail.topic)
                .font(.subheadline.weight(.semibold))
            if let status = detail.qualityStatus, !status.isEmpty {
                Text("数据质量：\(status)").font(.caption2).foregroundStyle(.secondary)
            }
            if let timeline = (detail.timeline?.isEmpty == false ? detail.timeline : detail.route), !timeline.isEmpty {
                Text("催化时间线").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ForEach(timeline.prefix(5)) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.date ?? item.publishedAt ?? "·")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title ?? "—").font(.caption.weight(.medium)).lineLimit(2)
                            if let desc = item.description, !desc.isEmpty {
                                Text(desc).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            if let stocks = detail.stocks, !stocks.isEmpty {
                Text("概念股 · \(detail.stockCount ?? stocks.count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ForEach(stocks.prefix(8)) { stock in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(stock.name ?? stock.code ?? "—").font(.caption)
                                Text(stock.code ?? "").font(.caption2).foregroundStyle(.secondary)
                                if let role = stock.role, !role.isEmpty {
                                    Text(role).font(.system(size: 9))
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color.gray.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let src = stock.source, !src.isEmpty {
                                Text("\(src)\(stock.sourceConfidence.map { " · 置信 \(String(format: "%.0f%%", $0 * 100))" } ?? "")")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if let pct = stock.changePct {
                            let m = Market(stockCode: stock.code ?? "")
                            Text("\((pct >= 0 ? "+" : ""))\(String(format: "%.2f%%", pct))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(DSColor.change(pct, market: m, scheme: env.colorScheme))
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.dsSystemFill, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Params

    private var paramsCard: some View {
        ModuleCard("策略参数") {
            HStack {
                Text("市场").font(.subheadline)
                Spacer()
                Picker("市场", selection: $vm.selectedMarket) {
                    Text("A 股").tag("cn")
                    Text("港股").tag("hk")
                    Text("美股").tag("us")
                }.pickerStyle(.menu)
            }
            HStack {
                Text("策略").font(.subheadline)
                Spacer()
                Picker("策略", selection: $vm.selectedStrategy) {
                    if vm.strategies.isEmpty {
                        Text("加载中…").tag(vm.selectedStrategy)
                    } else {
                        ForEach(vm.strategies) { s in
                            Text(s.title?.isEmpty == false ? s.title! : s.name).tag(s.key)
                        }
                    }
                }.pickerStyle(.menu)
            }
            if let desc = vm.strategies.first(where: { $0.key == vm.selectedStrategy })?.description, !desc.isEmpty {
                Text(desc).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            }
            HStack {
                Text("最大结果").font(.subheadline)
                Spacer()
                Stepper("\(vm.maxResults)", value: $vm.maxResults, in: 5...50, step: 5).labelsHidden()
                Text("\(vm.maxResults)").monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Run / Progress

    private var runButton: some View {
        Button {
            Task { await vm.runScreen(env: env) }
        } label: {
            HStack {
                if vm.screening { ProgressView().tint(.white) }
                Text(vm.screening ? "选股进行中…" : "执行选股")
            }
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(vm.available ? DSColor.accent : Color.gray.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .disabled(vm.screening || !vm.available)
    }

    @ViewBuilder
    private var progressCard: some View {
        ModuleCard("任务进度") {
            VStack(alignment: .leading, spacing: 6) {
                if let tid = vm.taskId {
                    Text("Task: \(tid.prefix(12))…")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if vm.screening {
                    ProgressView(value: Double(vm.screenProgress) / 100.0)
                        .tint(DSColor.accent)
                }
                if let msg = vm.screenStatusMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                if let result = vm.screenResult {
                    HStack(spacing: 12) {
                        statChip(label: "候选", value: "\(result.candidateCount ?? 0)")
                        if let snap = result.snapshotCount { statChip(label: "快照", value: "\(snap)") }
                        if let after = result.afterFilterCount { statChip(label: "过滤后", value: "\(after)") }
                        if let cov = result.llmCoverage { statChip(label: "LLM", value: String(format: "%.0f%%", cov * 100)) }
                    }
                    if result.llmRanked == true {
                        Text("已通过 LLM 重排").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let enrich = result.dsaEnrichment, let enriched = enrich.enrichedCount, enriched > 0 {
                        Text("DSA 增强：\(enriched) 条").font(.caption2).foregroundStyle(.secondary)
                    }
                    let warns = (result.warnings ?? []) + (result.sourceErrors ?? []) + (result.llmParseErrors ?? [])
                    if !warns.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(warns.prefix(5), id: \.self) { w in
                                Text("⚠︎ \(w)").font(.caption2).foregroundStyle(.orange).lineLimit(2)
                            }
                            if warns.count > 5 {
                                Text("…共 \(warns.count) 条").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func statChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary).tracking(0.4)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.dsSystemFill, in: RoundedRectangle(cornerRadius: 6))
    }

    private func scoreMini(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text("\(Int(value))").font(.caption2.monospacedDigit()).bold()
        }
    }

    // MARK: - Candidates

    @ViewBuilder
    private var candidatesCard: some View {
        let list = vm.screenResult?.candidates ?? []
        ModuleCard("候选股 · \(list.count)") {
            if list.isEmpty {
                Text(vm.screening ? "正在筛选…" : "尚未运行选股")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(list) { c in
                        candidateRow(c)
                        if c.id != list.last?.id { Divider() }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func candidateRow(_ c: ScreeningCandidate) -> some View {
        let isExpanded = vm.expandedCandidate == c.code
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) {
                    vm.expandedCandidate = isExpanded ? nil : c.code
                }
            } label: {
                HStack(spacing: 10) {
                    if let r = c.rank { Text("#\(r)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24, alignment: .leading) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name ?? c.code).font(.system(size: 15, weight: .medium))
                        HStack(spacing: 6) {
                            Text(c.code).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            if let industry = c.industry, !industry.isEmpty {
                                Text("· \(industry)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            if let price = c.price {
                                Text("· \(String(format: "%.2f", price))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            if let score = c.score {
                                Text("· 评分 \(Int(score))").font(.caption2).foregroundStyle(.secondary)
                            }
                            if let llm = c.llmScore {
                                Text("· LLM \(Int(llm))").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    if let risk = c.riskLevel, !risk.isEmpty {
                        Text(riskLabel(risk)).font(.caption2.weight(.medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(riskColor(risk).opacity(0.15), in: Capsule())
                            .foregroundStyle(riskColor(risk))
                    }
                    if let pct = c.changePct {
                        ChangeChip(percent: pct, market: c.market, scheme: env.colorScheme)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded { candidateDetail(c) }
        }
    }

    @ViewBuilder
    private func candidateDetail(_ c: ScreeningCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = c.reason, !reason.isEmpty {
                detailBlock(title: "选股理由", body: reason)
            }
            if let thesis = c.llmThesis, !thesis.isEmpty {
                detailBlock(title: "LLM 答辩", body: thesis)
            }
            if let summary = c.dsaAnalysisSummary, !summary.isEmpty {
                detailBlock(title: "DSA 摘要", body: summary)
            }
            if let catalysts = c.llmCatalysts, !catalysts.isEmpty {
                detailBlock(title: "催化因素", body: catalysts.joined(separator: "\n• "))
            }
            if let watch = c.llmWatchItems, !watch.isEmpty {
                detailBlock(title: "需关注", body: watch.joined(separator: "\n• "))
            }
            if let risks = c.llmRisks, !risks.isEmpty {
                detailBlock(title: "风险点", body: risks.joined(separator: "\n• "))
            }
            if let factors = c.factorScores, !factors.isEmpty {
                Text("主要因子").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                let top = Array(factors.sorted { abs($0.value) > abs($1.value) }.prefix(6))
                FlowLayout(spacing: 6) {
                    ForEach(top, id: \.key) { (key, value) in
                        HStack(spacing: 4) {
                            Text(key).font(.caption2)
                            Text(String(format: "%.2f", value))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.dsSystemFill, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            if let news = c.dsaNews, !news.isEmpty {
                Text("DSA 新闻").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ForEach(news.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title ?? "—").font(.caption.weight(.medium)).lineLimit(2)
                        if let snippet = item.snippet, !snippet.isEmpty {
                            Text(snippet).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
            if let flags = c.riskFlags, !flags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(flags, id: \.self) { tag in
                        Text(tag).font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.dsSystemFill, in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 6)
    }

    private func detailBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(body).font(.caption).lineSpacing(2)
        }
    }

    private func riskLabel(_ r: String) -> String {
        switch r.lowercased() {
        case "high": return "高风险"
        case "medium": return "中风险"
        case "low": return "低风险"
        default: return r
        }
    }

    private func riskColor(_ r: String) -> Color {
        switch r.lowercased() {
        case "high": return .red
        case "medium": return .orange
        case "low": return .green
        default: return .secondary
        }
    }
}

// MARK: - InlineAlertView

enum InlineAlertKind { case info, warning, danger }

struct InlineAlertView: View {
    let text: String
    let kind: InlineAlertKind

    var body: some View {
        let (bg, fg, icon): (Color, Color, String) = {
            switch kind {
            case .info: return (Color.blue.opacity(0.12), .blue, "info.circle")
            case .warning: return (Color.orange.opacity(0.14), .orange, "exclamationmark.triangle")
            case .danger: return (Color.red.opacity(0.12), .red, "xmark.octagon")
            }
        }()
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(fg)
            Text(text).font(.footnote).foregroundStyle(fg).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(bg, in: RoundedRectangle(cornerRadius: 10))
    }
}

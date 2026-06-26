import SwiftUI

@MainActor
final class AnalysisSubmitViewModel: ObservableObject {
    @Published var stockInputs: [String] = []
    @Published var pendingInput: String = ""
    @Published var skills: [AgentSkill] = []
    @Published var selectedSkills: Set<String> = []
    @Published var reportType: String = "detailed"
    @Published var reportLanguage: String = "zh"
    @Published var analysisPhase: String = "auto"
    @Published var notify: Bool = true
    @Published var forceRefresh: Bool = false
    @Published var submitting = false
    @Published var errorMessage: String?
    @Published var submitInfo: String?      // 提交成功提示（含 task_id），用于定位「提交是否真的成功」

    func load(env: AppEnvironment) async {
        do {
            struct SkillsResp: Decodable { let skills: [AgentSkill]? }
            let resp: SkillsResp = try await env.auth.api.send(.get("/agent/skills"))
            self.skills = resp.skills ?? []
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    func addPending() {
        let trimmed = pendingInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !stockInputs.contains(trimmed), stockInputs.count < 50 else { return }
        stockInputs.append(trimmed)
        pendingInput = ""
    }

    func remove(_ code: String) {
        stockInputs.removeAll { $0 == code }
    }

    func submit(env: AppEnvironment, taskStream: TaskStreamStore) async {
        guard !stockInputs.isEmpty else { return }
        submitting = true
        defer { submitting = false }

        struct Body: Encodable {
            let stockCodes: [String]
            let skills: [String]
            let reportType: String
            let reportLanguage: String
            let analysisPhase: String
            let notify: Bool
            let forceRefresh: Bool
            let asyncMode: Bool
        }
        let body = Body(stockCodes: stockInputs,
                        skills: Array(selectedSkills),
                        reportType: reportType, reportLanguage: reportLanguage,
                        analysisPhase: analysisPhase, notify: notify,
                        forceRefresh: forceRefresh, asyncMode: true)
        do {
            let ep = try Endpoint.post("/analysis/analyze", body: body)
            try await env.auth.api.sendVoid(ep)
            submitInfo = "✓ 已提交，分析约需 1–3 分钟，完成后会在此提示并进入历史报告"
            errorMessage = nil
            stockInputs.removeAll()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            submitInfo = nil
        }
    }
}

public struct AnalysisView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var taskStream: TaskStreamStore
    @StateObject private var vm = AnalysisSubmitViewModel()
    @State private var segment: Int = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CompactPageTitle("分析")
                    segmentControl
                    if segment == 0 {
                        submitForm
                    } else if segment == 1 {
                        marketReviewSection
                    } else {
                        Color.clear.frame(height: 0)
                    }
                    activeTasksSection
                    finishedTasksSection
                    Color.clear.frame(height: 100)
                }
            }
            .background(Color.dsGroupedBackground)
            .hideNavBar()
            .overlay(alignment: .top) { completionToast }
            .task {
                await vm.load(env: env)
                taskStream.start(env: env)
            }
            .onChange(of: taskStream.lastCompleted?.id) { _, newID in
                guard let target = newID else { return }
                // 5s 后自动收起「报告已生成」提示
                Task { try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if taskStream.lastCompleted?.id == target { taskStream.clearLastCompleted() }
                }
            }
        }
    }

    /// 任务完成后点开对应报告：拉取该股最新一份历史报告并以详情页打开。
    private func openReport(code: String) {
        guard !code.isEmpty else { return }
        Task { @MainActor in
            let resp: HistoryListResponse? = try? await env.auth.api.send(
                .get("/history", query: ["stock_code": code, "limit": "1"]))
            if let item = resp?.items?.first {
                taskStream.clearLastCompleted()
                env.presentedReport = item
            }
        }
    }

    /// 最近完成/失败的任务区，点按直接打开报告（闭环此前断在这里）。
    private var finishedTasksSection: some View {
        let finished = taskStream.finishedTasks
        return VStack(alignment: .leading, spacing: 8) {
            if !finished.isEmpty {
                Text("最近完成")
                    .font(.footnote).tracking(0.5).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(finished) { task in
                        Button { openReport(code: task.stockCode ?? "") } label: { finishedTaskRow(task) }
                            .buttonStyle(.plain)
                        if task.id != finished.last?.id { Divider().padding(.leading, 16) }
                    }
                }
                .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
        }
    }

    private func finishedTaskRow(_ t: TaskInfo) -> some View {
        let failed = (t.status == "failed")
        return HStack(spacing: 12) {
            Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(failed ? .red : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.stockName ?? t.stockCode ?? "—").font(.system(size: 16, weight: .medium))
                Text(failed ? (t.message ?? "分析失败") : "报告已生成 · 点按查看")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !failed { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
    }

    /// 任务完成瞬间的顶部轻提示：点「查看」直接跳报告；5s 自动消失。
    @ViewBuilder
    private var completionToast: some View {
        if let done = taskStream.lastCompleted {
            let failed = (done.status == "failed")
            let title = (done.stockName ?? done.stockCode ?? "分析") + (failed ? " · 分析失败" : " · 报告已生成")
            Button {
                if failed { taskStream.clearLastCompleted() } else { openReport(code: done.stockCode ?? "") }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: failed ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .foregroundStyle(failed ? .orange : .green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.subheadline.weight(.medium))
                        if failed, let m = done.message, !m.isEmpty {
                            Text(m).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(failed ? "知道了" : "查看 ›").font(.caption.weight(.semibold)).foregroundStyle(DSColor.accent)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
                .padding(.horizontal, 16).padding(.top, 8)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var segmentControl: some View {
        HStack(spacing: 6) {
            segChip("提交分析", index: 0)
            segChip("大盘点评", index: 1)
            segChip("活跃任务 · \(taskStream.activeTasks.count)", index: 2)
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

    @ViewBuilder
    private var submitForm: some View {
        ModuleCard("股票代码", trailing: AnyView(Text("最多 50 支").font(.caption2).foregroundStyle(.secondary))) {
            FlowLayout(spacing: 6) {
                ForEach(vm.stockInputs, id: \.self) { code in
                    HStack(spacing: 4) {
                        Text(code).font(.caption.weight(.medium))
                        Button { vm.remove(code) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.blue)
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("输入股票代码或名称", text: $vm.pendingInput)
                    .autocorrectionDisabled()
                    .onSubmit { vm.addPending() }
                Button("添加") { vm.addPending() }
                    .font(.footnote).disabled(vm.pendingInput.isEmpty)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 16)

        ModuleCard("分析技能", trailing: AnyView(Text("可选").font(.caption2).foregroundStyle(.secondary))) {
            FlowLayout(spacing: 6) {
                ForEach(vm.skills) { skill in
                    Button {
                        if vm.selectedSkills.contains(skill.key ?? "") {
                            vm.selectedSkills.remove(skill.key ?? "")
                        } else if vm.selectedSkills.count < 3 {
                            vm.selectedSkills.insert(skill.key ?? "")
                        }
                    } label: {
                        Text("\(skill.icon ?? "") \(skill.name)")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(vm.selectedSkills.contains(skill.key ?? "")
                                        ? DSColor.accent.opacity(0.16)
                                        : Color.gray.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(vm.selectedSkills.contains(skill.key ?? "") ? DSColor.accent : .secondary)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)

        ModuleCard("报告参数") {
            paramRow("报告类型", value: reportTypeLabel)
            paramRow("语言", value: vm.reportLanguage == "zh" ? "中文" : "English")
            paramRow("分析阶段", value: phaseLabel)
            Toggle("完成后通知", isOn: $vm.notify).font(.subheadline)
            Toggle("强制重新分析", isOn: $vm.forceRefresh).font(.subheadline)
        }
        .padding(.horizontal, 16)

        Button {
            Task { await vm.submit(env: env, taskStream: taskStream) }
        } label: {
            HStack {
                if vm.submitting { ProgressView().tint(.white) }
                Text("提交分析（\(vm.stockInputs.count) 支）")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(vm.stockInputs.isEmpty ? Color.gray.opacity(0.4) : DSColor.accent,
                        in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .disabled(vm.stockInputs.isEmpty || vm.submitting)
        .padding(.horizontal, 16)

        if let err = vm.errorMessage {
            Text(err).font(.footnote).foregroundStyle(.red).padding(.horizontal, 20)
        }
        if let info = vm.submitInfo {
            Text(info).font(.footnote).foregroundStyle(.green).padding(.horizontal, 20)
        }
    }

    private var marketReviewSection: some View {
        ModuleCard("大盘点评") {
            Text("一键触发当日大盘复盘，结果完成后会出现在历史报告。")
                .font(.callout).foregroundStyle(.secondary).lineSpacing(2)
            Button {
                Task {
                        try? await env.auth.api.sendVoid(.init(path: "/analysis/market-review", method: .POST))
                    
                }
            } label: {
                Text("触发大盘点评")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16).frame(height: 36)
                    .background(DSColor.accent, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }.buttonStyle(.plain).padding(.top, 8)
        }
        .padding(.horizontal, 16)
    }

    private var activeTasksSection: some View {
        let activeTasks = taskStream.activeTasks
        return VStack(alignment: .leading, spacing: 8) {
            if !activeTasks.isEmpty {
                Text("活跃任务")
                    .font(.footnote).tracking(0.5).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(activeTasks) { task in
                        taskRow(task)
                        if task.id != activeTasks.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
        }
    }

    private func taskRow(_ t: TaskInfo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.stockName ?? t.stockCode ?? "—").font(.system(size: 17, weight: .medium))
                Text("\(Int(t.progress ?? 0))% · \(t.message ?? t.status)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            ProgressRing(progress: (t.progress ?? 0) / 100)
                .frame(width: 32, height: 32)
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
    }

    private var reportTypeLabel: String {
        ["simple": "简要", "detailed": "完整", "full": "深度", "brief": "速览"][vm.reportType] ?? vm.reportType
    }

    private var phaseLabel: String {
        ["auto": "自动判断", "premarket": "盘前", "intraday": "盘中", "postmarket": "盘后"][vm.analysisPhase] ?? vm.analysisPhase
    }

    private func paramRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text("\(value) ›").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

// MARK: - ProgressRing

struct ProgressRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(DSColor.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - FlowLayout (轻量版)

struct FlowLayout: Layout {
    let spacing: CGFloat
    init(spacing: CGFloat = 6) { self.spacing = spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        let arranged = arrange(subviews: subviews, width: maxWidth)
        return CGSize(width: maxWidth, height: arranged.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(subviews: subviews, width: bounds.width)
        for (index, frame) in arranged.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.origin.x,
                                              y: bounds.minY + frame.origin.y),
                                  proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (frames, y + lineHeight)
    }
}

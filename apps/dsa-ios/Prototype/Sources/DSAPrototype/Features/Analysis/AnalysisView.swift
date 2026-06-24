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
            stockInputs.removeAll()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
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
                    Color.clear.frame(height: 100)
                }
            }
            .background(Color.dsGroupedBackground)
            .hideNavBar()
            .task {
                await vm.load(env: env)
                taskStream.start(env: env)
            }
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

import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var period: String = "month"
    @Published var dashboard: UsageDashboard?
    @Published var loading = false
    @Published var errorMessage: String?

    func load(env: AppEnvironment) async {
        do {
            self.dashboard = try await env.auth.api.send(.get("/usage/dashboard", query: ["period": period]))
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}

public struct UsageView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = UsageViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                periodPicker
                if let d = vm.dashboard {
                    statGrid(d)
                    if let models = d.byModel, !models.isEmpty { modelsCard(models) }
                    if let types = d.byCallType, !types.isEmpty { callTypesCard(types) }
                    if let recent = d.recentCalls, !recent.isEmpty { recentCard(recent) }
                }
                if let err = vm.errorMessage {
                    Text(err).font(.footnote).foregroundStyle(.red).padding(.horizontal, 20)
                }
                Color.clear.frame(height: 80)
            }
            .padding(.top, 8)
        }
        .background(Color.dsGroupedBackground)
        .navigationTitle("Token 用量")
        .dsInlineTitle()
        .task { await vm.load(env: env) }
    }

    private var periodPicker: some View {
        HStack(spacing: 6) {
            chip("今天", value: "today")
            chip("本月", value: "month")
            chip("全部", value: "all")
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func chip(_ title: String, value: String) -> some View {
        let active = vm.period == value
        return Button {
            vm.period = value
            Task { await vm.load(env: env) }
        } label: {
            Text(title).font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(active ? DSColor.accent.opacity(0.16) : Color.gray.opacity(0.10), in: Capsule())
                .foregroundStyle(active ? DSColor.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func statGrid(_ d: UsageDashboard) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return VStack(alignment: .leading, spacing: 8) {
            if let from = d.fromDate, let to = d.toDate {
                Text("\(from) ~ \(to)").font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 2)
            }
            LazyVGrid(columns: cols, spacing: 10) {
                statCard("总 Token", formatTokens(d.totalTokens ?? 0))
                statCard("调用次数", String(d.totalCalls ?? 0))
                statCard("Prompt", formatTokens(d.totalPromptTokens ?? 0))
                statCard("Completion", formatTokens(d.totalCompletionTokens ?? 0))
            }
        }
        .padding(.horizontal, 16)
    }

    private func statCard(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 14))
    }

    private func modelsCard(_ items: [UsageModelBreakdown]) -> some View {
        let total = items.compactMap(\.totalTokens).reduce(0, +)
        return ModuleCard("模型分布") {
            VStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, m in
                    let weight = total > 0 ? Double(m.totalTokens ?? 0) / Double(total) : 0
                    VStack(spacing: 3) {
                        HStack(spacing: 8) {
                            Text(m.model).font(.caption).foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .leading).lineLimit(1)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.gray.opacity(0.16))
                                    Capsule().fill(palette[idx % palette.count])
                                        .frame(width: geo.size.width * CGFloat(weight))
                                }
                            }.frame(height: 8)
                            Text(formatTokens(m.totalTokens ?? 0))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                        HStack(spacing: 6) {
                            Text("P \(formatTokens(m.promptTokens ?? 0))")
                            Text("· C \(formatTokens(m.completionTokens ?? 0))")
                            if let mx = m.maxTotalTokens, mx > 0 { Text("· 峰值 \(formatTokens(mx))") }
                            Spacer()
                        }
                        .font(.caption2).foregroundStyle(.tertiary).padding(.leading, 108)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func callTypesCard(_ items: [UsageCallTypeBreakdown]) -> some View {
        let total = items.compactMap(\.calls).reduce(0, +)
        return ModuleCard("调用类型") {
            VStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, t in
                    let weight = total > 0 ? Double(t.calls ?? 0) / Double(total) : 0
                    VStack(spacing: 3) {
                        HStack(spacing: 8) {
                            Text(callTypeLabel(t.callType)).font(.caption).foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.gray.opacity(0.16))
                                    Capsule().fill(palette[idx % palette.count])
                                        .frame(width: geo.size.width * CGFloat(weight))
                                }
                            }.frame(height: 8)
                            Text("\(t.calls ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                        HStack(spacing: 6) {
                            Text("P \(formatTokens(t.promptTokens ?? 0))")
                            Text("· C \(formatTokens(t.completionTokens ?? 0))")
                            Text("· \(formatTokens(t.totalTokens ?? 0))")
                            Spacer()
                        }
                        .font(.caption2).foregroundStyle(.tertiary).padding(.leading, 108)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func recentCard(_ items: [UsageCallRecord]) -> some View {
        ModuleCard("最近调用 · \(items.count)") {
            VStack(spacing: 0) {
                ForEach(items) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.calledAt ?? "—") · \(callTypeLabel(r.callType ?? "")) · \(r.model ?? "")")
                                .font(.system(size: 13, weight: .medium)).lineLimit(1)
                            HStack(spacing: 6) {
                                Text("prompt \(formatTokens(r.promptTokens ?? 0)) · completion \(formatTokens(r.completionTokens ?? 0)) · \(formatTokens(r.totalTokens ?? 0))")
                                if let code = r.stockCode, !code.isEmpty { Text("· \(code)") }
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    if r.id != items.last?.id { Divider() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var palette: [Color] {
        [DSColor.accent, .blue, .purple, .green, .orange, .teal]
    }

    private func callTypeLabel(_ key: String) -> String {
        switch key {
        case "analysis": return "个股分析"
        case "agent": return "AI 对话"
        case "market_review": return "大盘点评"
        default: return key
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return String(n)
    }
}

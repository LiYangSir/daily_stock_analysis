import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var period: String = "month"
    @Published var dashboard: UsageDashboard?
    @Published var loading = false
    @Published var errorMessage: String?

    func load(env: AppEnvironment) async {
        if env.useMockData {
            dashboard = MockData.usageDashboard
            return
        }
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
                    modelsCard(d.modelStats)
                    callTypesCard(d.callTypes)
                    recentCard(d.recent)
                }
                Color.clear.frame(height: 80)
            }
            .padding(.top, 8)
        }
        .background(Color.dsGroupedBackground)
        .navigationTitle("Token 用量")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        return LazyVGrid(columns: cols, spacing: 10) {
            statCard("总 Token", formatTokens(d.totalTokens))
            statCard("调用次数", String(d.totalCalls))
            statCard("Prompt", formatTokens(d.promptTokens))
            statCard("Completion", formatTokens(d.completionTokens))
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

    private func modelsCard(_ items: [UsageModelStat]) -> some View {
        ModuleCard("模型分布") {
            VStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, m in
                    HStack(spacing: 8) {
                        Text(m.model).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Color.gray.opacity(0.16))
                            Capsule().fill(palette[idx % palette.count])
                                .frame(width: geo.size.width * CGFloat(m.weight))
                        }.frame(height: 8)
                        Text(formatTokens(m.tokens)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func callTypesCard(_ items: [UsageCallType]) -> some View {
        ModuleCard("调用类型") {
            VStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, t in
                    HStack(spacing: 8) {
                        Text(t.type).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Color.gray.opacity(0.16))
                            Capsule().fill(palette[idx % palette.count])
                                .frame(width: geo.size.width * CGFloat(t.weight))
                        }.frame(height: 8)
                        Text("\(t.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func recentCard(_ items: [UsageRecord]) -> some View {
        ModuleCard("最近调用 · \(items.count)") {
            VStack(spacing: 0) {
                ForEach(items) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.time) · \(r.type) · \(r.model)").font(.system(size: 13, weight: .medium))
                            Text("prompt \(formatTokens(r.promptTokens)) · completion \(formatTokens(r.completionTokens)) · \(formatTokens(r.promptTokens + r.completionTokens))")
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
        [DSColor.accent, .blue, .purple, .green, .orange]
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return String(n)
    }
}

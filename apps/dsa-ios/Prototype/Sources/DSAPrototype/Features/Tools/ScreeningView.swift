import SwiftUI

@MainActor
final class ScreeningViewModel: ObservableObject {
    @Published var hotspots: [Hotspot] = []
    @Published var strategies: [ScreeningStrategy] = []
    @Published var candidates: [ScreeningCandidate] = []
    @Published var selectedStrategy: String = "breakout"
    @Published var selectedMarket: String = "cn"
    @Published var maxResults: Int = 20
    @Published var loading = false
    @Published var errorMessage: String?

    func load(env: AppEnvironment) async {
        if env.useMockData {
            hotspots = MockData.hotspots
            strategies = MockData.strategies
            candidates = MockData.candidates
            return
        }
        self.hotspots = (try? await env.auth.api.send(.get("/alphasift/hotspots"))) ?? []
        self.strategies = (try? await env.auth.api.send(.get("/alphasift/strategies"))) ?? []
    }

    func runScreen(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        if env.useMockData {
            try? await Task.sleep(nanoseconds: 800_000_000)
            candidates = MockData.candidates
            return
        }
        // 真实接入应轮询 /alphasift/screen/tasks/{id}，原型简化
    }
}

public struct ScreeningView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = ScreeningViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hotspotsCard
                paramsCard
                Button {
                    Task { await vm.runScreen(env: env) }
                } label: {
                    HStack {
                        if vm.loading { ProgressView().tint(.white) }
                        Text("执行选股")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(DSColor.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .disabled(vm.loading)

                candidatesCard
                Color.clear.frame(height: 80)
            }
            .padding(.top, 8)
        }
        .background(Color.dsGroupedBackground)
        .navigationTitle("选股 (AlphaSift)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.load(env: env) }
    }

    private var hotspotsCard: some View {
        ModuleCard("热点主题") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(vm.hotspots) { h in
                    hotspotCell(h)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func hotspotCell(_ h: Hotspot) -> some View {
        let up = h.changePct >= 0
        let color: Color = up ? .red : .green
        return VStack(alignment: .leading, spacing: 4) {
            Text(h.topic).font(.system(size: 13, weight: .semibold))
            sparkline(values: h.trend, color: color).frame(height: 22)
            Text("\(h.count) 只 · \((up ? "↑ +" : "↓ ") + String(format: "%.1f%%", abs(h.changePct)))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sparkline(values: [Double], color: Color) -> some View {
        GeometryReader { geo in
            if values.count >= 2 {
                let minV = values.min() ?? 0
                let maxV = values.max() ?? 1
                let span = max(maxV - minV, 0.1)
                let step = geo.size.width / CGFloat(values.count - 1)
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * step
                        let y = geo.size.height - CGFloat(v - minV) / CGFloat(span) * (geo.size.height - 4) - 2
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, lineWidth: 1.2)
            }
        }
    }

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
                    ForEach(vm.strategies) { Text($0.name).tag($0.key) }
                }.pickerStyle(.menu)
            }
            HStack {
                Text("最大结果").font(.subheadline)
                Spacer()
                Stepper("\(vm.maxResults)", value: $vm.maxResults, in: 5...50, step: 5)
                    .labelsHidden()
                Text("\(vm.maxResults)").monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
    }

    private var candidatesCard: some View {
        ModuleCard("候选股 · \(vm.candidates.count)") {
            VStack(spacing: 0) {
                ForEach(vm.candidates) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.stockName).font(.system(size: 15, weight: .medium))
                            Text("\(c.stockCode)\(c.theme.map { " · \($0)" } ?? "") · 评分 \(Int(c.score))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ChangeChip(percent: c.changePct, market: Market(stockCode: c.stockCode), scheme: env.colorScheme)
                    }
                    .padding(.vertical, 8)
                    if c.id != vm.candidates.last?.id { Divider() }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

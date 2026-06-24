import SwiftUI

// MARK: - RunFlow Sheet

struct RunFlowSheet: View {
    @EnvironmentObject var env: AppEnvironment
    let recordId: String
    @State private var flow: RunFlow?
    @State private var selected: String?
    @State private var subSegment = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("运行流 · RunFlow").font(.title3.bold())
                    if let f = flow {
                        Text("trace \(f.traceId ?? "—") · \(durationLabel(f.totalDurationMs)) · \(statusText(f.overallStatus))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            HStack(spacing: 6) {
                segChip("流程图", index: 0)
                segChip("节点列表", index: 1)
            }
            if subSegment == 0 {
                graphView.frame(height: 280)
            } else {
                listView
            }
            if let nodeId = selected, let node = flow?.nodes?.first(where: { $0.id == nodeId }) {
                ModuleCard("选中节点：\(node.label)") {
                    Text("状态：\(node.status) · \(durationLabel(node.durationMs))")
                        .font(.callout)
                    if let detail = node.detail {
                        Text(detail).font(.footnote).foregroundStyle(.secondary).padding(.top, 2)
                    }
                }
            }
            Spacer()
        }
        .padding(20)
        .presentationBackground(.regularMaterial)
        .task {
                flow = try? await env.auth.api.send(.get("/history/\(recordId)/flow"))
            
        }
    }

    private func segChip(_ title: String, index: Int) -> some View {
        let active = subSegment == index
        return Button { subSegment = index } label: {
            Text(title).font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(active ? DSColor.accent.opacity(0.16) : Color.gray.opacity(0.10), in: Capsule())
                .foregroundStyle(active ? DSColor.accent : .secondary)
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var graphView: some View {
        if let flow {
            FlowGraphCanvas(nodes: flow.nodes ?? [], edges: flow.edges ?? [], selected: $selected)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var listView: some View {
        if let flow {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(flow.nodes ?? []) { node in
                        Button { selected = node.id } label: {
                            HStack {
                                Circle().fill(nodeColor(node.status ?? "")).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(node.label ?? "").font(.system(size: 14, weight: .medium))
                                    if let detail = node.detail {
                                        Text(detail).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(durationLabel(node.durationMs)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8).padding(.horizontal, 12)
                            .background(selected == node.id ? DSColor.accent.opacity(0.08) : .clear)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func nodeColor(_ status: String) -> Color {
        switch status {
        case "success": return .green
        case "fallback": return .orange
        case "failed": return .red
        case "running": return DSColor.accent
        default: return .gray
        }
    }

    private func statusText(_ s: String?) -> String {
        switch s {
        case "normal": return "正常"
        case "degraded": return "降级"
        case "failed": return "失败"
        default: return s ?? "—"
        }
    }

    private func durationLabel(_ ms: Int?) -> String {
        guard let ms else { return "—" }
        if ms >= 1000 { return String(format: "%.1fs", Double(ms) / 1000) }
        return "\(ms)ms"
    }
}

/// 简易流程图：按 edges 推断层级，顺序排版。
struct FlowGraphCanvas: View {
    let nodes: [RunFlowNode]
    let edges: [RunFlowEdge]
    @Binding var selected: String?

    var body: some View {
        let levels = computeLevels()
        GeometryReader { geo in
            let columnCount = max(levels.values.max().map { $0 + 1 } ?? 1, 1)
            let columnWidth = geo.size.width / CGFloat(columnCount)
            let positions = computePositions(levels: levels, geo: geo, columnWidth: columnWidth)

            ZStack {
                // edges
                ForEach(edges, id: \.self) { edge in
                    if let from = positions[edge.from], let to = positions[edge.to] {
                        Path { p in
                            p.move(to: from)
                            p.addLine(to: to)
                        }
                        .stroke(Color.gray.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                // nodes
                ForEach(nodes) { node in
                    if let pos = positions[node.id] {
                        nodeView(node)
                            .position(pos)
                            .onTapGesture { selected = node.id }
                    }
                }
            }
        }
    }

    private func nodeView(_ node: RunFlowNode) -> some View {
        let color: Color = {
            switch node.status {
            case "success": return .green
            case "fallback": return .orange
            case "failed": return .red
            default: return .gray
            }
        }()
        return VStack(spacing: 1) {
            Text(node.label ?? "").font(.caption2.weight(.semibold))
            if let d = node.durationMs {
                Text(d >= 1000 ? String(format: "%.1fs", Double(d)/1000) : "\(d)ms")
                    .font(.system(size: 9)).foregroundStyle(color)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: selected == node.id ? 1.5 : 0.5))
    }

    private func computeLevels() -> [String: Int] {
        var levels: [String: Int] = [:]
        let incoming = Dictionary(grouping: edges, by: \.to).mapValues { $0.map(\.from) }
        // 按拓扑排序计算层级
        var queue = nodes.filter { incoming[$0.id] == nil }.map(\.id)
        queue.forEach { levels[$0] = 0 }
        var processed = Set(queue)
        var iterations = 0
        while !queue.isEmpty && iterations < 100 {
            iterations += 1
            let current = queue.removeFirst()
            for edge in edges where edge.from == current {
                let parents = incoming[edge.to] ?? []
                if parents.allSatisfy({ levels[$0] != nil }) {
                    let lv = (parents.compactMap { levels[$0] }.max() ?? 0) + 1
                    levels[edge.to] = lv
                    if !processed.contains(edge.to) {
                        queue.append(edge.to)
                        processed.insert(edge.to)
                    }
                }
            }
        }
        // 任何遗漏节点放到最后一层
        let maxLevel = levels.values.max() ?? 0
        for node in nodes where levels[node.id] == nil {
            levels[node.id] = maxLevel + 1
        }
        return levels
    }

    private func computePositions(levels: [String: Int], geo: GeometryProxy, columnWidth: CGFloat) -> [String: CGPoint] {
        let grouped = Dictionary(grouping: nodes) { levels[$0.id] ?? 0 }
        var positions: [String: CGPoint] = [:]
        for (level, nodesInLevel) in grouped {
            let count = nodesInLevel.count
            let spacing = geo.size.height / CGFloat(count + 1)
            for (i, node) in nodesInLevel.enumerated() {
                let x = columnWidth * (CGFloat(level) + 0.5)
                let y = spacing * CGFloat(i + 1)
                positions[node.id] = CGPoint(x: x, y: y)
            }
        }
        return positions
    }
}

// MARK: - Markdown Sheet

struct MarkdownReportSheet: View {
    @EnvironmentObject var env: AppEnvironment
    let recordId: String
    let stockName: String
    @State private var markdown: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("完整报告 · Markdown").font(.headline)
                    Text("\(stockName) · \(recordId)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    UIPasteboardCopy(markdown)
                } label: {
                    Image(systemName: "doc.on.doc").imageScale(.medium)
                        .frame(width: 32, height: 32).background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
            Divider()
            ScrollView {
                Text(LocalizedStringKey(markdown))
                    .font(.system(size: 15, design: .serif))
                    .lineSpacing(4)
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .presentationBackground(.regularMaterial)
        .task {
                struct Wrap: Decodable { let content: String? }
                if let w: Wrap = try? await env.auth.api.send(.get("/history/\(recordId)/markdown")) {
                    markdown = w.content ?? ""
                }
            
        }
    }
}

// 跨平台剪贴板
private func UIPasteboardCopy(_ text: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = text
    #endif
}

#if canImport(UIKit)
import UIKit
#endif

// MARK: - History Trend Sheet

struct HistoryTrendSheet: View {
    @EnvironmentObject var env: AppEnvironment
    let stockCode: String
    @State private var items: [HistoryItem] = []
    @State private var range: Int = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(items.first?.stockName ?? stockCode) · 历史趋势").font(.title3.bold())
                Text("最近 \(range) 天 · \(items.count) 份报告")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                rangeChip(7); rangeChip(30); rangeChip(90)
                Spacer()
            }
            sparkline
                .frame(height: 100)
            Text("时间线").font(.caption).foregroundStyle(.secondary).tracking(0.5).padding(.top, 4)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(item.createdAt) · \(item.currentPrice.map { "¥\(String(format: "%.0f", $0))" } ?? "—")")
                                    .font(.system(size: 14, weight: .medium))
                                Text(changeText(item))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DSColor.change(item.changePct ?? 0, market: item.market, scheme: env.colorScheme))
                            }
                            Spacer()
                            ActionChip(action: item.action, label: item.actionLabel)
                        }
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        if item.id != items.last?.id { Divider() }
                    }
                }
                .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .presentationBackground(.regularMaterial)
        .task { await load() }
    }

    private func rangeChip(_ days: Int) -> some View {
        let active = range == days
        return Button { range = days; Task { await load() } } label: {
            Text("\(days) 天").font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(active ? DSColor.accent.opacity(0.16) : Color.gray.opacity(0.1), in: Capsule())
                .foregroundStyle(active ? DSColor.accent : .secondary)
        }.buttonStyle(.plain)
    }

    private var sparkline: some View {
        let prices = items.compactMap(\.currentPrice).reversed().map { CGFloat($0) }
        return GeometryReader { geo in
            if prices.count >= 2 {
                let minP = prices.min() ?? 0
                let maxP = prices.max() ?? 1
                let span = max(maxP - minP, 1)
                let stepX = geo.size.width / CGFloat(prices.count - 1)
                Path { p in
                    for (i, value) in prices.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = geo.size.height - (value - minP) / span * (geo.size.height - 8) - 4
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(DSColor.accent, lineWidth: 1.5)
            } else {
                Text("数据不足").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func changeText(_ item: HistoryItem) -> String {
        if let pct = item.changePct {
            return (pct >= 0 ? "+" : "") + String(format: "%.2f%%", pct) + " · \(item.reportType ?? "report")"
        }
        return item.reportType ?? "report"
    }

    private func load() async {
        let resp: HistoryListResponse? = try? await env.auth.api.send(.get("/history",
            query: ["stock_code": stockCode, "limit": "50"]))
        items = resp?.items ?? []
    }
}

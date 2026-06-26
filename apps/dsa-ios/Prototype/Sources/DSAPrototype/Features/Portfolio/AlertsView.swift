import SwiftUI

@MainActor
final class AlertsViewModel: ObservableObject {
    @Published var rules: [AlertRule] = []
    @Published var triggers: [AlertTrigger] = []
    @Published var notifications: [AlertNotificationItem] = []
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var subSegment: Int = 0

    func load(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        struct RulesResp: Decodable { let items: [AlertRule]? }
        struct TriggersResp: Decodable { let items: [AlertTrigger]? }
        struct NotifResp: Decodable { let items: [AlertNotificationItem]? }
        async let r: RulesResp? = try? env.auth.api.send(.get("/alerts/rules"))
        async let t: TriggersResp? = try? env.auth.api.send(.get("/alerts/triggers", query: ["limit": "30"]))
        async let n: NotifResp? = try? env.auth.api.send(.get("/alerts/notifications", query: ["page_size": "30"]))
        self.rules = (await r)?.items ?? []
        self.triggers = (await t)?.items ?? []
        self.notifications = (await n)?.items ?? []
    }

    func toggle(env: AppEnvironment, rule: AlertRule) async {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx].enabled?.toggle()
        }
        let action = (rule.enabled == true) ? "disable" : "enable"
        try? await env.auth.api.sendVoid(.init(path: "/alerts/rules/\(rule.id)/\(action)", method: .POST))
    }

    @Published var showCreate = false
    @Published var testing: Int?
    @Published var testResults: [Int: String] = [:]
    @Published var newRule = AlertRuleDraft()

    struct AlertRuleDraft {
        var name = ""
        var target = ""               // 股票代码（single_symbol）
        var alertType = "price_cross" // price_cross / price_change_percent（均为 threshold + direction）
        var threshold = ""
        var direction = "above"       // above / below
        var severity = "warning"      // info / warning / critical
        var enabled = true
    }

    /// 新建规则：POST /alerts/rules（固定 single_symbol scope）。
    func createRule(env: AppEnvironment) async {
        struct Params: Encodable { let threshold: Double?; let direction: String }
        struct Body: Encodable {
            let name: String; let targetScope: String; let target: String
            let alertType: String; let parameters: Params; let severity: String; let enabled: Bool
        }
        do {
            let body = Body(name: newRule.name, targetScope: "single_symbol", target: newRule.target,
                            alertType: newRule.alertType,
                            parameters: Params(threshold: Double(newRule.threshold), direction: newRule.direction),
                            severity: newRule.severity, enabled: newRule.enabled)
            let _: AlertRule = try await env.auth.api.send(
                Endpoint(path: "/alerts/rules", method: .POST, body: try JSONEncoder.dsa.encode(body)))
            showCreate = false
            newRule = AlertRuleDraft()
            await load(env: env)
        } catch {
            errorMessage = "创建失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 删除规则：DELETE /alerts/rules/{id}。
    func deleteRule(env: AppEnvironment, id: Int) async {
        try? await env.auth.api.sendVoid(.init(path: "/alerts/rules/\(id)", method: .DELETE))
        rules.removeAll { $0.id == id }
    }

    /// 测试规则（dry-run）：POST /alerts/rules/{id}/test。
    func testRule(env: AppEnvironment, id: Int) async {
        testing = id
        struct Resp: Decodable { let status: String?; let triggered: Bool? }
        do {
            let resp: Resp = try await env.auth.api.send(.init(path: "/alerts/rules/\(id)/test", method: .POST))
            testResults[id] = ((resp.triggered ?? false) ? "✓ 已触发" : "未触发") + "（\(resp.status ?? "?")）"
        } catch {
            testResults[id] = "✗ \((error as? APIError)?.errorDescription ?? "")"
        }
        testing = nil
    }
}

struct AlertsView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = AlertsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                subSegment
                if vm.subSegment == 0 {
                    rulesCard
                } else if vm.subSegment == 1 {
                    triggersCard
                } else {
                    notificationsCard
                }
                Color.clear.frame(height: 100)
            }
            .padding(.top, 6)
        }
        .task { await vm.load(env: env) }
        .refreshable { await vm.load(env: env) }
        .sheet(isPresented: $vm.showCreate) { createSheet }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section("基础") {
                    TextField("规则名称", text: $vm.newRule.name)
                    TextField("股票代码", text: $vm.newRule.target)
                        .autocorrectionDisabled()
                    Picker("类型", selection: $vm.newRule.alertType) {
                        Text("价格穿越").tag("price_cross")
                        Text("涨跌幅").tag("price_change_percent")
                    }
                    Picker("方向", selection: $vm.newRule.direction) {
                        Text("上穿 / 高于").tag("above")
                        Text("下穿 / 低于").tag("below")
                    }
                    TextField("阈值", text: $vm.newRule.threshold)
                        .autocorrectionDisabled()
                }
                Section("其他") {
                    Picker("严重度", selection: $vm.newRule.severity) {
                        Text("信息").tag("info")
                        Text("警告").tag("warning")
                        Text("紧急").tag("critical")
                    }
                    Toggle("启用", isOn: $vm.newRule.enabled)
                }
                if let err = vm.errorMessage {
                    Section { Text(err).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("新建规则")
            .dsInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { vm.showCreate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task {
                            await vm.createRule(env: env)
                            if !vm.showCreate { vm.errorMessage = nil }
                        }
                    }
                    .disabled(vm.newRule.name.isEmpty || vm.newRule.target.isEmpty || vm.newRule.threshold.isEmpty)
                }
            }
        }
    }

    private var subSegment: some View {
        HStack(spacing: 6) {
            chip("规则 · \(vm.rules.count)", index: 0)
            chip("触发记录 · \(vm.triggers.count)", index: 1)
            chip("通知 · \(vm.notifications.count)", index: 2)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func chip(_ title: String, index: Int) -> some View {
        let active = vm.subSegment == index
        return Button { vm.subSegment = index } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(active ? DSColor.accent.opacity(0.16) : Color.gray.opacity(0.10),
                            in: Capsule())
                .foregroundStyle(active ? DSColor.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var rulesCard: some View {
        ModuleCard("规则", trailing: AnyView(
            Button {
                vm.newRule = AlertsViewModel.AlertRuleDraft()
                vm.errorMessage = nil
                vm.showCreate = true
            } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(DSColor.accent)
            }
            .buttonStyle(.plain)
        )) {
            if vm.rules.isEmpty {
                Text("暂无规则，点右上角 + 新建").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
            VStack(spacing: 0) {
                ForEach(vm.rules) { rule in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name ?? "").font(.system(size: 15, weight: .medium))
                                Text("\(typeLabel(rule.alertType ?? "")) · \(severityLabel(rule.severity ?? ""))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { rule.enabled ?? false },
                                set: { _ in Task { await vm.toggle(env: env, rule: rule) } }
                            ))
                            .labelsHidden()
                        }
                        let params = humanizeParameters(rule.parameters)
                        if !params.isEmpty {
                            Text(params).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                        }
                        if rule.cooldownActive == true {
                            Label("冷却中", systemImage: "snowflake")
                                .font(.caption2).foregroundStyle(.blue)
                        } else if let src = rule.source, !src.isEmpty {
                            Text("来源 \(src)").font(.caption2).foregroundStyle(.tertiary)
                        }
                        if vm.testing == rule.id {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("测试中…").font(.caption2).foregroundStyle(.secondary)
                            }
                        } else if let r = vm.testResults[rule.id] {
                            Text(r)
                                .font(.caption2)
                                .foregroundStyle(r.hasPrefix("✓") ? .green : .red)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            Task { await vm.testRule(env: env, id: rule.id) }
                        } label: {
                            Label("测试", systemImage: "play")
                        }
                        Button("删除", role: .destructive) {
                            Task { await vm.deleteRule(env: env, id: rule.id) }
                        }
                    }
                    if rule.id != vm.rules.last?.id { Divider() }
                }
            }
            }
        }
        .padding(.horizontal, 16)
    }

    private var triggersCard: some View {
        ModuleCard("最近触发") {
            if vm.triggers.isEmpty {
                Text("暂无触发记录").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
            VStack(spacing: 0) {
                ForEach(vm.triggers) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(t.target ?? "—").font(.system(size: 15, weight: .medium))
                            Spacer()
                            statusBadge("", status: t.status ?? "")
                        }
                        if let reason = t.reason, !reason.isEmpty {
                            Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        HStack(spacing: 10) {
                            if let obs = t.observedValue {
                                Text("观测 \(String(format: "%.2f", obs))").font(.caption2).foregroundStyle(.secondary)
                            }
                            if let thr = t.threshold {
                                Text("阈值 \(String(format: "%.2f", thr))").font(.caption2).foregroundStyle(.secondary)
                            }
                            if let src = t.dataSource, !src.isEmpty {
                                Text("· \(src)").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        Text(t.triggeredAt ?? "—").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    if t.id != vm.triggers.last?.id { Divider() }
                }
            }
            }
        }
        .padding(.horizontal, 16)
    }

    private var notificationsCard: some View {
        ModuleCard("通知记录") {
            if vm.notifications.isEmpty {
                Text("暂无通知记录").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
            VStack(spacing: 0) {
                ForEach(vm.notifications) { n in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(n.channel ?? "—").font(.system(size: 14, weight: .medium))
                            Spacer()
                            notifStatusBadge(n.success == true, n.errorCode ?? "")
                        }
                        HStack(spacing: 10) {
                            if let attempt = n.attempt {
                                Text("第 \(attempt) 次").font(.caption2).foregroundStyle(.tertiary)
                            }
                            if let latency = n.latencyMs {
                                Text("\(latency)ms").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                            if n.retryable == true {
                                Text("可重试").font(.caption2).foregroundStyle(.orange)
                            }
                            Spacer()
                        }
                        if let t = n.createdAt, !t.isEmpty {
                            Text(t).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 8)
                    if n.id != vm.notifications.last?.id { Divider() }
                }
            }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "price_cross": return "价格穿越"
        case "price_change_percent": return "涨跌幅"
        case "volume_spike": return "放量"
        case "ma_price_cross": return "均线穿越"
        case "rsi_threshold": return "RSI 阈值"
        case "macd_cross": return "MACD 交叉"
        case "kdj_cross": return "KDJ 交叉"
        case "cci_threshold": return "CCI 阈值"
        case "portfolio_stop_loss": return "组合止损"
        case "portfolio_concentration": return "组合集中度"
        case "portfolio_drawdown": return "组合回撤"
        case "portfolio_price_stale": return "估值过期"
        case "market_light_status": return "市场信号状态"
        case "market_light_score_drop": return "市场信号回落"
        default: return type
        }
    }

    private func severityLabel(_ s: String) -> String {
        switch s {
        case "critical": return "紧急"
        case "warning": return "警告"
        case "info": return "信息"
        default: return s
        }
    }

    private func humanizeParameters(_ params: JSONValue?) -> String {
        guard let obj = params?.objectValue, !obj.isEmpty else { return "" }
        return obj.map { "\($0.key)=\(jsonScalar($0.value))" }.sorted().joined(separator: " · ")
    }

    private func jsonScalar(_ v: JSONValue) -> String {
        switch v.storage {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "是" : "否"
        case .null: return "—"
        default: return "…"
        }
    }

    private func statusBadge(_ severity: String, status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "delivered": return (severity == "critical" ? "紧急" : "已触发", .orange)
            case "suppressed": return ("已抑制", .secondary)
            case "triggered": return ("已触发", .red)
            case "failed": return ("失败", .red)
            default: return (status, .secondary)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color == .secondary ? Color.secondary : color)
    }

    private func notifStatusBadge(_ success: Bool, _ errorCode: String) -> some View {
        let (label, color): (String, Color) = success
            ? ("成功", .green)
            : (errorCode.isEmpty ? "失败" : errorCode, .red)
        return Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }
}

import SwiftUI

@MainActor
final class AlertsViewModel: ObservableObject {
    @Published var rules: [AlertRule] = []
    @Published var triggers: [AlertTrigger] = []
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var subSegment: Int = 0

    func load(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        do {
            struct RulesResp: Decodable { let items: [AlertRule]? }; let rResp: RulesResp = try await env.auth.api.send(.get("/alerts/rules")); self.rules = rResp.items ?? []
            struct TriggersResp: Decodable { let items: [AlertTrigger]? }; let tResp: TriggersResp = try await env.auth.api.send(.get("/alerts/triggers", query: ["limit": "20"])); self.triggers = tResp.items ?? []
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func toggle(env: AppEnvironment, rule: AlertRule) async {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx].enabled?.toggle()
        }
        let action = (rule.enabled == true) ? "disable" : "enable"
        try? await env.auth.api.sendVoid(.init(path: "/alerts/rules/\(rule.id)/\(action)", method: .POST))
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
                } else {
                    triggersCard
                }
                if let err = vm.errorMessage {
                    Text(err).font(.footnote).foregroundStyle(.red).padding(.horizontal, 20)
                }
                Color.clear.frame(height: 100)
            }
            .padding(.top, 6)
        }
        .task { await vm.load(env: env) }
    }

    private var subSegment: some View {
        HStack(spacing: 6) {
            chip("规则 · \(vm.rules.count)", index: 0)
            chip("触发记录 · \(vm.triggers.count)", index: 1)
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
        ModuleCard("规则") {
            VStack(spacing: 0) {
                ForEach(vm.rules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name ?? "").font(.system(size: 15, weight: .medium))
                            Text("\(typeLabel(rule.alertType ?? "")) · \(severityLabel(rule.severity ?? "")) · \(rule.channels ?? 0) 渠道")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { rule.enabled ?? false },
                            set: { _ in Task { await vm.toggle(env: env, rule: rule) } }
                        ))
                        .labelsHidden()
                    }
                    .padding(.vertical, 8)
                    if rule.id != vm.rules.last?.id { Divider() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var triggersCard: some View {
        ModuleCard("最近触发") {
            VStack(spacing: 0) {
                ForEach(vm.triggers) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.ruleName ?? "").font(.system(size: 15, weight: .medium))
                            Text("\(t.triggeredAt ?? "—") · \(t.message ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        statusBadge(t.severity ?? "", status: t.status ?? "")
                    }
                    .padding(.vertical, 8)
                    if t.id != vm.triggers.last?.id { Divider() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "price_threshold": return "价格阈值"
        case "watchlist": return "关注列表"
        case "portfolio_holdings", "portfolio_account": return "投资组合"
        case "market": return "市场"
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

    private func statusBadge(_ severity: String, status: String) -> some View {
        let (label, color): (String, Color) = {
            switch (status, severity) {
            case ("delivered", "critical"): return ("紧急", .red)
            case ("delivered", "warning"): return ("警告", .orange)
            case ("delivered", _): return ("已推送", .green)
            case ("suppressed", _): return ("已抑制", .secondary)
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

import SwiftUI

// MARK: - LLM Channels

@MainActor
final class LLMChannelsViewModel: ObservableObject {
    @Published var channels: [LLMChannel] = []
    @Published var loading = false

    func load(env: AppEnvironment) async {
        // 真实接入：从 /system/config 读取 channels 字段
    }
}

public struct LLMChannelsView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = LLMChannelsViewModel()

    public init() {}

    public var body: some View {
        List {
            Section("通道列表 · \(vm.channels.count)") {
                ForEach(vm.channels) { ch in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ch.name ?? "").font(.system(size: 15, weight: .medium))
                            Text("\((ch.models ?? []).joined(separator: ", "))\((ch.models ?? []).isEmpty ? "（无模型）" : "")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        statusTag(ch.status ?? "unknown", primary: ch.isPrimary ?? false)
                    }
                }
            }
            Section("当前编辑：\(vm.channels.first?.name ?? "—")") {
                if let ch = vm.channels.first {
                    LabeledContent("通道名称", value: ch.name ?? "")
                    LabeledContent("协议", value: ch.provider ?? "")
                    LabeledContent("Base URL", value: ch.baseURL ?? "")
                    LabeledContent("API Key", value: ch.apiKeyMasked ?? "")
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
                        Text("自动发现模型"); Spacer(); Text("\((ch.models ?? []).count) 个 ›").foregroundStyle(.secondary).font(.subheadline)
                    }
                    HStack {
                        Image(systemName: "play.fill").foregroundStyle(.green)
                        Text("测试连接"); Spacer(); Text("JSON ✓ Tools ✓").foregroundStyle(.secondary).font(.subheadline)
                    }
                }
            }
            Section("运行时参数") {
                LabeledContent("主模型", value: "gpt-4o ›")
                LabeledContent("Agent 模型", value: "gpt-4o ›")
                LabeledContent("Vision 模型", value: "gpt-4o ›")
                LabeledContent("Temperature", value: "0.7")
            }
        }
        .dsListStyle()
        .scrollContentBackground(.hidden)
        .background(Color.dsGroupedBackground)
        .navigationTitle("LLM 通道")
        .dsInlineTitle()
        .task { await vm.load(env: env) }
    }

    private func statusTag(_ status: String, primary: Bool) -> some View {
        let (label, color): (String, Color) = {
            if primary { return ("主", .green) }
            switch status {
            case "online": return ("备", .blue)
            case "offline": return ("离线", .red)
            default: return (status, .secondary)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color == .secondary ? Color.secondary : color)
    }
}

// MARK: - Notification Channels

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var channels: [NotificationChannel] = []
    @Published var testTitle: String = "DSA 测试通知"
    @Published var testContent: String = "这是一条来自 iOS 的测试通知。"
    @Published var testResult: String?

    func load(env: AppEnvironment) async {
    }

    func sendTest(env: AppEnvironment, channel: NotificationChannel) async {
        // 真实接入：POST /system/config/notification/test-channel
    }
}

public struct NotificationChannelsView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = NotificationsViewModel()

    public init() {}

    public var body: some View {
        List {
            Section("已配置 · \(vm.channels.count)") {
                ForEach(vm.channels) { ch in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ch.name ?? "").font(.system(size: 15, weight: .medium))
                            Text(ch.target ?? ch.kind ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusTag(ch.status ?? "unknown")
                        Button("测试") { Task { await vm.sendTest(env: env, channel: ch) } }
                            .font(.caption.weight(.medium))
                    }
                }
            }
            Section("发送测试") {
                LabeledContent("标题") { TextField("", text: $vm.testTitle).multilineTextAlignment(.trailing) }
                LabeledContent("内容") { TextField("", text: $vm.testContent).multilineTextAlignment(.trailing) }
                if let result = vm.testResult {
                    LabeledContent("结果", value: result)
                }
            }
            Section("支持渠道（14）") {
                Text("Telegram · 飞书 · 企业微信 · 邮件 · Pushover · ntfy · Gotify · PushPlus · ServerChan3 · Discord · Slack · 钉钉 · AstrBot · Webhook")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .dsListStyle()
        .scrollContentBackground(.hidden)
        .background(Color.dsGroupedBackground)
        .navigationTitle("通知通道")
        .dsInlineTitle()
        .task { await vm.load(env: env) }
    }

    private func statusTag(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "online": return ("在线", .green)
            case "untested": return ("未测试", .orange)
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
}

// MARK: - Scheduler

@MainActor
final class SchedulerViewModel: ObservableObject {
    @Published var status: SchedulerStatus?
    @Published var running = false

    func load(env: AppEnvironment) async {
        // 真实接入：GET /system/scheduler/status
    }

    func runNow(env: AppEnvironment) async {
        running = true; defer { running = false }
        try? await env.auth.api.sendVoid(.init(path: "/system/scheduler/run-now", method: .POST))
    }
}

public struct SchedulerView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = SchedulerViewModel()

    public init() {}

    public var body: some View {
        List {
            if let s = vm.status {
                Section("运行状态") {
                    Toggle("启用调度器", isOn: .constant(s.enabled ?? false))
                    LabeledContent("下次执行", value: s.nextRun ?? "—")
                    LabeledContent("上次执行", value: s.lastRun ?? "—")
                }
                Section("定时任务 · \(((s.times ?? []).count))") {
                    ForEach(s.times ?? []) { t in
                        HStack {
                            Text(t.time ?? "").font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit().frame(width: 60, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.scope ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: .constant(t.enabled ?? false)).labelsHidden()
                        }
                    }
                }
                Section {
                    Button {
                        Task { await vm.runNow(env: env) }
                    } label: {
                        HStack {
                            if vm.running { ProgressView() }
                            Text("立即运行一次")
                        }
                    }
                }
            }
        }
        .dsListStyle()
        .scrollContentBackground(.hidden)
        .background(Color.dsGroupedBackground)
        .navigationTitle("定时调度")
        .dsInlineTitle()
        .task { await vm.load(env: env) }
    }
}

// MARK: - Auth + Env Backup

@MainActor
final class AuthBackupViewModel: ObservableObject {
    @Published var authEnabled = true
    @Published var currentPwd = ""
    @Published var newPwd = ""
    @Published var confirmPwd = ""
    @Published var preview: EnvBackupPreview?

    func load(env: AppEnvironment) async {
        authEnabled = env.auth.status.authEnabled ?? false
    }
}

public struct AuthBackupView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = AuthBackupViewModel()

    public init() {}

    public var body: some View {
        List {
            Section("认证") {
                Toggle("启用密码认证", isOn: $vm.authEnabled)
                LabeledContent("会话有效期", value: "24 小时 ›")
                LabeledContent("登录失败限速", value: "5 次 / 5 分钟")
            }
            Section("修改密码") {
                SecureField("当前密码", text: $vm.currentPwd)
                SecureField("新密码（≥ 6 位）", text: $vm.newPwd)
                SecureField("确认新密码", text: $vm.confirmPwd)
                Button("提交修改") {}
                    .disabled(vm.currentPwd.isEmpty || vm.newPwd.isEmpty || vm.newPwd != vm.confirmPwd)
            }
            Section("配置备份 (.env)") {
                Button { } label: { Label("导出 .env", systemImage: "arrow.down.circle") }
                Button { } label: { Label("导入 .env", systemImage: "arrow.up.circle") }
                Button { } label: { Label("校验配置", systemImage: "checkmark.seal") }
            }
            if let p = vm.preview {
                Section("导入预览（dry-run）") {
                    HStack {
                        Text("新增").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("(p.added?.count ?? 0)").bold()
                        Text("修改").font(.caption).foregroundStyle(.secondary).padding(.leading, 12)
                        Text("(p.modified?.count ?? 0)").bold()
                        Text("删除").font(.caption).foregroundStyle(.secondary).padding(.leading, 12)
                        Text("\(p.removed?.count ?? 0)").bold()
                    }
                    ForEach(p.added ?? [], id: \.self) { Text("+ \($0)").font(.caption.monospaced()).foregroundStyle(.green) }
                    ForEach(p.modified ?? [], id: \.self) { item in Text("± \(item)").font(.caption.monospaced()).foregroundStyle(.orange) }
                    ForEach(p.removed ?? [], id: \.self) { item in Text("− \(item)").font(.caption.monospaced()).foregroundStyle(.red) }
                }
            }
        }
        .dsListStyle()
        .scrollContentBackground(.hidden)
        .background(Color.dsGroupedBackground)
        .navigationTitle("认证 · 配置备份")
        .dsInlineTitle()
        .task { await vm.load(env: env) }
    }
}

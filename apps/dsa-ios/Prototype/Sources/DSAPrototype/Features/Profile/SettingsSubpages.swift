import SwiftUI

// MARK: - LLM Channels

@MainActor
final class LLMChannelsViewModel: ObservableObject {
    @Published var channels: [LLMChannel] = []
    @Published var loading = false
    @Published var error: String?
    @Published var enteredKeys: [String: String] = [:]      // 每通道测试/发现用临时输入的 key
    @Published var testing: String?
    @Published var testResults: [String: String] = [:]
    @Published var discovering: String?
    @Published var discovered: [String: [String]] = [:]

    func load(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        do {
            let resp: SystemConfigResponse = try await env.auth.api.send(
                .get("/system/config", query: ["include_schema": "true"]))
            self.channels = Self.parseChannels(resp.items ?? [])
            self.error = nil
        } catch {
            self.channels = []
            self.error = "加载失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 从扁平 config 条目解析 LLM_CHANNELS 花名册 + 每通道 LLM_{NAME}_* 字段。
    static func parseChannels(_ items: [SystemConfigItem]) -> [LLMChannel] {
        let roster = items.first { $0.key.uppercased() == "LLM_CHANNELS" }?.value ?? ""
        let names = roster.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        func val(_ name: String, _ suffix: String) -> String? {
            let key = "LLM_\(name.uppercased())_\(suffix)"
            return items.first { $0.key.uppercased() == key }?.value
        }
        return names.map { name in
            let models = (val(name, "MODELS") ?? "")
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let enabled = (val(name, "ENABLED") ?? "").lowercased()
            return LLMChannel(id: name, name: name, provider: val(name, "PROTOCOL"),
                              baseURL: val(name, "BASE_URL"),
                              apiKeyMasked: val(name, "API_KEY") ?? val(name, "API_KEYS"),
                              models: models, isPrimary: nil,
                              status: enabled == "false" ? "offline" : "online")
        }
    }

    func channel(_ name: String) -> LLMChannel? { channels.first { $0.id == name } }

    /// 测试连接：后端用提交的 api_key 直接调用（不解析掩码），故需重新输入。
    func testChannel(env: AppEnvironment, name: String) async {
        guard let ch = channel(name) else { return }
        testing = name
        struct Body: Encodable {
            let name: String; let proto: String; let baseUrl: String; let apiKey: String
            let models: [String]; let enabled: Bool; let timeoutSeconds: Double; let capabilityChecks: [String]
            enum CodingKeys: String, CodingKey {
                case name; case proto = "protocol"; case baseUrl = "base_url"; case apiKey = "api_key"
                case models; case enabled; case timeoutSeconds = "timeout_seconds"; case capabilityChecks = "capability_checks"
            }
        }
        do {
            let body = Body(name: name, proto: ch.provider ?? "openai", baseUrl: ch.baseURL ?? "",
                            apiKey: enteredKeys[name] ?? "", models: ch.models ?? [], enabled: true,
                            timeoutSeconds: 20, capabilityChecks: ["json", "tools", "vision", "stream"])
            let resp: SystemConfigLLMTestResponse = try await env.auth.api.send(
                Endpoint(path: "/system/config/llm/test-channel", method: .POST, body: try JSONEncoder.dsa.encode(body)))
            let caps = resp.capabilityResults ?? [:]
            let capSummary = ["json", "tools", "vision", "stream"].compactMap { k -> String? in
                guard let r = caps[k] else { return nil }
                let mark = r.status == "passed" ? "✓" : (r.status == "failed" ? "✗" : "–")
                return "\(k) \(mark)"
            }.joined(separator: " ")
            let ok = resp.success ?? false
            testResults[name] = (ok ? "✓ " : "✗ ") + (resp.message ?? "")
                + (capSummary.isEmpty ? "" : "\n\(capSummary)")
        } catch {
            testResults[name] = "✗ \((error as? APIError)?.errorDescription ?? "")"
        }
        testing = nil
    }

    /// 发现模型：同样需重新输入 api_key。
    func discoverModels(env: AppEnvironment, name: String) async {
        guard let ch = channel(name) else { return }
        discovering = name
        struct Body: Encodable {
            let name: String; let proto: String; let baseUrl: String; let apiKey: String
            let models: [String]; let timeoutSeconds: Double
            enum CodingKeys: String, CodingKey {
                case name; case proto = "protocol"; case baseUrl = "base_url"; case apiKey = "api_key"
                case models; case timeoutSeconds = "timeout_seconds"
            }
        }
        do {
            let body = Body(name: name, proto: ch.provider ?? "openai", baseUrl: ch.baseURL ?? "",
                            apiKey: enteredKeys[name] ?? "", models: ch.models ?? [], timeoutSeconds: 20)
            let resp: SystemConfigLLMDiscoverResponse = try await env.auth.api.send(
                Endpoint(path: "/system/config/llm/discover-models", method: .POST, body: try JSONEncoder.dsa.encode(body)))
            discovered[name] = resp.models ?? []
            if !(resp.success ?? false) {
                testResults[name] = "✗ 发现失败：\(resp.error ?? resp.message ?? "")"
            }
        } catch {
            testResults[name] = "✗ \((error as? APIError)?.errorDescription ?? "")"
        }
        discovering = nil
    }
}

public struct LLMChannelsView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = LLMChannelsViewModel()

    public init() {}

    public var body: some View {
        List {
            if vm.loading && vm.channels.isEmpty {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            }
            if let err = vm.error {
                Section { Text(err).font(.caption).foregroundStyle(.red) }
            }
            if vm.channels.isEmpty && !vm.loading {
                Section { Text("尚未配置 LLM 通道").font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(vm.channels) { ch in
                Section {
                    channelDetail(ch)
                } header: {
                    HStack {
                        Text(ch.name ?? ch.id).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        statusTag(ch.status ?? "unknown", primary: ch.isPrimary ?? false)
                    }
                }
            }
        }
        .dsListStyle()
        .scrollContentBackground(.hidden)
        .background(Color.dsGroupedBackground)
        .navigationTitle("LLM 通道")
        .dsInlineTitle()
        .refreshable { await vm.load(env: env) }
        .task { await vm.load(env: env) }
    }

    @ViewBuilder
    private func channelDetail(_ ch: LLMChannel) -> some View {
        LabeledContent("协议", value: ch.provider ?? "—")
        LabeledContent("Base URL", value: ch.baseURL ?? "—")
        LabeledContent("模型", value: (ch.models ?? []).isEmpty ? "—" : (ch.models ?? []).joined(separator: ", "))
            .font(.caption)
        SecureField("API Key（测试/发现需重新输入）", text: keyBinding(ch.id))
            .font(.caption)
        HStack {
            Button { Task { await vm.testChannel(env: env, name: ch.id) } } label: {
                HStack { if vm.testing == ch.id { ProgressView() }; Text("测试连接") }
            }.disabled(vm.testing == ch.id)
            Spacer()
            Button { Task { await vm.discoverModels(env: env, name: ch.id) } } label: {
                HStack { if vm.discovering == ch.id { ProgressView() }; Text("发现模型") }
            }.disabled(vm.discovering == ch.id)
        }
        .font(.caption.weight(.medium))
        if let r = vm.testResults[ch.id] {
            Text(r).font(.caption2)
                .foregroundStyle(r.hasPrefix("✓") ? .green : .red)
        }
        if let found = vm.discovered[ch.id], !found.isEmpty {
            Text("发现 \(found.count) 个：\n" + found.joined(separator: ", "))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func keyBinding(_ name: String) -> Binding<String> {
        Binding(get: { vm.enteredKeys[name] ?? "" }, set: { vm.enteredKeys[name] = $0 })
    }

    private func statusTag(_ status: String, primary: Bool) -> some View {
        let (label, color): (String, Color) = {
            if primary { return ("主", .green) }
            switch status {
            case "online": return ("在线", .blue)
            case "offline": return ("禁用", .red)
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
    /// 通知渠道在后端不是独立列表接口，而是 /system/config 里的扁平 key/value 条目，
    /// 按 schema.category == "notification" 分类。这里只读展示 + 按渠道测试发送。
    @Published var items: [SystemConfigItem] = []
    @Published var maskToken: String = "******"
    @Published var loading = false
    @Published var loadFailed = false
    @Published var testing: String?                        // 正在测试的 provider channel
    @Published var testResults: [String: String] = [:]     // channel -> 结果文案
    @Published var testTitle = "DSA 通知测试"
    @Published var testContent = "这是一条来自 iOS 的测试通知。"

    /// 渠道注册表：channel(后端枚举) / 配置 key 前缀 / 中文名。
    static let providers: [(channel: String, prefix: String, label: String)] = [
        ("telegram", "TELEGRAM_", "Telegram"),
        ("wechat", "WECHAT_", "企业微信"),
        ("feishu", "FEISHU_", "飞书"),
        ("email", "EMAIL_", "邮件"),
        ("pushplus", "PUSHPLUS_", "PushPlus"),
        ("pushover", "PUSHOVER_", "Pushover"),
        ("ntfy", "NTFY_", "ntfy"),
        ("gotify", "GOTIFY_", "Gotify"),
        ("serverchan3", "SERVERCHAN3_", "ServerChan3"),
        ("discord", "DISCORD_", "Discord"),
        ("slack", "SLACK_", "Slack"),
        ("astrbot", "ASTRBOT_", "AstrBot"),
        ("custom", "CUSTOM_", "Webhook"),
    ]

    /// 已配置（存在该渠道 key）的渠道列表，顺序沿用 providers 注册表（即优先级）。
    var configuredProviders: [(channel: String, label: String)] {
        Self.providers
            .filter { p in items.contains { $0.key.uppercased().hasPrefix(p.prefix) } }
            .map { (channel: $0.channel, label: $0.label) }
    }

    /// 尚未配置的渠道（置灰展示，提示用户需先在后端填写）。
    var unconfiguredProviders: [(channel: String, label: String)] {
        let configured = Set(configuredProviders.map { $0.channel })
        return Self.providers
            .filter { !configured.contains($0.channel) }
            .map { (channel: $0.channel, label: $0.label) }
    }

    func load(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        do {
            let resp: SystemConfigResponse = try await env.auth.api.send(
                .get("/system/config", query: ["include_schema": "true"]))
            self.items = (resp.items ?? []).filter { Self.isNotification($0) }
            self.maskToken = resp.maskToken ?? "******"
            self.loadFailed = false
        } catch {
            self.items = []
            self.loadFailed = true
        }
    }

    /// 通知类配置：优先用 schema.category，缺失时回退到 NOTIFICATION_ / 各渠道前缀。
    static func isNotification(_ item: SystemConfigItem) -> Bool {
        if let cat = item.schema?.category?.lowercased(), cat == "notification" { return true }
        let k = item.key.uppercased()
        if k.hasPrefix("NOTIFICATION_") { return true }
        return providers.contains { k.hasPrefix($0.prefix) }
    }

    /// 测试某渠道：POST /system/config/notification/test-channel
    /// （敏感值回传掩码，后端用存储的真实值投递；channel 不在已配置则需先在后端配置）。
    func sendTest(env: AppEnvironment, channel: String) async {
        guard let prefix = Self.providers.first(where: { $0.channel == channel })?.prefix else { return }
        testing = channel
        struct Item: Encodable { let key: String; let value: String }
        struct Body: Encodable {
            let channel: String
            let items: [Item]
            let maskToken: String
            let title: String
            let content: String
        }
        do {
            let channelItems = items
                .filter { $0.key.uppercased().hasPrefix(prefix) }
                .map { Item(key: $0.key, value: $0.value ?? "") }
            let body = Body(channel: channel, items: channelItems, maskToken: maskToken,
                            title: testTitle, content: testContent)
            let resp: SystemConfigNotificationTestResponse = try await env.auth.api.send(
                Endpoint(path: "/system/config/notification/test-channel", method: .POST,
                         body: try JSONEncoder.dsa.encode(body)))
            let ok = resp.success ?? false
            testResults[channel] = (ok ? "✓ " : "✗ ") + (resp.message ?? (ok ? "成功" : "失败"))
        } catch {
            testResults[channel] = "✗ 测试失败：\((error as? APIError)?.errorDescription ?? "")"
        }
        testing = nil
    }
}

public struct NotificationChannelsView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = NotificationsViewModel()

    public init() {}

    public var body: some View {
        List {
            // 已配置渠道（置顶，可直接测试）；顺序即渠道优先级
            Section {
                if vm.loading && vm.items.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if vm.configuredProviders.isEmpty {
                    Text(vm.loadFailed ? "加载失败，下拉重试" : "尚未配置任何通知渠道，配置后可在此测试发送")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(vm.configuredProviders, id: \.channel) { p in
                        testRow(channel: p.channel, label: p.label)
                    }
                }
            } header: {
                Text("已配置渠道 · \(vm.configuredProviders.count)")
            } footer: {
                Text("点「测试」向该渠道发一条通知；敏感值由服务端用存储的真实值投递。")
                    .font(.caption2)
            }

            // 未配置渠道（置灰，仅展示可用）
            if !vm.unconfiguredProviders.isEmpty {
                Section {
                    ForEach(vm.unconfiguredProviders, id: \.channel) { p in
                        HStack {
                            Text(p.label).foregroundStyle(.secondary)
                            Spacer()
                            Text("未配置").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("其他支持渠道 · \(vm.unconfiguredProviders.count)")
                } footer: {
                    Text("这些渠道尚未在后端配置，需先填写对应密钥/地址。").font(.caption2)
                }
            }

            // 原始配置项（默认折叠，减少噪音，需要时展开核对）
            if !vm.items.isEmpty {
                Section {
                    DisclosureGroup("原始配置项 · \(vm.items.count)") {
                        ForEach(vm.items) { item in configRow(item) }
                    }
                }
            }
        }
        .dsListStyle()
        .scrollContentBackground(.hidden)
        .background(Color.dsGroupedBackground)
        .navigationTitle("通知通道")
        .dsInlineTitle()
        .refreshable { await vm.load(env: env) }
        .task { await vm.load(env: env) }
    }

    @ViewBuilder
    private func testRow(channel: String, label: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 14, weight: .medium))
                if let r = vm.testResults[channel] {
                    Text(r).font(.caption2)
                        .foregroundStyle(r.hasPrefix("✓") ? .green : .red)
                        .lineLimit(3)
                }
            }
            Spacer()
            if vm.testing == channel {
                ProgressView()
            } else {
                Button("测试") { Task { await vm.sendTest(env: env, channel: channel) } }
                    .font(.caption.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private func configRow(_ item: SystemConfigItem) -> some View {
        let sensitive = item.schema?.isSensitive == true || item.isMasked == true
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(item.schema?.title ?? humanKey(item.key))
                    .font(.system(size: 14, weight: .medium))
                if sensitive { sensitiveBadge }
                Spacer()
            }
            Text(displayValue(item, sensitive: sensitive))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
            Text(item.key).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
        }
    }

    private var sensitiveBadge: some View {
        Text("敏感").font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.orange)
    }

    private func displayValue(_ item: SystemConfigItem, sensitive: Bool) -> String {
        if sensitive { return item.isMasked == true ? "******（已掩码）" : "（已配置，值隐藏）" }
        if let v = item.value, !v.isEmpty { return v }
        return "未设置"
    }

    /// NOTIFICATION_TELEGRAM_BOT_TOKEN -> "Telegram Bot Token"
    private func humanKey(_ key: String) -> String {
        key.replacingOccurrences(of: "NOTIFICATION_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// MARK: - Scheduler

@MainActor
final class SchedulerViewModel: ObservableObject {
    @Published var status: SchedulerStatus?
    @Published var running = false
    @Published var error: String?

    func load(env: AppEnvironment) async {
        do {
            self.status = try await env.auth.api.send(.get("/system/scheduler/status"))
        } catch {
            self.status = nil
        }
    }

    /// 开关调度器：写 SCHEDULE_ENABLED（后端 PUT 含此 key 时自动 reconcile runtime scheduler）。
    func setEnabled(env: AppEnvironment, value: Bool) async {
        let prev = status?.enabled ?? false
        if var s = status { s.enabled = value; status = s }   // 乐观更新
        do {
            _ = try await ConfigWriter.update(
                api: env.auth.api,
                items: [(key: "SCHEDULE_ENABLED", value: value ? "true" : "false")])
            await load(env: env)
            error = nil
        } catch {
            if var s = status { s.enabled = prev; status = s }   // 失败回滚
            self.error = "切换失败：\((error as? APIError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    func runNow(env: AppEnvironment) async {
        running = true; defer { running = false }
        try? await env.auth.api.sendVoid(.init(path: "/system/scheduler/run-now", method: .POST))
        await load(env: env)
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
                    Toggle("启用调度器", isOn: Binding(
                        get: { s.enabled ?? false },
                        set: { newValue in Task { await vm.setEnabled(env: env, value: newValue) } }
                    ))
                    if s.running == true {
                        LabeledContent("当前", value: "运行中")
                    }
                    LabeledContent("下次执行", value: formatTime(s.nextRunAt))
                    LabeledContent("上次执行", value: formatTime(s.lastRunAt))
                    if let success = s.lastSuccessAt, !success.isEmpty {
                        LabeledContent("上次成功", value: formatTime(success))
                    }
                    if let skipped = s.lastSkippedAt, !skipped.isEmpty {
                        LabeledContent("上次跳过", value: formatTime(skipped))
                        if let reason = s.lastSkipReason, !reason.isEmpty {
                            LabeledContent("跳过原因", value: reason)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let err = s.lastError, !err.isEmpty {
                        LabeledContent("上次错误", value: err)
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                Section("定时任务 · \((s.scheduleTimes ?? []).count)") {
                    let times = s.scheduleTimes ?? []
                    if times.isEmpty {
                        Text("未配置定时").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(times, id: \.self) { t in
                            HStack {
                                Text(t).font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                                Spacer()
                                Image(systemName: (s.enabled ?? false) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle((s.enabled ?? false) ? .green : .secondary)
                            }
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
                    .disabled(vm.running || !(s.enabled ?? false))
                }
            } else {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                Section {
                    Text("无法加载调度器状态，下拉重试")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .dsListStyle()
        .scrollContentBackground(.hidden)
        .background(Color.dsGroupedBackground)
        .navigationTitle("定时调度")
        .dsInlineTitle()
        .refreshable { await vm.load(env: env) }
        .task { await vm.load(env: env) }
        .alert("调度器", isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("好的", role: .cancel) {}
        } message: { Text(vm.error ?? "") }
    }

    private func formatTime(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        return String(raw.prefix(19)).replacingOccurrences(of: "T", with: " ")
    }
}

// MARK: - Auth + Env Backup

@MainActor
final class AuthBackupViewModel: ObservableObject {
    @Published var authEnabled = true
    @Published var currentPwd = ""
    @Published var newPwd = ""
    @Published var confirmPwd = ""
    @Published var saving = false
    @Published var error: String?
    @Published var info: String?
    @Published var importing = false
    @Published var importText = ""
    @Published var exportedURL: URL?

    func load(env: AppEnvironment) async {
        authEnabled = env.auth.status.authEnabled ?? false
    }

    /// 导出 .env：GET /system/config/export → 写临时文件供分享。
    func exportEnv(env: AppEnvironment) async {
        do {
            let resp: SystemConfigExportResponse = try await env.auth.api.send(.get("/system/config/export"))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dsa-config.env")
            try (resp.content ?? "").data(using: .utf8)?.write(to: url)
            exportedURL = url
            error = nil
        } catch {
            self.error = "导出失败（可能需管理员会话）：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 导入 .env：POST /system/config/import（带最新 config_version；导入会合并并 reload）。
    func importEnv(env: AppEnvironment) async {
        let content = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        importing = true; defer { importing = false }
        struct Body: Encodable { let configVersion: String; let content: String; let reloadNow: Bool }
        do {
            let cfg: SystemConfigResponse = try await env.auth.api.send(
                .get("/system/config", query: ["include_schema": "false"]))
            let body = Body(configVersion: cfg.configVersion ?? "", content: content, reloadNow: true)
            let resp: SystemConfigUpdateResponse = try await env.auth.api.send(
                Endpoint(path: "/system/config/import", method: .POST, body: try JSONEncoder.dsa.encode(body)))
            importText = ""
            let w = resp.warnings ?? []
            info = "已导入：应用 \(resp.appliedCount ?? 0) 项" + (w.isEmpty ? "" : "；警告 \(w.count) 条")
        } catch {
            self.error = "导入失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 开关认证（已登录会话无需 currentPassword）。走 POST /auth/settings（ADMIN_AUTH_ENABLED 不可经 config PUT）。
    func setAuthEnabled(env: AppEnvironment, value: Bool) async {
        struct Body: Encodable { let authEnabled: Bool }
        let prev = authEnabled
        authEnabled = value   // 乐观
        do {
            try await env.auth.api.sendVoid(
                Endpoint(path: "/auth/settings", method: .POST,
                         body: try JSONEncoder.dsa.encode(Body(authEnabled: value))))
            await env.auth.refreshStatus()
            error = nil
        } catch {
            authEnabled = prev   // 回滚
            self.error = "切换认证失败：\((error as? APIError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    /// 修改密码：POST /auth/change-password。
    func changePassword(env: AppEnvironment) async {
        guard !newPwd.isEmpty, newPwd == confirmPwd else { return }
        saving = true; defer { saving = false }
        struct Body: Encodable {
            let currentPassword: String
            let newPassword: String
            let newPasswordConfirm: String
        }
        do {
            let body = Body(currentPassword: currentPwd, newPassword: newPwd, newPasswordConfirm: confirmPwd)
            try await env.auth.api.sendVoid(
                Endpoint(path: "/auth/change-password", method: .POST, body: try JSONEncoder.dsa.encode(body)))
            currentPwd = ""; newPwd = ""; confirmPwd = ""
            error = nil; info = "密码已修改"
        } catch {
            self.error = "修改失败：\((error as? APIError)?.errorDescription ?? error.localizedDescription)"
        }
    }
}

public struct AuthBackupView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = AuthBackupViewModel()

    public init() {}

    public var body: some View {
        List {
            Section("认证") {
                Toggle("启用密码认证", isOn: Binding(
                    get: { vm.authEnabled },
                    set: { v in Task { await vm.setAuthEnabled(env: env, value: v) } }
                ))
                LabeledContent("会话有效期", value: "24 小时 ›")
                LabeledContent("登录失败限速", value: "5 次 / 5 分钟")
            }
            Section("修改密码") {
                SecureField("当前密码", text: $vm.currentPwd)
                SecureField("新密码（≥ 6 位）", text: $vm.newPwd)
                SecureField("确认新密码", text: $vm.confirmPwd)
                Button {
                    Task { await vm.changePassword(env: env) }
                } label: {
                    HStack { if vm.saving { ProgressView() }; Text("提交修改") }
                }
                .disabled(vm.currentPwd.isEmpty || vm.newPwd.isEmpty || vm.newPwd != vm.confirmPwd || vm.saving)
            }
            Section {
                Button { Task { await vm.exportEnv(env: env) } } label: {
                    Label("导出 .env", systemImage: "arrow.down.circle")
                }
                if let url = vm.exportedURL {
                    ShareLink(item: url) { Label("分享 .env 文件", systemImage: "square.and.arrow.up") }
                }
            } header: {
                Text("配置备份 (.env)")
            } footer: {
                Text("导出/导入需管理员会话或桌面模式；导入会直接合并并 reload。")
                    .font(.caption2)
            }
            Section("导入 .env") {
                TextEditor(text: $vm.importText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if vm.importText.isEmpty {
                            Text("粘贴 .env 内容…").font(.caption).foregroundStyle(.tertiary).padding(8).allowsHitTesting(false)
                        }
                    }
                Button {
                    Task { await vm.importEnv(env: env) }
                } label: {
                    HStack { if vm.importing { ProgressView() }; Text("导入并应用") }
                }
                .disabled(vm.importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.importing)
            }
        }
        .dsListStyle()
        .scrollContentBackground(.hidden)
        .background(Color.dsGroupedBackground)
        .navigationTitle("认证 · 配置备份")
        .dsInlineTitle()
        .task { await vm.load(env: env) }
        .alert("出错", isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })) {
            Button("好的", role: .cancel) {}
        } message: { Text(vm.error ?? "") }
        .alert("完成", isPresented: Binding(get: { vm.info != nil }, set: { if !$0 { vm.info = nil } })) {
            Button("好的", role: .cancel) {}
        } message: { Text(vm.info ?? "") }
    }
}

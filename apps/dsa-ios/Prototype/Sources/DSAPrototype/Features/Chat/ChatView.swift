import SwiftUI
import MarkdownUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var sessions: [ChatSessionInfo] = []
    @Published var currentSessionId: String?
    @Published var skills: [AgentSkill] = []
    @Published var selectedSkills: Set<String> = []
    @Published var draft: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?

    private var streamTask: Task<Void, Never>?

    func load(env: AppEnvironment) async {
        do {
            struct SkillsResp: Decodable { let skills: [AgentSkill]? }
            let resp: SkillsResp = try await env.auth.api.send(.get("/agent/skills"))
            self.skills = resp.skills ?? []
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
        }
        await loadSessions(env: env)
    }

    func loadSessions(env: AppEnvironment) async {
        do {
            struct SessionsResp: Decodable { let sessions: [ChatSessionInfo]? }
            let resp: SessionsResp = try await env.auth.api.send(.get("/agent/chat/sessions"))
            self.sessions = resp.sessions ?? []
        } catch {}
    }

    func switchSession(env: AppEnvironment, sessionId: String) async {
        currentSessionId = sessionId
        messages = []
        do {
            struct MsgsResp: Decodable {
                let sessionId: String?
                let messages: [[String: JSONValue]]?
            }
            let resp: MsgsResp = try await env.auth.api.send(.get("/agent/chat/sessions/\(sessionId)"))
            if let rawMsgs = resp.messages {
                self.messages = rawMsgs.compactMap { dict -> ChatMessage? in
                    let role = dict["role"]?.stringValue ?? "assistant"
                    let content = dict["content"]?.stringValue ?? ""
                    guard let chatRole = ChatRole(rawValue: role) else { return nil }
                    return ChatMessage(role: chatRole, text: content)
                }
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    func startNewSession() {
        currentSessionId = nil
        messages = []
    }

    func deleteSession(env: AppEnvironment, sessionId: String) async {
        try? await env.auth.api.sendVoid(.init(path: "/agent/chat/sessions/\(sessionId)", method: .DELETE))
        sessions.removeAll { $0.id == sessionId }
        if currentSessionId == sessionId {
            startNewSession()
        }
    }

    func send(env: AppEnvironment) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        messages.append(ChatMessage(role: .user, text: text))
        draft = ""
        realStream(env: env, prompt: text)
    }

    func cancel() {
        streamTask?.cancel(); streamTask = nil
        isStreaming = false
        if var last = messages.last, last.role == .assistant {
            last.isStreaming = false
            messages[messages.count - 1] = last
        }
    }

    // MARK: - SSE (URLSessionDataTask + delegate for real-time streaming through Cloudflare)

    private func realStream(env: AppEnvironment, prompt: String) {
        guard let url = URL(string: env.auth.baseURLString + "/api/v1/agent/chat/stream") else { return }
        isStreaming = true
        messages.append(ChatMessage(role: .assistant, text: "", isStreaming: true))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("DSA-iOS/0.1", forHTTPHeaderField: "User-Agent")
        struct Body: Encodable {
            let message: String
            let skills: [String]
            let sessionId: String?
        }
        // 注意：曾尝试在命中股票代码时注入 context={stock_code} 供 agent 复用数据，
        // 但实测会导致后端 agent 抛 "cannot parse response"（与 context 传参相关），
        // 故回退为不传 context，保持对话可用。会话导出仍保留。
        request.httpBody = try? JSONEncoder.dsa.encode(
            Body(message: prompt, skills: Array(selectedSkills), sessionId: currentSessionId))

        let sseDelegate = SSEDataDelegate { [weak self] eventPayload in
            Task { @MainActor in
                self?.handleEvent(event: "message", payload: eventPayload)
            }
        } onComplete: { [weak self] in
            Task { @MainActor in
                self?.finishStreaming()
                await self?.loadSessions(env: env)
            }
        } onError: { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = error
                self?.finishStreaming()
            }
        }

        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        let session = URLSession(configuration: config, delegate: sseDelegate, delegateQueue: nil)
        sseDelegate.trustAll = true
        let task = session.dataTask(with: request)
        task.resume()
        streamTask = Task { while !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000_000) } }
    }

    private func handleEvent(event: String, payload: String) {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            if !payload.isEmpty { appendText(payload) }
            return
        }

        switch type {
        case "thinking":
            let msg = json["message"] as? String ?? "思考中…"
            appendThinking(msg)
        case "tool_start":
            let name = json["display_name"] as? String ?? json["tool"] as? String ?? "调用工具"
            appendThinking("🔧 \(name)…")
        case "tool_done":
            let name = json["display_name"] as? String ?? json["tool"] as? String ?? ""
            let duration = json["duration"] as? Double
            let success = json["success"] as? Bool ?? true
            let suffix = duration.map { String(format: " %.1fs", $0) } ?? ""
            let icon = success ? "✓" : "✗"
            guard !messages.isEmpty else { return }
            var last = messages[messages.count - 1]
            last.tools.append("\(icon) \(name)\(suffix)")
            last.toolCount += 1
            if let d = duration { last.toolDurationTotal += d }
            messages[messages.count - 1] = last
        case "generating":
            let msg = json["message"] as? String ?? "正在生成回复…"
            appendThinking(msg)
        case "done":
            if let content = json["content"] as? String, !content.isEmpty {
                guard !messages.isEmpty else { return }
                var last = messages[messages.count - 1]
                last.text = content
                last.isStreaming = false
                messages[messages.count - 1] = last
            }
            if let sid = json["session_id"] as? String {
                currentSessionId = sid
            }
            isStreaming = false
        case "error":
            let msg = json["message"] as? String ?? payload
            errorMessage = msg
            finishStreaming()
        default:
            break
        }
    }

    private func appendThinking(_ line: String) {
        guard !messages.isEmpty else { return }
        var last = messages[messages.count - 1]
        last.thinking.append(line)
        messages[messages.count - 1] = last
    }

    private func appendText(_ chunk: String) {
        guard !messages.isEmpty else { return }
        var last = messages[messages.count - 1]
        last.text += chunk
        messages[messages.count - 1] = last
    }

    private func finishStreaming() {
        guard !messages.isEmpty else { return }
        var last = messages[messages.count - 1]
        last.isStreaming = false
        messages[messages.count - 1] = last
        isStreaming = false
    }

    /// 把当前会话消息拼成 Markdown（用于导出/分享）。
    var exportMarkdown: String {
        guard !messages.isEmpty else { return "_（暂无消息）_" }
        return messages.enumerated().map { idx, msg -> String in
            let role = msg.role == .user ? "🧑 用户" : "🤖 助手"
            return "### \(role)\n\n\(msg.text)"
        }.joined(separator: "\n\n---\n\n")
    }
}

// MARK: - ChatView

public struct ChatView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = ChatViewModel()
    @State private var showSessions = false
    @State private var expandedThinking: Set<UUID> = []

    private let quickQuestions: [String] = [
        "今天大盘怎么看？",
        "帮我看一下贵州茅台",
        "最近有什么热门板块？",
        "美股和港股有什么机会？",
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部导航（实底）
            HStack {
                Button { showSessions = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DSColor.accent)
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("历史会话")
                Spacer()
                CapsuleTitle(vm.currentSessionId == nil ? "新对话" : "AI 对话")
                Spacer()
                ShareLink(item: vm.exportMarkdown) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DSColor.accent)
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: Circle())
                }
                .disabled(vm.messages.isEmpty)
                .accessibilityLabel("导出会话")
                Button { vm.startNewSession() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DSColor.accent)
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("新建对话")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.dsGroupedBackground)

            // 中间消息区（占满剩余空间）
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if vm.messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(vm.messages) { msg in
                                bubble(msg).id(msg.id)
                            }
                        }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            // 底部控件区（实底背景）
            VStack(spacing: 6) {
                skillsRow
                inputBar
            }
            .padding(.top, 8)
            .padding(.bottom, 80) // Tab Bar 空间
            .background(Color.dsGroupedBackground)
        }
        .background(Color.dsGroupedBackground.ignoresSafeArea())
        .task { await vm.load(env: env) }
        .sheet(isPresented: $showSessions) {
            SessionListSheet(vm: vm, env: env, isPresented: $showSessions)
                .presentationDetents([.medium, .large])
                .presentationBackground(.regularMaterial)
        }
        .alert("出错", isPresented: .constant(vm.errorMessage != nil)) {
            Button("好的") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
    }

    // MARK: - Bubble

    @ViewBuilder
    private func bubble(_ msg: ChatMessage) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(msg.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(DSColor.accent, in:
                        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 4, topTrailing: 18)))
                    .foregroundStyle(.white)
                    .font(.callout)
                    .padding(.trailing, 16)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                if msg.toolCount > 0 || !msg.thinking.isEmpty {
                    thinkingBlock(msg)
                }
                if !msg.text.isEmpty {
                    MarkdownCards(text: msg.text)
                        .contextMenu {
                            Button { copyText(msg.text) } label: { Label("复制回复", systemImage: "doc.on.doc") }
                        }
                }
            }
            .padding(.leading, 16).padding(.trailing, 40)
        case .system:
            EmptyView()
        }
    }

    private var thinkingDot: some View {
        Circle().stroke(DSColor.accent, lineWidth: 1.5)
            .frame(width: 10, height: 10)
            .overlay(Circle().trim(from: 0, to: 0.3).stroke(DSColor.accent, lineWidth: 1.5))
    }

    @ViewBuilder
    private func thinkingBlock(_ msg: ChatMessage) -> some View {
        let expanded = expandedThinking.contains(msg.id) || msg.isStreaming
        VStack(alignment: .leading, spacing: 4) {
            Button { if !msg.isStreaming { toggleThinking(msg.id) } } label: {
                HStack(spacing: 6) {
                    if msg.isStreaming { thinkingDot }
                    else { Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2) }
                    if msg.isStreaming {
                        Text(msg.thinking.last ?? "思考中…")
                    } else if msg.toolCount > 0 {
                        Text("\(msg.toolCount) 个工具" + (msg.toolDurationTotal > 0
                              ? " · \(String(format: "%.1fs", msg.toolDurationTotal))" : ""))
                    } else {
                        Text("思考过程")
                    }
                    Spacer()
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(Array(msg.thinking.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption2).foregroundStyle(.secondary)
                        .padding(.leading, 22).padding(.trailing, 8)
                }
                if !msg.tools.isEmpty {
                    Text(msg.tools.joined(separator: "\n"))
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.leading, 22).padding(.trailing, 8)
                }
            }
        }
    }

    private func toggleThinking(_ id: UUID) {
        if expandedThinking.contains(id) { expandedThinking.remove(id) }
        else { expandedThinking.insert(id) }
    }

    private func copyText(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("开始与 AI 对话").font(.headline)
            Text("试试这些问题").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(quickQuestions, id: \.self) { q in
                    Button { vm.draft = q } label: {
                        Text(q).font(.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Skills

    private var skillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(vm.skills) { s in
                    Button {
                        if vm.selectedSkills.contains(s.key ?? "") { vm.selectedSkills.remove(s.key ?? "") }
                        else if vm.selectedSkills.count < 3 { vm.selectedSkills.insert(s.key ?? "") }
                    } label: {
                        let active = vm.selectedSkills.contains(s.key ?? "")
                        Text("\(s.icon ?? "") \(s.name)")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(active ? DSColor.accent.opacity(0.16) : Color.white.opacity(0.7),
                                        in: Capsule())
                            .overlay(Capsule().stroke(Color.gray.opacity(0.18), lineWidth: 0.5))
                            .foregroundStyle(active ? DSColor.accent : Color.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("追问…", text: $vm.draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.leading, 16)
            Button {
                if vm.isStreaming { vm.cancel() } else { vm.send(env: env) }
            } label: {
                Image(systemName: vm.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(vm.draft.isEmpty && !vm.isStreaming
                                ? Color.gray.opacity(0.3) : DSColor.accent,
                                in: Circle())
                    .foregroundStyle(.white)
            }
            .disabled(vm.draft.isEmpty && !vm.isStreaming)
            .accessibilityLabel(vm.isStreaming ? "停止生成" : "发送")
            .padding(.trailing, 6)
        }
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.gray.opacity(0.18), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Session List Sheet

private struct SessionListSheet: View {
    @ObservedObject var vm: ChatViewModel
    let env: AppEnvironment
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        vm.startNewSession()
                        isPresented = false
                    } label: {
                        Label("新建对话", systemImage: "plus.circle.fill")
                            .foregroundStyle(DSColor.accent)
                    }
                }
                Section("历史会话 · \(vm.sessions.count)") {
                    ForEach(vm.sessions) { session in
                        Button {
                            Task {
                                await vm.switchSession(env: env, sessionId: session.id)
                                isPresented = false
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title ?? "未命名")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        Text("\(session.messageCount ?? 0) 条消息")
                                        if let time = session.updatedAt {
                                            Text(time.prefix(10))
                                        }
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if vm.currentSessionId == session.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(DSColor.accent)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await vm.deleteSession(env: env, sessionId: session.id) }
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("会话")
            .dsInlineTitle()
            .dsListStyle()
        }
    }
}

// MARK: - SSE Data Delegate (chunk-by-chunk for real-time streaming)

final class SSEDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var trustAll = false
    private let onEvent: (String) -> Void
    private let onComplete: () -> Void
    private let onError: (String) -> Void
    private var buffer = ""

    init(onEvent: @escaping (String) -> Void, onComplete: @escaping () -> Void, onError: @escaping (String) -> Void) {
        self.onEvent = onEvent
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk
        while let range = buffer.range(of: "\n\n") {
            let eventBlock = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            processBlock(eventBlock)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            processBlock(buffer)
            buffer = ""
        }
        if let error {
            onError(error.localizedDescription)
        } else {
            onComplete()
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if trustAll, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private func processBlock(_ block: String) {
        var data = ""
        for line in block.components(separatedBy: "\n") {
            if line.hasPrefix("data:") {
                let part = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                data = data.isEmpty ? part : data + "\n" + part
            }
        }
        if !data.isEmpty {
            onEvent(data)
        }
    }
}

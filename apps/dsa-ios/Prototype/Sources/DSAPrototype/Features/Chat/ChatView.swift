import SwiftUI
import MarkdownUI

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
                let messages: [[String: AnyCodable]]?
            }
            let resp: MsgsResp = try await env.auth.api.send(.get("/agent/chat/sessions/\(sessionId)"))
            if let rawMsgs = resp.messages {
                self.messages = rawMsgs.compactMap { dict -> ChatMessage? in
                    let role = (dict["role"]?.value as? String) ?? "assistant"
                    let content = (dict["content"]?.value as? String) ?? ""
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
}

// MARK: - ChatView

public struct ChatView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = ChatViewModel()
    @State private var showSessions = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        Color.clear.frame(height: 90).id("top")
                        ForEach(vm.messages) { msg in
                            bubble(msg).id(msg.id)
                        }
                        Color.clear.frame(height: 180).id("bottom")
                    }
                    .padding(.bottom, 6)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            // 顶部浮空栏
            VStack {
                HStack {
                    Button { showSessions = true } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DSColor.accent)
                            .frame(width: 36, height: 36)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
                    }
                    Spacer()
                    CapsuleTitle(vm.currentSessionId == nil ? "新对话" : "AI 对话")
                    Spacer()
                    Button { vm.startNewSession() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DSColor.accent)
                            .frame(width: 36, height: 36)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 8)
                Spacer()
            }

            // 底部技能 + 输入
            VStack {
                Spacer()
                skillsRow.padding(.bottom, 6)
                inputBar.padding(.bottom, 100)
            }
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
                ForEach(Array(msg.thinking.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 6) {
                        if msg.isStreaming { thinkingDot }
                        Text(line)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                if !msg.tools.isEmpty {
                    Text("📊 \(msg.tools.joined(separator: " · "))")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                if !msg.text.isEmpty {
                    Markdown(msg.text)
                        .markdownTextStyle {
                            FontSize(14)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.dsSecondaryGrouped, in:
                            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 4, bottomTrailing: 18, topTrailing: 18)))
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

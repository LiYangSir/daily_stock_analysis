import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
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
    }

    func send(env: AppEnvironment) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        let userMessage = ChatMessage(role: .user, text: text)
        messages.append(userMessage)
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

    // MARK: - Mock

    private func mockStream() {
        isStreaming = true
        let placeholder = ChatMessage(role: .assistant, text: "", thinking: ["分析问题…"], tools: [], isStreaming: true)
        messages.append(placeholder)
        let chunks = ["从 K 线看，", "MACD 仍在零轴上方运行，", "短期偏震荡但中期未破坏多头结构。",
                      " 建议参考报告中给出的 1,580 入场 / 1,520 止损区间，", "破位严格止损。"]
        streamTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                self?.appendThinking("拉取最新行情与新闻 …")
                self?.appendThinking("调用工具：search_news, get_quote")
            }
            for chunk in chunks {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
                await MainActor.run { self?.appendText(chunk) }
            }
            await MainActor.run { self?.finishStreaming() }
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

    // MARK: - Real SSE

    private func realStream(env: AppEnvironment, prompt: String) {
        guard let url = URL(string: env.auth.baseURLString + "/api/v1/agent/chat/stream") else { return }
        isStreaming = true
        messages.append(ChatMessage(role: .assistant, text: "", isStreaming: true))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        struct Body: Encodable {
            let message: String
            let skills: [String]
        }
        request.httpBody = try? JSONEncoder.dsa.encode(Body(message: prompt, skills: Array(selectedSkills)))

        streamTask = Task { [weak self] in
            do {
                let (bytes, _) = try await TrustAllSession.shared.bytes(for: request)
                var event = "message"
                var data = ""
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    if line.isEmpty {
                        await MainActor.run { self?.handleEvent(event: event, payload: data) }
                        event = "message"; data = ""
                    } else if line.hasPrefix("event:") {
                        event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("data:") {
                        let part = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        data = data.isEmpty ? part : data + "\n" + part
                    }
                }
                await MainActor.run { self?.finishStreaming() }
            } catch {
                await MainActor.run {
                    self?.errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                    self?.finishStreaming()
                }
            }
        }
    }

    private func handleEvent(event: String, payload: String) {
        switch event {
        case "thinking":
            appendThinking(payload)
        case "tool_start", "tool_done":
            guard !messages.isEmpty else { return }
            var last = messages[messages.count - 1]
            last.tools.append(payload)
            messages[messages.count - 1] = last
        case "generating", "message":
            appendText(payload)
        case "done":
            finishStreaming()
        case "error":
            errorMessage = payload
            finishStreaming()
        default:
            break
        }
    }
}

public struct ChatView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = ChatViewModel()

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
            VStack {
                HStack {
                    FloatingBackButton {}.opacity(0.001)
                    Spacer()
                    CapsuleTitle("AI 对话")
                    Spacer()
                    FloatingBackButton {}.opacity(0.001)
                }
                .padding(.horizontal, 14).padding(.top, 8)
                Spacer()
            }
            VStack {
                Spacer()
                skillsRow.padding(.bottom, 6)
                inputBar.padding(.bottom, 100)
            }
        }
        .background(Color.dsGroupedBackground.ignoresSafeArea())
        .task { await vm.load(env: env) }
        .alert("出错", isPresented: .constant(vm.errorMessage != nil)) {
            Button("好的") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
    }

    @ViewBuilder
    private func bubble(_ msg: ChatMessage) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(msg.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(DSColor.accent, in:
                        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 4, topTrailing: 18))
                    )
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
                    Text(msg.text)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color.dsSecondaryGrouped, in:
                            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 4, bottomTrailing: 18, topTrailing: 18))
                        )
                        .font(.callout)
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

import Foundation
import Combine

/// 全局任务状态管理：SSE 主路径 + Mock 模拟。
@MainActor
public final class TaskStreamStore: ObservableObject {
    @Published public private(set) var tasks: [TaskInfo] = []
    @Published public private(set) var isConnected: Bool = false
    /// 最近一个「刚完成」的任务（pending/processing → completed/failed 的瞬间），
    /// 供 UI 弹出「报告已生成 → 查看」提示；UI 展示后用 clearLastCompleted() 清掉。
    @Published public private(set) var lastCompleted: TaskInfo?

    private var session: URLSession?
    private var mockTicker: Task<Void, Never>?

    public init() {}

    public func start(env: AppEnvironment) {
        stop()
        startSSE(env: env)
    }

    public func stop() {
        session?.invalidateAndCancel(); session = nil
        mockTicker?.cancel(); mockTicker = nil
        isConnected = false
    }

    public func upsert(_ task: TaskInfo) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            let prev = tasks[idx]
            tasks[idx] = task
            // 新完成（进行中 → 终态）触发提示
            if Self.isFinished(task.status), !Self.isFinished(prev.status) {
                lastCompleted = task
            }
        } else {
            tasks.insert(task, at: 0)
            if Self.isFinished(task.status) { lastCompleted = task }
        }
        pruneFinished(keep: 20)
    }

    public var activeTasks: [TaskInfo] {
        tasks.filter { ["pending", "processing"].contains($0.status ?? "") }
    }

    /// 最近完成/失败的任务（供「最近完成」区展示并点开报告），按最新在前、最多 5 条。
    public var finishedTasks: [TaskInfo] {
        Array(tasks.filter { Self.isFinished($0.status) }.prefix(5))
    }

    public func clearLastCompleted() { lastCompleted = nil }

    private static func isFinished(_ status: String?) -> Bool {
        ["completed", "failed"].contains(status ?? "")
    }

    /// 控制已完成任务在内存里无限增长，仅保留最近 keep 条（连同活跃任务）。
    private func pruneFinished(keep: Int) {
        let finished = tasks.filter { Self.isFinished($0.status) }
        guard finished.count > keep else { return }
        let dropIds = Set(finished.dropFirst(keep).map { $0.id })
        tasks.removeAll { dropIds.contains($0.id) }
    }

    // MARK: - SSE

    private func startSSE(env: AppEnvironment) {
        let base = env.auth.baseURLString
        guard let url = URL(string: base + "/api/v1/analysis/tasks/stream") else { return }
        isConnected = true
        // 关键：必须用 delegate 方式读 SSE。`URLSession.bytes(for:)` 经 Cloudflare 会被缓冲到
        // 连接关闭才返回，而 SSE 永不关闭 → 永远收不到事件（聊天流也是因此改用 delegate）。
        let delegate = TaskStreamDelegate(
            onEvent: { [weak self] event, data in
                Task { @MainActor in await self?.handle(event: SSEEvent(event: event, data: data)) }
            },
            onError: { [weak self] _ in
                Task { @MainActor in self?.isConnected = false }
            })
        delegate.trustAll = true
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("DSA-iOS/0.1", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request).resume()
    }

    private func handle(event: SSEEvent) async {
        guard let data = event.data.data(using: .utf8) else { return }
        switch event.event {
        case "task_created", "task_started", "task_progress", "task_completed", "task_failed":
            if let info = try? JSONDecoder.dsa.decode(TaskInfo.self, from: data) {
                upsert(info)
            }
        default:
            break
        }
    }

    // MARK: - Mock ticker

    private func startMockTicker() {
        mockTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let self else { return }
                await MainActor.run {
                    self.tasks = self.tasks.map { t in
                        guard t.status == "processing", let p = t.progress, p < 100 else {
                            if t.status == "pending" {
                                return TaskInfo(taskId: t.taskId, stockCode: t.stockCode, stockName: t.stockName,
                                                status: "processing", progress: 8, message: "拉取实时行情",
                                                createdAt: t.createdAt, analysisPhase: t.analysisPhase)
                            }
                            return t
                        }
                        let next = min(100, p + Double.random(in: 4...12))
                        let msg: String
                        switch next {
                        case ..<30: msg = "拉取实时行情"
                        case ..<55: msg = "抓取技术指标"
                        case ..<75: msg = "检索资讯"
                        case ..<95: msg = "调用大模型"
                        default: msg = "生成报告"
                        }
                        let status = next >= 100 ? "completed" : "processing"
                        return TaskInfo(taskId: t.taskId, stockCode: t.stockCode, stockName: t.stockName,
                                        status: status, progress: next, message: msg,
                                        createdAt: t.createdAt, analysisPhase: t.analysisPhase)
                    }
                }
            }
        }
    }
}

// MARK: - 任务流 SSE 委托（delegate 方式，过 Cloudflare 可实时收块）

final class TaskStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var trustAll = false
    private let onEvent: (String, String) -> Void
    private let onError: (String) -> Void
    private var buffer = ""

    init(onEvent: @escaping (String, String) -> Void, onError: @escaping (String) -> Void) {
        self.onEvent = onEvent
        self.onError = onError
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk
        while let range = buffer.range(of: "\n\n") {
            let block = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            processBlock(block)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            processBlock(buffer)
            buffer = ""
        }
        if let error { onError(error.localizedDescription) }
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
        var event = "message"
        var data = ""
        for line in block.components(separatedBy: "\n") {
            if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let part = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                data = data.isEmpty ? part : data + "\n" + part
            }
        }
        if !data.isEmpty { onEvent(event, data) }
    }
}

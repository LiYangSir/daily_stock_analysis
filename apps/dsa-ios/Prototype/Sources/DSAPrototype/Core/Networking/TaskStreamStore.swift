import Foundation
import Combine

/// 全局任务状态管理：SSE 主路径 + Mock 模拟。
@MainActor
public final class TaskStreamStore: ObservableObject {
    @Published public private(set) var tasks: [TaskInfo] = []
    @Published public private(set) var isConnected: Bool = false

    private var streamTask: Task<Void, Never>?
    private var mockTicker: Task<Void, Never>?

    public init() {}

    public func start(env: AppEnvironment) {
        stop()
            startSSE(env: env)
        
    }

    public func stop() {
        streamTask?.cancel(); streamTask = nil
        mockTicker?.cancel(); mockTicker = nil
        isConnected = false
    }

    public func upsert(_ task: TaskInfo) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = task
        } else {
            tasks.insert(task, at: 0)
        }
    }

    public var activeTasks: [TaskInfo] {
        tasks.filter { ["pending", "processing"].contains($0.status ?? "") }
    }

    // MARK: - SSE

    private func startSSE(env: AppEnvironment) {
        let base = env.auth.baseURLString
        guard let url = URL(string: base + "/api/v1/analysis/tasks/stream") else { return }
        let client = SSEClient()
        isConnected = true
        streamTask = Task { [weak self] in
            do {
                for try await event in client.stream(url: url) {
                    guard let self else { return }
                    await self.handle(event: event)
                }
            } catch {
                // 网络错误：把状态置为断开，UI 可决定退化为 Mock 或重连
                await MainActor.run { [weak self] in self?.isConnected = false }
            }
        }
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

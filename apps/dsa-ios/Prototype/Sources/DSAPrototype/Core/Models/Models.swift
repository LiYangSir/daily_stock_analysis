import Foundation

// MARK: - Stock

public struct StockQuote: Codable, Sendable, Identifiable {
    public var id: String { stockCode }
    public let stockCode: String
    public let stockName: String?
    public let currentPrice: Double
    public let change: Double?
    public let changePercent: Double?
    public let open: Double?
    public let high: Double?
    public let low: Double?
    public let prevClose: Double?
    public let volume: Double?
    public let amount: Double?
    public let updateTime: String?

    public var market: Market { Market(stockCode: stockCode) }
}

public struct KLineData: Codable, Sendable, Identifiable {
    public var id: String { date }
    public let date: String
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double?
    public let amount: Double?
    public let changePercent: Double?
}

public struct StockHistoryResponse: Codable, Sendable {
    public let stockCode: String?
    public let period: String?
    public let data: [KLineData]?
}

// MARK: - Watchlist

public struct WatchlistResponse: Codable, Sendable {
    public let stockCodes: [String]?
    public let message: String?
}

// MARK: - History list

public struct HistoryListResponse: Codable, Sendable {
    public let total: Int?
    public let page: Int?
    public let limit: Int?
    public let items: [HistoryItem]?
}

public struct HistoryItem: Codable, Sendable, Identifiable {
    public var id: String { "\(dbId ?? 0)-\(queryId ?? stockCode)" }
    public let dbId: Int?
    public let queryId: String?
    public let stockCode: String
    public let stockName: String?
    public let reportType: String?
    public let trendPrediction: String?
    public let analysisSummary: String?
    public let sentimentScore: Double?
    public let operationAdvice: String?
    public let action: DecisionAction?
    public let actionLabel: String?
    public let currentPrice: Double?
    public let changePct: Double?
    public let volumeRatio: Double?
    public let turnoverRate: Double?
    public let modelUsed: String?
    public let createdAt: String?

    public var market: Market { Market(stockCode: stockCode) }

    enum CodingKeys: String, CodingKey {
        case dbId = "id"
        case queryId, stockCode, stockName, reportType, trendPrediction
        case analysisSummary, sentimentScore, operationAdvice
        case action, actionLabel, currentPrice, changePct
        case volumeRatio, turnoverRate, modelUsed, createdAt
    }
}

// MARK: - Analysis Report (detail)

public struct ReportMeta: Codable, Sendable {
    public let id: String?
    public let queryId: String?
    public let stockCode: String?
    public let stockName: String?
    public let reportType: String?
    public let reportLanguage: String?
    public let createdAt: String?
    public let currentPrice: Double?
    public let changePct: Double?
    public let modelUsed: String?
}

public struct ReportSummary: Codable, Sendable {
    public let analysisSummary: String?
    public let operationAdvice: String?
    public let action: DecisionAction?
    public let actionLabel: String?
    public let trendPrediction: String?
    public let sentimentScore: Double?
    public let sentimentLabel: String?
}

public struct ReportStrategy: Codable, Sendable {
    public let idealBuy: String?
    public let secondaryBuy: String?
    public let stopLoss: String?
    public let takeProfit: String?
}

public struct AnalysisReport: Codable, Sendable {
    public let meta: ReportMeta?
    public let summary: ReportSummary?
    public let strategy: ReportStrategy?
}

// MARK: - Task

public struct TaskInfo: Codable, Sendable, Identifiable {
    public var id: String { taskId ?? UUID().uuidString }
    public let taskId: String?
    public let stockCode: String?
    public let stockName: String?
    public let status: String?
    public let progress: Double?
    public let message: String?
    public let createdAt: String?
    public let analysisPhase: String?

    public init(taskId: String?, stockCode: String?, stockName: String?,
                status: String?, progress: Double?, message: String?,
                createdAt: String?, analysisPhase: String?) {
        self.taskId = taskId; self.stockCode = stockCode; self.stockName = stockName
        self.status = status; self.progress = progress; self.message = message
        self.createdAt = createdAt; self.analysisPhase = analysisPhase
    }
}

// MARK: - Auth

public struct AuthStatus: Codable, Sendable {
    public let authEnabled: Bool?
    public let loggedIn: Bool?
    public let passwordSet: Bool?
    public let setupState: String?
}

// MARK: - Agent

public struct AgentSkill: Codable, Sendable, Identifiable {
    public var id: String { key ?? name }
    public let key: String?
    public let name: String
    public let description: String?
    public let icon: String?

    enum CodingKeys: String, CodingKey {
        case key = "id"
        case name, description, icon
    }
}

public struct ChatSessionInfo: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String?
    public let messageCount: Int?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "sessionId"
        case title, messageCount
        case updatedAt = "lastActive"
    }
}

public enum ChatRole: String, Codable, Sendable {
    case user, assistant, system
}

public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public var role: ChatRole
    public var text: String
    public var thinking: [String]
    public var tools: [String]
    public var isStreaming: Bool

    public init(id: UUID = UUID(), role: ChatRole, text: String,
                thinking: [String] = [], tools: [String] = [], isStreaming: Bool = false) {
        self.id = id; self.role = role; self.text = text
        self.thinking = thinking; self.tools = tools; self.isStreaming = isStreaming
    }
}

// MARK: - Portfolio

public struct PortfolioAccount: Codable, Sendable, Identifiable {
    public var id: String { "\(accountId ?? 0)" }
    public let accountId: Int?
    public let name: String?
    public let broker: String?
    public let market: String?
    public let baseCurrency: String?
    public let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case accountId = "id"
        case name, broker, market, baseCurrency, isActive
    }
}

public struct PortfolioPositionItem: Codable, Sendable, Identifiable {
    public var id: String { symbol }
    public let symbol: String
    public let market: String?
    public let currency: String?
    public let quantity: Double?
    public let avgCost: Double?
    public let totalCost: Double?
    public let lastPrice: Double?
    public let marketValueBase: Double?
    public let unrealizedPnlBase: Double?
    public let unrealizedPnlPct: Double?
    public let priceSource: String?
    public let priceStale: Bool?
    public let priceAvailable: Bool?

    public var marketEnum: Market { Market(stockCode: symbol) }
}

public struct PortfolioAccountSnapshot: Codable, Sendable, Identifiable {
    public var id: String { "\(accountId ?? 0)" }
    public let accountId: Int?
    public let accountName: String?
    public let market: String?
    public let baseCurrency: String?
    public let totalCash: Double?
    public let totalMarketValue: Double?
    public let totalEquity: Double?
    public let realizedPnl: Double?
    public let unrealizedPnl: Double?
    public let fxStale: Bool?
    public let positions: [PortfolioPositionItem]?

    enum CodingKeys: String, CodingKey {
        case accountId = "accountId"
        case accountName, market, baseCurrency, totalCash, totalMarketValue
        case totalEquity, realizedPnl, unrealizedPnl, fxStale, positions
    }
}

public struct PortfolioSnapshotResponse: Codable, Sendable {
    public let asOf: String?
    public let costMethod: String?
    public let currency: String?
    public let accountCount: Int?
    public let totalCash: Double?
    public let totalMarketValue: Double?
    public let totalEquity: Double?
    public let realizedPnl: Double?
    public let unrealizedPnl: Double?
    public let feeTotal: Double?
    public let taxTotal: Double?
    public let fxStale: Bool?
    public let accounts: [PortfolioAccountSnapshot]?
}

public struct PortfolioRiskResponse: Codable, Sendable {
    public let asOf: String?
    public let accountId: Int?
    public let costMethod: String?
    public let currency: String?
    public let thresholds: [String: AnyCodable]?
    public let concentration: [String: AnyCodable]?
    public let drawdown: [String: AnyCodable]?
    public let stopLoss: [String: AnyCodable]?
}

// Helper for arbitrary JSON values
public struct AnyCodable: Codable, Sendable {
    public let value: Any?
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { value = nil }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode(Bool.self) { value = v }
        else { value = nil }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = value as? Double { try container.encode(v) }
        else if let v = value as? String { try container.encode(v) }
        else if let v = value as? Bool { try container.encode(v) }
        else { try container.encodeNil() }
    }
}

// MARK: - Decision Signal

public struct DecisionSignal: Codable, Sendable, Identifiable {
    public let id: String
    public let stockCode: String
    public let stockName: String?
    public let action: DecisionAction?
    public let actionLabel: String?
    public let confidence: Double?
    public let entry: Double?
    public let stopLoss: Double?
    public let target: Double?
    public let phase: String?
    public let status: String?
    public let createdAt: String?
    public let sourceReportId: String?

    public var market: Market { Market(stockCode: stockCode) }
}

public struct DecisionSignalStats: Codable, Sendable {
    public let total: Int?
    public let hit: Int?
    public let miss: Int?
    public let hitRate: Double?
}

// MARK: - Alerts

public struct AlertRule: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let alertType: String?
    public let severity: String?
    public let target: String?
    public var enabled: Bool?
    public let channels: Int?
}

public struct AlertTrigger: Codable, Sendable, Identifiable {
    public let id: String
    public let ruleName: String?
    public let stockCode: String?
    public let triggeredAt: String?
    public let severity: String?
    public let status: String?
    public let message: String?
}

// MARK: - RunFlow

public struct RunFlowNode: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String?
    public let status: String?
    public let durationMs: Int?
    public let detail: String?
}

public struct RunFlowEdge: Codable, Sendable, Hashable {
    public let from: String
    public let to: String
}

public struct RunFlow: Codable, Sendable {
    public let traceId: String?
    public let totalDurationMs: Int?
    public let overallStatus: String?
    public let nodes: [RunFlowNode]?
    public let edges: [RunFlowEdge]?
}

// MARK: - Screening (AlphaSift)

public struct Hotspot: Codable, Sendable, Identifiable {
    public var id: String { topic }
    public let topic: String
    public let count: Int?
    public let changePct: Double?
    public let trend: [Double]?
}

public struct ScreeningStrategy: Codable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let description: String?
}

public struct ScreeningCandidate: Codable, Sendable, Identifiable {
    public var id: String { stockCode }
    public let stockCode: String
    public let stockName: String?
    public let score: Double?
    public let changePct: Double?
    public let theme: String?
}

// MARK: - Backtest

public struct BacktestPerformance: Codable, Sendable {
    public let directionalAccuracy: Double?
    public let winRate: Double?
    public let avgReturn: Double?
    public let stopLossRate: Double?
    public let phaseDistribution: [PhaseDistribution]?
}

public struct PhaseDistribution: Codable, Sendable, Identifiable {
    public var id: String { phase }
    public let phase: String
    public let count: Int?
}

public struct BacktestResult: Codable, Sendable, Identifiable {
    public let id: String
    public let stockCode: String?
    public let stockName: String?
    public let date: String?
    public let phase: String?
    public let predicted: String?
    public let actual: String?
    public let outcome: String?
}

// MARK: - Usage

public struct UsageDashboard: Codable, Sendable {
    public let period: String?
    public let fromDate: String?
    public let toDate: String?
    public let totalCalls: Int?
    public let totalPromptTokens: Int?
    public let totalCompletionTokens: Int?
    public let totalTokens: Int?
    public let byCallType: [UsageCallTypeBreakdown]?
    public let byModel: [UsageModelBreakdown]?
    public let recentCalls: [UsageCallRecord]?
}

public struct UsageModelBreakdown: Codable, Sendable, Identifiable {
    public var id: String { model }
    public let model: String
    public let calls: Int?
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?
}

public struct UsageCallTypeBreakdown: Codable, Sendable, Identifiable {
    public var id: String { callType }
    public let callType: String
    public let calls: Int?
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?
}

public struct UsageCallRecord: Codable, Sendable, Identifiable {
    public var id: String { "\(recordId ?? 0)" }
    public let recordId: Int?
    public let calledAt: String?
    public let callType: String?
    public let model: String?
    public let stockCode: String?
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case recordId = "id"
        case calledAt, callType, model, stockCode, promptTokens, completionTokens, totalTokens
    }
}

// MARK: - LLM / Notification / Scheduler / Env

public struct LLMChannel: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String?
    public var provider: String?
    public var baseURL: String?
    public var apiKeyMasked: String?
    public var models: [String]?
    public var isPrimary: Bool?
    public var status: String?
}

public struct NotificationChannel: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let kind: String?
    public let target: String?
    public var status: String?
    public let lastSentAt: String?
}

public struct ScheduledTime: Codable, Sendable, Identifiable {
    public let id: String
    public let time: String?
    public var enabled: Bool?
    public let scope: String?
}

public struct SchedulerStatus: Codable, Sendable {
    public var enabled: Bool?
    public let nextRun: String?
    public let lastRun: String?
    public let lastRunStatus: String?
    public let times: [ScheduledTime]?
}

public struct EnvBackupPreview: Codable, Sendable {
    public let added: [String]?
    public let modified: [String]?
    public let removed: [String]?
}

// MARK: - Intelligent Import

public struct IntelligentImportItem: Identifiable, Sendable {
    public let id: UUID
    public let stockCode: String
    public let stockName: String
    public let market: String?
    public let confidence: Double
    public var selected: Bool

    public init(id: UUID = UUID(), stockCode: String, stockName: String,
                market: String?, confidence: Double, selected: Bool) {
        self.id = id; self.stockCode = stockCode; self.stockName = stockName
        self.market = market; self.confidence = confidence; self.selected = selected
    }
}

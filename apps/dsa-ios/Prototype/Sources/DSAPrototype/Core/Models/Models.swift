import Foundation

// MARK: - Stock

public struct StockQuote: Codable, Sendable, Identifiable {
    public var id: String { stockCode }
    public let stockCode: String
    public let stockName: String
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

// MARK: - Watchlist

public struct WatchlistItem: Codable, Sendable, Identifiable {
    public var id: String { stockCode }
    public let stockCode: String
    public let stockName: String?
}

// MARK: - History list item

public struct HistoryItem: Codable, Sendable, Identifiable {
    public let id: String
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
    public let modelUsed: String?
    public let createdAt: String

    public var market: Market { Market(stockCode: stockCode) }
}

// MARK: - Analysis Report

public struct ReportMeta: Codable, Sendable {
    public let id: String?
    public let queryId: String?
    public let stockCode: String
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
    public let meta: ReportMeta
    public let summary: ReportSummary?
    public let strategy: ReportStrategy?
}

// MARK: - Task

public struct TaskInfo: Codable, Sendable, Identifiable {
    public let id: String
    public let stockCode: String?
    public let stockName: String?
    public let status: String
    public let progress: Double?
    public let message: String?
    public let createdAt: String?
    public let analysisPhase: String?

    enum CodingKeys: String, CodingKey {
        case id = "task_id"
        case stockCode = "stock_code"
        case stockName = "stock_name"
        case status, progress, message
        case createdAt = "created_at"
        case analysisPhase = "analysis_phase"
    }
}

// MARK: - Auth

public struct AuthStatus: Codable, Sendable {
    public let authEnabled: Bool
    public let loggedIn: Bool
    public let passwordSet: Bool?
    public let setupState: String?
}

// MARK: - Agent

public struct AgentSkill: Codable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let description: String?
    public let icon: String?
}

public struct ChatSessionInfo: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String?
    public let messageCount: Int?
    public let updatedAt: String?
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
    public let id: String
    public let name: String
    public let currency: String?
}

public struct Position: Codable, Sendable, Identifiable {
    public var id: String { stockCode }
    public let stockCode: String
    public let stockName: String?
    public let quantity: Double
    public let avgCost: Double
    public let marketValue: Double
    public let pnl: Double
    public let pnlPct: Double
    public let weight: Double?

    public var market: Market { Market(stockCode: stockCode) }
}

public struct PortfolioSnapshot: Codable, Sendable {
    public let totalEquity: Double
    public let totalMarketValue: Double
    public let cash: Double
    public let dailyPnl: Double
    public let dailyPnlPct: Double
    public let positions: [Position]
    public let sectorAllocation: [SectorWeight]?
}

public struct SectorWeight: Codable, Sendable, Identifiable {
    public var id: String { sector }
    public let sector: String
    public let weight: Double
}

public struct PortfolioRisk: Codable, Sendable {
    public let maxDrawdown: Double?
    public let stopLossLine: Double?
    public let analysisCoverage: Double?
    public let alerts: [String]?
}

// MARK: - Decision Signal

public struct DecisionSignal: Codable, Sendable, Identifiable {
    public let id: String
    public let stockCode: String
    public let stockName: String?
    public let action: DecisionAction
    public let actionLabel: String?
    public let confidence: Double?
    public let entry: Double?
    public let stopLoss: Double?
    public let target: Double?
    public let phase: String?
    public let status: String
    public let createdAt: String?
    public let sourceReportId: String?

    public var market: Market { Market(stockCode: stockCode) }
}

public struct DecisionSignalStats: Codable, Sendable {
    public let total: Int
    public let hit: Int
    public let miss: Int
    public let hitRate: Double
}

// MARK: - Alerts

public struct AlertRule: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let alertType: String
    public let severity: String
    public let target: String?
    public var enabled: Bool
    public let channels: Int?
}

public struct AlertTrigger: Codable, Sendable, Identifiable {
    public let id: String
    public let ruleName: String
    public let stockCode: String?
    public let triggeredAt: String?
    public let severity: String
    public let status: String
    public let message: String?
}

// MARK: - RunFlow

public struct RunFlowNode: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let status: String
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
    public let nodes: [RunFlowNode]
    public let edges: [RunFlowEdge]
}

// MARK: - Screening (AlphaSift)

public struct Hotspot: Codable, Sendable, Identifiable {
    public var id: String { topic }
    public let topic: String
    public let count: Int
    public let changePct: Double
    public let trend: [Double]
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
    public let stockName: String
    public let score: Double
    public let changePct: Double
    public let theme: String?
}

// MARK: - Backtest

public struct BacktestPerformance: Codable, Sendable {
    public let directionalAccuracy: Double
    public let winRate: Double
    public let avgReturn: Double
    public let stopLossRate: Double
    public let phaseDistribution: [PhaseDistribution]
}

public struct PhaseDistribution: Codable, Sendable, Identifiable {
    public var id: String { phase }
    public let phase: String
    public let count: Int
}

public struct BacktestResult: Codable, Sendable, Identifiable {
    public let id: String
    public let stockCode: String
    public let stockName: String?
    public let date: String
    public let phase: String?
    public let predicted: String
    public let actual: String?
    public let outcome: String
}

// MARK: - Usage

public struct UsageDashboard: Codable, Sendable {
    public let totalTokens: Int
    public let totalCalls: Int
    public let promptTokens: Int
    public let completionTokens: Int
    public let modelStats: [UsageModelStat]
    public let callTypes: [UsageCallType]
    public let recent: [UsageRecord]
}

public struct UsageModelStat: Codable, Sendable, Identifiable {
    public var id: String { model }
    public let model: String
    public let tokens: Int
    public let weight: Double
}

public struct UsageCallType: Codable, Sendable, Identifiable {
    public var id: String { type }
    public let type: String
    public let count: Int
    public let weight: Double
}

public struct UsageRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let time: String
    public let type: String
    public let model: String
    public let promptTokens: Int
    public let completionTokens: Int
}

// MARK: - LLM / Notification / Scheduler / Env

public struct LLMChannel: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var provider: String
    public var baseURL: String
    public var apiKeyMasked: String
    public var models: [String]
    public var isPrimary: Bool
    public var status: String
}

public struct NotificationChannel: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String
    public let target: String?
    public var status: String
    public let lastSentAt: String?
}

public struct ScheduledTime: Codable, Sendable, Identifiable {
    public let id: String
    public let time: String
    public var enabled: Bool
    public let scope: String
}

public struct SchedulerStatus: Codable, Sendable {
    public var enabled: Bool
    public let nextRun: String?
    public let lastRun: String?
    public let lastRunStatus: String?
    public let times: [ScheduledTime]
}

public struct EnvBackupPreview: Codable, Sendable {
    public let added: [String]
    public let modified: [String]
    public let removed: [String]
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

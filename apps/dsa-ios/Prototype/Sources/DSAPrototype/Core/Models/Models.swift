import Foundation

// MARK: - JSON helper

/// 全保真 JSON 值容器：能解码任意 JSON（含数组 / 嵌套对象），用于后端 `Any` / `Dict[str, Any]` 字段。
/// 与旧的 `AnyCodable` 不同，它不会丢掉数组或嵌套结构。
public struct JSONValue: Codable, Sendable, Hashable {
    public enum Storage: Sendable, Hashable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])
    }

    public let storage: Storage
    public init(_ storage: Storage) { self.storage = storage }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { storage = .null }
        else if let v = try? c.decode(Bool.self) { storage = .bool(v) }
        else if let v = try? c.decode(Double.self) { storage = .number(v) }
        else if let v = try? c.decode(String.self) { storage = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { storage = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { storage = .object(v) }
        else { storage = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch storage {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let dict) = storage { return dict[key] } else { return nil }
    }
    public var stringValue: String? { if case .string(let v) = storage { return v } else { return nil } }
    public var doubleValue: Double? { if case .number(let v) = storage { return v } else { return nil } }
    public var boolValue: Bool? { if case .bool(let v) = storage { return v } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let v) = storage { return v } else { return nil } }
    public var objectValue: [String: JSONValue]? { if case .object(let v) = storage { return v } else { return nil } }

    /// 用共享的 DSA 解码器把本值重新解码为指定类型（保留原始 snake_case key，再走 convertFromSnakeCase）。
    public func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder.dsa.decode(type, from: data)
    }
}

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

    public init(stockCode: String, stockName: String? = nil, currentPrice: Double,
                change: Double? = nil, changePercent: Double? = nil, open: Double? = nil,
                high: Double? = nil, low: Double? = nil, prevClose: Double? = nil,
                volume: Double? = nil, amount: Double? = nil, updateTime: String? = nil) {
        self.stockCode = stockCode; self.stockName = stockName; self.currentPrice = currentPrice
        self.change = change; self.changePercent = changePercent; self.open = open
        self.high = high; self.low = low; self.prevClose = prevClose
        self.volume = volume; self.amount = amount; self.updateTime = updateTime
    }
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
    /// 用于 API 路径的记录 ID（优先 dbId，fallback queryId）
    public var recordId: String { dbId.map { String($0) } ?? queryId ?? "" }
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
    public let marketPhaseSummary: MarketPhaseSummary?
    public let createdAt: String?

    public var market: Market { Market(stockCode: stockCode) }

    enum CodingKeys: String, CodingKey {
        case dbId = "id"
        case queryId, stockCode, stockName, reportType, trendPrediction
        case analysisSummary, sentimentScore, operationAdvice
        case action, actionLabel, currentPrice, changePct
        case volumeRatio, turnoverRate, modelUsed, marketPhaseSummary, createdAt
    }
}

// MARK: - Analysis Report (detail)

public struct ReportMeta: Codable, Sendable {
    public let id: Int?
    public let queryId: String?
    public let stockCode: String?
    public let stockName: String?
    public let reportType: String?
    public let reportLanguage: String?
    public let createdAt: String?
    public let currentPrice: Double?
    public let changePct: Double?
    public let modelUsed: String?
    public let marketPhaseSummary: MarketPhaseSummary?
}

public struct MarketPhaseSummary: Codable, Sendable {
    public let market: String?
    public let phase: String?
    public let marketLocalTime: String?
    public let sessionDate: String?
    public let effectiveDailyBarDate: String?
    public let isTradingDay: Bool?
    public let isMarketOpenNow: Bool?
    public let isPartialBar: Bool?
    public let minutesToOpen: Int?
    public let minutesToClose: Int?
    public let triggerSource: String?
    public let analysisIntent: String?
    public let warnings: [String]?
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
    public let details: ReportDetails?
}

public struct ReportDetails: Codable, Sendable {
    public let newsContent: String?
    public let rawResult: JSONValue?
    public let contextSnapshot: JSONValue?
    public let analysisContextPackOverview: AnalysisContextPackOverview?
    public let financialReport: JSONValue?
    public let dividendMetrics: JSONValue?
    public let belongBoards: [RelatedBoard]?
    public let sectorRankings: MarketSectors?

    /// 从 context_snapshot 中提取大盘评述 payload（market_review 报告用）。
    public var marketReviewPayload: MarketReviewPayload? {
        contextSnapshot?["market_review_payload"]?.decode(MarketReviewPayload.self)
    }
}

/// 关联板块条目（belong_boards，后端为 Any，按 WebUI RelatedBoard 形状建模）。
public struct RelatedBoard: Codable, Sendable, Identifiable {
    public var id: String { "\(name ?? "")-\(code ?? "")" }
    public let name: String?
    public let code: String?
    public let type: String?
}

public struct MarketReviewPayload: Codable, Sendable {
    public let title: String?
    public let rootTitle: String?
    public let region: String?
    public let language: String?
    public let date: String?
    public let generatedAt: String?
    public let markdownReport: String?
    public let sections: [MarketReviewSection]?
    public let indices: [MarketIndex]?
    public let breadth: MarketBreadth?
    public let sectors: MarketSectors?
    public let marketLight: MarketLight?
    public let marketScope: String?
    public let version: Int?
    public let kind: String?
    public let news: [JSONValue]?
    /// 多区域：每个区域对应一个 payload（递归结构）。
    public let markets: [String: MarketReviewPayload]?
}

public struct MarketReviewSection: Codable, Sendable, Identifiable {
    public var id: String { key ?? title ?? UUID().uuidString }
    public let key: String?
    public let title: String?
    public let markdown: String?
}

public struct MarketBreadth: Codable, Sendable {
    public let upCount: Int?
    public let downCount: Int?
    public let flatCount: Int?
    public let limitUpCount: Int?
    public let limitDownCount: Int?
    public let totalAmount: Double?
    public let turnoverUnit: String?
}

public struct MarketIndex: Codable, Sendable, Identifiable {
    public var id: String { code ?? name ?? "" }
    public let code: String?
    public let name: String?
    public let current: Double?
    public let changePct: Double?
    public let high: Double?
    public let low: Double?
}

public struct MarketSectors: Codable, Sendable {
    public let top: [SectorItem]?
    public let bottom: [SectorItem]?
}

public struct SectorItem: Codable, Sendable, Identifiable {
    public var id: String { name ?? "" }
    public let name: String?
    public let changePct: Double?
}

public struct MarketLight: Codable, Sendable {
    public let signal: Int?
    public let label: String?
}

// MARK: - AnalysisContextPackOverview（输入数据质量低敏摘要）

public struct AnalysisContextPackOverview: Codable, Sendable {
    public let packVersion: String?
    public let createdAt: String?
    public let subject: AnalysisContextPackOverviewSubject?
    public let blocks: [AnalysisContextPackOverviewBlock]?
    public let counts: AnalysisContextPackOverviewCounts?
    public let dataQuality: AnalysisContextPackOverviewDataQuality?
    public let warnings: [String]?
    public let metadata: AnalysisContextPackOverviewMetadata?
}

public struct AnalysisContextPackOverviewSubject: Codable, Sendable {
    public let code: String?
    public let stockName: String?
    public let market: String?
}

public struct AnalysisContextPackOverviewBlock: Codable, Sendable, Identifiable {
    public var id: String { key ?? label ?? UUID().uuidString }
    public let key: String?
    public let label: String?
    public let status: String?
    public let source: String?
    public let warnings: [String]?
    public let missingReasons: [String]?
}

public struct AnalysisContextPackOverviewCounts: Codable, Sendable {
    public let available: Int?
    public let missing: Int?
    public let notSupported: Int?
    public let fallback: Int?
    public let stale: Int?
    public let estimated: Int?
    public let partial: Int?
    public let fetchFailed: Int?
}

public struct AnalysisContextPackOverviewMetadata: Codable, Sendable {
    public let triggerSource: String?
    public let newsResultCount: Int?
}

public struct AnalysisContextPackOverviewDataQuality: Codable, Sendable {
    public let overallScore: Int?
    public let level: String?
    public let blockScores: [String: Int]?
    public let limitations: [String]?
}

// MARK: - News intel（报告相关新闻）

public struct NewsIntelItem: Codable, Sendable, Identifiable {
    public var id: String { url ?? title ?? UUID().uuidString }
    public let title: String?
    public let snippet: String?
    public let url: String?
}

public struct NewsIntelResponse: Codable, Sendable {
    public let total: Int?
    public let items: [NewsIntelItem]?
}

// MARK: - Stock bar（个股聚合栏）

public struct StockBarItem: Codable, Sendable, Identifiable {
    public var id: String { "\(recordId ?? 0)-\(stockCode)" }
    public let recordId: Int?
    public let stockCode: String
    public let stockName: String?
    public let reportType: String?
    public let sentimentScore: Double?
    public let operationAdvice: String?
    public let action: DecisionAction?
    public let actionLabel: String?
    public let analysisCount: Int?
    public let lastAnalysisTime: String?
    public let modelUsed: String?
    public let marketPhaseSummary: MarketPhaseSummary?

    public var market: Market { Market(stockCode: stockCode) }
}

public struct StockBarResponse: Codable, Sendable {
    public let total: Int?
    public let items: [StockBarItem]?
}

// MARK: - Run diagnostics（运行诊断摘要）

public struct RunDiagnosticComponent: Codable, Sendable, Identifiable {
    public var id: String { key ?? label ?? UUID().uuidString }
    public let key: String?
    public let label: String?
    public let status: String?
    public let message: String?
    public let details: JSONValue?
}

public struct RunDiagnosticSummaryResponse: Codable, Sendable {
    public let traceId: String?
    public let taskId: String?
    public let queryId: String?
    public let stockCode: String?
    public let triggerSource: String?
    public let status: String?
    public let statusLabel: String?
    public let reason: String?
    public let components: [String: RunDiagnosticComponent]?
    public let copyText: String?
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
    public var toolCount: Int
    public var toolDurationTotal: Double
    public var isStreaming: Bool

    public init(id: UUID = UUID(), role: ChatRole, text: String,
                thinking: [String] = [], tools: [String] = [], toolCount: Int = 0,
                toolDurationTotal: Double = 0, isStreaming: Bool = false) {
        self.id = id; self.role = role; self.text = text
        self.thinking = thinking; self.tools = tools
        self.toolCount = toolCount; self.toolDurationTotal = toolDurationTotal
        self.isStreaming = isStreaming
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
    public let valuationCurrency: String?
    public let priceSource: String?
    public let priceProvider: String?
    public let priceDate: String?
    public let priceStale: Bool?
    public let priceAvailable: Bool?

    public var marketEnum: Market { Market(stockCode: symbol) }
}

public struct PortfolioAccountSnapshot: Codable, Sendable, Identifiable {
    public var id: String { "\(accountId ?? 0)" }
    public let accountId: Int?
    public let accountName: String?
    public let ownerId: String?
    public let broker: String?
    public let market: String?
    public let baseCurrency: String?
    public let asOf: String?
    public let costMethod: String?
    public let totalCash: Double?
    public let totalMarketValue: Double?
    public let totalEquity: Double?
    public let realizedPnl: Double?
    public let unrealizedPnl: Double?
    public let feeTotal: Double?
    public let taxTotal: Double?
    public let fxStale: Bool?
    public let positions: [PortfolioPositionItem]?

    enum CodingKeys: String, CodingKey {
        case accountId, accountName, ownerId, broker, market, baseCurrency
        case asOf, costMethod, totalCash, totalMarketValue, totalEquity
        case realizedPnl, unrealizedPnl, feeTotal, taxTotal, fxStale, positions
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

public struct PortfolioDecisionSignalRiskItem: Codable, Sendable {
    public let accountId: Int?
    public let symbol: String?
    public let market: String?
    public let signal: JSONValue?
}

public struct PortfolioDecisionSignalRiskBlock: Codable, Sendable {
    public let available: Bool?
    public let total: Int?
    public let actions: [String: Int]?
    public let items: [PortfolioDecisionSignalRiskItem]?
}

public struct PortfolioRiskResponse: Codable, Sendable {
    public let asOf: String?
    public let accountId: Int?
    public let costMethod: String?
    public let currency: String?
    public let thresholds: JSONValue?
    public let concentration: JSONValue?
    public let sectorConcentration: JSONValue?
    public let drawdown: JSONValue?
    public let stopLoss: JSONValue?
    public let decisionSignalRisk: PortfolioDecisionSignalRiskBlock?
}

// MARK: - Portfolio write-side (accounts / trades / events / imports / fx)

public struct PortfolioAccountItem: Codable, Sendable, Identifiable {
    public let id: Int
    public let ownerId: String?
    public let name: String
    public let broker: String?
    public let market: String
    public let baseCurrency: String
    public let isActive: Bool?
    public let createdAt: String?
    public let updatedAt: String?
}

public struct PortfolioAccountListResponse: Codable, Sendable {
    public let accounts: [PortfolioAccountItem]?
}

/// 通用「事件已创建」响应：POST /trades、/cash-ledger、/corporate-actions 只回 {id}。
public struct PortfolioEventCreatedResponse: Codable, Sendable {
    public let id: Int?
}

public struct PortfolioDeleteResponse: Codable, Sendable {
    public let deleted: Int?
}

public struct PortfolioTradeListItem: Codable, Sendable, Identifiable {
    public let id: Int
    public let accountId: Int?
    public let tradeUid: String?
    public let symbol: String
    public let market: String?
    public let currency: String?
    public let tradeDate: String?
    public let side: String?
    public let quantity: Double?
    public let price: Double?
    public let fee: Double?
    public let tax: Double?
    public let note: String?
    public let createdAt: String?
}

public struct PortfolioTradeListResponse: Codable, Sendable {
    public let items: [PortfolioTradeListItem]?
    public let total: Int?
}

public struct PortfolioImportTradeItem: Codable, Sendable, Identifiable {
    public var id: String { (tradeUid ?? "") + "|" + (tradeDate ?? "") + "|" + symbol }
    public let tradeDate: String?
    public let symbol: String
    public let side: String?
    public let quantity: Double?
    public let price: Double?
    public let fee: Double?
    public let tax: Double?
    public let tradeUid: String?
    public let currency: String?
}

public struct PortfolioImportParseResponse: Codable, Sendable {
    public let broker: String?
    public let recordCount: Int?
    public let skippedCount: Int?
    public let errorCount: Int?
    public let records: [PortfolioImportTradeItem]?
    public let errors: [String]?
}

public struct PortfolioImportCommitResponse: Codable, Sendable {
    public let accountId: Int?
    public let recordCount: Int?
    public let insertedCount: Int?
    public let duplicateCount: Int?
    public let failedCount: Int?
    public let dryRun: Bool?
    public let errors: [String]?
}

public struct PortfolioImportBrokerItem: Codable, Sendable, Identifiable {
    public var id: String { broker }
    public let broker: String
    public let aliases: [String]?
    public let displayName: String?
}

public struct PortfolioImportBrokerListResponse: Codable, Sendable {
    public let brokers: [PortfolioImportBrokerItem]?
}

public struct PortfolioFxRefreshResponse: Codable, Sendable {
    public let asOf: String?
    public let accountCount: Int?
    public let refreshEnabled: Bool?
    public let disabledReason: String?
    public let pairCount: Int?
    public let updatedCount: Int?
    public let staleCount: Int?
    public let errorCount: Int?
}

// MARK: - Decision Signal

public struct DecisionSignal: Codable, Sendable, Identifiable {
    public let id: Int
    public let stockCode: String
    public let stockName: String?
    public let market: String?
    public let sourceType: String?
    public let sourceAgent: String?
    public let sourceReportId: Int?
    public let traceId: String?
    public let marketPhase: String?
    public let triggerSource: String?
    public let action: DecisionAction?
    public let actionLabel: String?
    public let confidence: Double?
    public let score: Int?
    public let horizon: String?
    public let entryLow: Double?
    public let entryHigh: Double?
    public let stopLoss: Double?
    public let targetPrice: Double?
    public let invalidation: String?
    public let watchConditions: String?
    public let reason: String?
    public let riskSummary: String?
    public let catalystSummary: String?
    public let evidence: JSONValue?
    public let dataQualitySummary: JSONValue?
    public let planQuality: String?
    public let status: String?
    public let expiresAt: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let metadata: JSONValue?

    public var marketEnum: Market { Market(stockCode: stockCode) }
}

/// 决策信号反馈请求（对齐 DecisionSignalFeedbackRequest）。
public struct DecisionSignalFeedbackRequest: Encodable, Sendable {
    public let feedbackValue: String   // "useful" | "not_useful"
    public let reasonCode: String?
    public let note: String?
    public let source: String          // "web" | "api"

    public init(feedbackValue: String, reasonCode: String? = nil, note: String? = nil, source: String = "web") {
        self.feedbackValue = feedbackValue
        self.reasonCode = reasonCode
        self.note = note
        self.source = source
    }
}

/// 决策信号状态更新：PATCH /decision-signals/{id}/status。
/// status: active/closed/expired/invalidated/archived；terminal 状态不可 PATCH 回 active。
public struct DecisionSignalStatusUpdateRequest: Encodable, Sendable {
    public let status: String
    public let metadata: JSONValue?

    public init(status: String, metadata: JSONValue? = nil) {
        self.status = status
        self.metadata = metadata
    }
}

public struct DecisionSignalOutcomeItem: Codable, Sendable, Identifiable {
    public var id: Int { outcomeId ?? signalId ?? 0 }
    public let outcomeId: Int?
    public let signalId: Int?
    public let horizon: String?
    public let engineVersion: String?
    public let evalStatus: String?
    public let outcome: String?
    public let directionExpected: String?
    public let directionCorrect: Bool?
    public let unableReason: String?
    public let anchorDate: String?
    public let evalWindowDays: Int?
    public let startPrice: Double?
    public let endClose: Double?
    public let maxHigh: Double?
    public let minLow: Double?
    public let stockReturnPct: Double?
    public let action: String?
    public let market: String?
    public let marketPhase: String?
    public let sourceType: String?
    public let sourceAgent: String?
    public let planQuality: String?
    public let dataQualityLevel: String?
    public let holdingState: String?
    public let createdAt: String?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case outcomeId = "id"
        case signalId, horizon, engineVersion, evalStatus, outcome, directionExpected, directionCorrect
        case unableReason, anchorDate, evalWindowDays, startPrice, endClose, maxHigh, minLow, stockReturnPct
        case action, market, marketPhase, sourceType, sourceAgent, planQuality, dataQualityLevel
        case holdingState, createdAt, updatedAt
    }
}

public struct DecisionSignalOutcomeListResponse: Codable, Sendable {
    public let items: [DecisionSignalOutcomeItem]?
    public let total: Int?
    public let page: Int?
    public let pageSize: Int?
}

public struct DecisionSignalOutcomeStatsBucket: Codable, Sendable {
    public let dimension: String?
    public let value: String?
    public let total: Int?
    public let completed: Int?
    public let unable: Int?
    public let hit: Int?
    public let miss: Int?
    public let neutral: Int?
    public let hitRatePct: Double?
    public let avgStockReturnPct: Double?
    public let unableReasons: [String: Int]?
}

public struct DecisionSignalStats: Codable, Sendable {
    public let engineVersion: String?
    public let horizons: [String]?
    public let statuses: [String]?
    public let total: Int?
    public let completed: Int?
    public let unable: Int?
    public let hit: Int?
    public let miss: Int?
    public let neutral: Int?
    public let hitRatePct: Double?
    public let avgStockReturnPct: Double?
    public let unableReasons: [String: Int]?
    public let breakdowns: [String: [DecisionSignalOutcomeStatsBucket]]?
}

// MARK: - Alerts

public struct AlertRule: Codable, Sendable, Identifiable {
    public let id: Int
    public let name: String?
    public let targetScope: String?
    public let target: String?
    public let alertType: String?
    public let parameters: JSONValue?
    public let severity: String?
    public var enabled: Bool?
    public let source: String?
    public let cooldownPolicy: JSONValue?
    public let notificationPolicy: JSONValue?
    public let lastTriggeredAt: String?
    public let cooldownUntil: String?
    public let cooldownActive: Bool?
    public let createdAt: String?
    public let updatedAt: String?
}

public struct AlertTrigger: Codable, Sendable, Identifiable {
    public let id: Int
    public let ruleId: Int?
    public let target: String?
    public let observedValue: Double?
    public let threshold: Double?
    public let reason: String?
    public let dataSource: String?
    public let dataTimestamp: String?
    public let triggeredAt: String?
    public let status: String?
    public let diagnostics: String?
    public let marketPhaseSummary: MarketPhaseSummary?
    public let analysisContextPackOverview: AnalysisContextPackOverview?
    public let analysisVisibilitySource: String?
    public let decisionSignalSummary: JSONValue?
}

public struct AlertNotificationItem: Codable, Sendable, Identifiable {
    public var id: Int { notificationId ?? (triggerId ?? 0) }
    public let notificationId: Int?
    public let triggerId: Int?
    public let channel: String?
    public let attempt: Int?
    public let success: Bool?
    public let errorCode: String?
    public let retryable: Bool?
    public let latencyMs: Int?
    public let diagnostics: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case notificationId = "id"
        case triggerId, channel, attempt, success, errorCode, retryable, latencyMs, diagnostics, createdAt
    }
}

public struct AlertNotificationListResponse: Codable, Sendable {
    public let items: [AlertNotificationItem]?
    public let total: Int?
    public let page: Int?
    public let pageSize: Int?
}

// MARK: - RunFlow

public struct RunFlowLane: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String?
    public let order: Int?
}

public struct RunFlowNode: Codable, Sendable, Identifiable {
    public let id: String
    public let lane: String?
    public let kind: String?
    public let label: String?
    public let status: String?
    public let provider: String?
    public let startedAt: String?
    public let endedAt: String?
    public let durationMs: Int?
    public let attempts: Int?
    public let recordCount: Int?
    public let message: String?
    public let metadata: JSONValue?

    /// 兼容旧字段：节点短摘要等价于 message。
    public var detail: String? { message }
}

public struct RunFlowEdge: Codable, Sendable, Hashable {
    public let id: String?
    public let from: String
    public let to: String
    public let kind: String?
    public let status: String?
    public let label: String?
    public let message: String?
    public let metadata: JSONValue?
}

public struct RunFlowEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: String?
    public let severity: String?
    public let type: String?
    public let nodeId: String?
    public let title: String?
    public let message: String?
    public let metadata: JSONValue?
}

public struct RunFlowSummary: Codable, Sendable {
    public let elapsedMs: Int?
    public let bottleneckNodeId: String?
    public let failedAttempts: Int?
    public let fallbackCount: Int?
    public let model: String?
    public let dataSourceCount: Int?
    public let eventCount: Int?
}

public struct RunFlow: Codable, Sendable {
    public let taskId: String?
    public let traceId: String?
    public let stockCode: String?
    public let stockName: String?
    public let status: String?
    public let summary: RunFlowSummary?
    public let lanes: [RunFlowLane]?
    public let nodes: [RunFlowNode]?
    public let edges: [RunFlowEdge]?
    public let events: [RunFlowEvent]?
    public let generatedAt: String?

    /// 兼容旧字段。
    public var overallStatus: String? { status }
    public var totalDurationMs: Int? { summary?.elapsedMs }
}

// MARK: - Screening (AlphaSift)

public struct AlphaSiftStatus: Codable, Sendable {
    public let enabled: Bool?
    public let available: Bool?
    public let installSpecIsDefault: Bool?
    public let contractVersion: String?
    public let version: String?
    public let strategyCount: Int?
    public let diagnostics: [String: String]?
}

public struct AlphaSiftHotspot: Codable, Sendable, Identifiable {
    public var id: String { topic }
    public let topic: String
    public let name: String?
    public let source: String?
    public let rank: Int?
    public let changePct: Double?
    public let heatScore: Double?
    public let trendScore: Double?
    public let persistenceScore: Double?
    public let coolingScore: Double?
    public let observations: Int?
    public let state: String?
    public let stage: String?
    public let sampleStockCount: Int?
    public let leaders: [String]?
    public let providerUsed: String?
    public let fallbackUsed: Bool?
    public let cacheUsed: Bool?
    public let cachedAt: String?
    public let sourceErrors: [String]?
    public let stale: Bool?
    public let staleAgeHours: Double?
}

public struct AlphaSiftHotspotRouteItem: Codable, Sendable, Identifiable {
    public var id: String { (publishedAt ?? date ?? "") + (title ?? "") }
    public let title: String?
    public let description: String?
    public let source: String?
    public let date: String?
    public let time: String?
    public let publishedAt: String?
    public let url: String?
}

public struct AlphaSiftHotspotStock: Codable, Sendable, Identifiable {
    public var id: String { code ?? UUID().uuidString }
    public let code: String?
    public let name: String?
    public let changePct: Double?
    public let amount: Double?
    public let turnoverRate: Double?
    public let volumeRatio: Double?
    public let role: String?
    public let hotStockScore: Double?
    public let source: String?
    public let sourceConfidence: Double?
    public let fallbackUsed: Bool?
}

public struct AlphaSiftHotspotDetail: Codable, Sendable {
    public let enabled: Bool?
    public let provider: String?
    public let topic: String
    public let name: String?
    public let canonicalTopic: String?
    public let aliases: [String]?
    public let route: [AlphaSiftHotspotRouteItem]?
    public let timeline: [AlphaSiftHotspotRouteItem]?
    public let stocks: [AlphaSiftHotspotStock]?
    public let leaderStocks: [AlphaSiftHotspotStock]?
    public let stockCount: Int?
    public let sourceErrors: [String]?
    public let qualityStatus: String?
    public let missingFields: [String]?
    public let fallbackUsed: Bool?
    public let stale: Bool?
    public let staleAgeHours: Double?
    public let cacheUsed: Bool?
    public let cachedAt: String?
}

public struct AlphaSiftHotspotsResponse: Codable, Sendable {
    public let enabled: Bool?
    public let provider: String?
    public let providerUsed: String?
    public let fallbackUsed: Bool?
    public let cacheUsed: Bool?
    public let cachedAt: String?
    public let sourceErrors: [String]?
    public let stale: Bool?
    public let staleAgeHours: Double?
    public let message: String?
    public let hotspots: [AlphaSiftHotspot]?
    public let hotspotCount: Int?
    public let details: [String: AlphaSiftHotspotDetail]?
}

public struct ScreeningStrategy: Codable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let title: String?
    public let description: String?
    public let category: String?
    public let tag: String?
    public let tags: [String]?
    public let marketScope: [String]?
    public let market: String?

    enum CodingKeys: String, CodingKey {
        case key = "id"
        case name, title, description, category, tag, tags, marketScope, market
    }
}

public struct ScreeningStrategiesResponse: Codable, Sendable {
    public let enabled: Bool?
    public let strategies: [ScreeningStrategy]?
    public let strategyCount: Int?
}

public struct DSANewsItem: Codable, Sendable, Identifiable {
    public var id: String { url ?? title ?? UUID().uuidString }
    public let title: String?
    public let snippet: String?
    public let url: String?
    public let source: String?
    public let publishedDate: String?
}

public struct ScreeningCandidate: Codable, Sendable, Identifiable {
    public var id: String { code }
    public let rank: Int?
    public let code: String
    public let name: String?
    public let score: Double?
    public let screenScore: Double?
    public let reason: String?
    public let riskLevel: String?
    public let riskFlags: [String]?
    public let llmScore: Double?
    public let llmConfidence: Double?
    public let llmSector: String?
    public let llmTheme: String?
    public let llmTags: [String]?
    public let llmThesis: String?
    public let llmCatalysts: [String]?
    public let llmRisks: [String]?
    public let llmWatchItems: [String]?
    public let llmInvalidators: [String]?
    public let llmStyleFit: String?
    public let price: Double?
    public let changePct: Double?
    public let amount: Double?
    public let industry: String?
    public let factorScores: [String: Double]?
    public let dsaAnalysisSummary: String?
    public let dsaNews: [DSANewsItem]?
    public let postAnalysisTags: [String]?

    public var market: Market { Market(stockCode: code) }
}

public struct AlphaSiftDsaEnrichment: Codable, Sendable {
    public let enabled: Bool?
    public let maxCandidates: Int?
    public let requestedCount: Int?
    public let enrichedCount: Int?
    public let warnings: [String]?
}

public struct AlphaSiftScreenResponse: Codable, Sendable {
    public let enabled: Bool?
    public let candidates: [ScreeningCandidate]?
    public let candidateCount: Int?
    public let runId: String?
    public let strategy: String?
    public let market: String?
    public let snapshotCount: Int?
    public let afterFilterCount: Int?
    public let llmRanked: Bool?
    public let llmMarketView: String?
    public let llmSelectionLogic: String?
    public let llmPortfolioRisk: String?
    public let llmCoverage: Double?
    public let llmParseErrors: [String]?
    public let warnings: [String]?
    public let sourceErrors: [String]?
    public let dsaEnrichment: AlphaSiftDsaEnrichment?
    public let portfolioConcentrationNotes: [String]?
}

public struct AlphaSiftScreenAccepted: Codable, Sendable {
    public let taskId: String
    public let traceId: String?
    public let status: String
    public let message: String?
    public let strategy: String?
    public let market: String?
    public let maxResults: Int?
}

public struct AlphaSiftScreenTaskStatus: Codable, Sendable {
    public let taskId: String
    public let traceId: String?
    public let status: String
    public let progress: Int?
    public let message: String?
    public let error: String?
    public let result: AlphaSiftScreenResponse?
}

// MARK: - Backtest

/// 对齐后端 PerformanceMetrics。
public struct BacktestPerformance: Codable, Sendable {
    public let scope: String?
    public let code: String?
    public let evalWindowDays: Int?
    public let engineVersion: String?
    public let computedAt: String?
    public let totalEvaluations: Int?
    public let completedCount: Int?
    public let insufficientCount: Int?
    public let longCount: Int?
    public let cashCount: Int?
    public let winCount: Int?
    public let lossCount: Int?
    public let neutralCount: Int?
    public let directionAccuracyPct: Double?
    public let winRatePct: Double?
    public let neutralRatePct: Double?
    public let avgStockReturnPct: Double?
    public let avgSimulatedReturnPct: Double?
    public let stopLossTriggerRate: Double?
    public let takeProfitTriggerRate: Double?
    public let ambiguousRate: Double?
    public let avgDaysToFirstHit: Double?
    public let adviceBreakdown: JSONValue?
    public let diagnostics: JSONValue?
}

/// 对齐后端 BacktestResultItem。
public struct BacktestResult: Codable, Sendable, Identifiable {
    public var id: Int { analysisHistoryId }
    public let analysisHistoryId: Int
    public let code: String
    public let stockName: String?
    public let analysisDate: String?
    public let evalWindowDays: Int?
    public let engineVersion: String?
    public let evalStatus: String?
    public let evaluatedAt: String?
    public let operationAdvice: String?
    public let action: DecisionAction?
    public let actionLabel: String?
    public let trendPrediction: String?
    public let marketPhase: String?
    public let marketPhaseSummary: MarketPhaseSummary?
    public let positionRecommendation: String?
    public let startPrice: Double?
    public let endClose: Double?
    public let maxHigh: Double?
    public let minLow: Double?
    public let stockReturnPct: Double?
    public let actualReturnPct: Double?
    public let actualMovement: String?
    public let directionExpected: String?
    public let directionCorrect: Bool?
    public let outcome: String?
    public let stopLoss: Double?
    public let takeProfit: Double?
    public let hitStopLoss: Bool?
    public let hitTakeProfit: Bool?
    public let firstHit: String?
    public let firstHitDate: String?
    public let firstHitTradingDays: Int?
    public let simulatedEntryPrice: Double?
    public let simulatedExitPrice: Double?
    public let simulatedExitReason: String?
    public let simulatedReturnPct: Double?
}

public struct BacktestResultsResponse: Codable, Sendable {
    public let total: Int?
    public let page: Int?
    public let limit: Int?
    public let items: [BacktestResult]?
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
    public let maxTotalTokens: Int?
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

/// 与后端 GET /system/scheduler/status 返回结构对齐。
/// schedule_times 为时间字符串数组（如 ["09:30", "15:00"]），非对象数组。
public struct SchedulerStatus: Codable, Sendable {
    public var enabled: Bool?
    public let running: Bool?
    public let scheduleTimes: [String]?
    public let nextRunAt: String?
    public let lastRunAt: String?
    public let lastSuccessAt: String?
    public let lastError: String?
    public let lastSkippedAt: String?
    public let lastSkipReason: String?
}

// MARK: - System config（只读展示用）

/// GET /system/config 返回结构：通知 / LLM 等渠道以扁平 key/value 条目形式承载，
/// 按 schema.category 分类（notification / ai_model / ...），敏感值由服务端掩码。
public struct SystemConfigResponse: Codable, Sendable {
    public let configVersion: String?
    public let maskToken: String?
    public let items: [SystemConfigItem]?
}

/// PUT /system/config 的更新结果（成功后含新 config_version、应用计数、警告）。
public struct SystemConfigUpdateResponse: Codable, Sendable {
    public let success: Bool?
    public let configVersion: String?
    public let appliedCount: Int?
    public let skippedMaskedCount: Int?
    public let reloadTriggered: Bool?
    public let updatedKeys: [String]?
    public let warnings: [String]?
}

/// POST /system/config/validate 的单项问题。
public struct SystemConfigValidationIssue: Codable, Sendable, Identifiable {
    public var id: String { "\(key)-\(code)" }
    public let key: String?
    public let code: String?
    public let message: String?
    public let severity: String?
    public let expected: String?
    public let actual: String?
}

/// POST /system/config/validate 的结果。
public struct SystemConfigValidateResponse: Codable, Sendable {
    public let valid: Bool?
    public let issues: [SystemConfigValidationIssue]?
}

/// GET /system/config/export 的结果（原始 .env 文本）。
public struct SystemConfigExportResponse: Codable, Sendable {
    public let content: String?
    public let configVersion: String?
    public let updatedAt: String?
}

/// POST /system/config/notification/test-channel 单次投递结果。
public struct NotificationTestAttempt: Codable, Sendable, Identifiable {
    public var id: String { "\(channel ?? "?")-\(stage ?? "?")-\(latencyMs ?? 0)" }
    public let channel: String?
    public let success: Bool?
    public let message: String?
    public let target: String?
    public let errorCode: String?
    public let stage: String?
    public let retryable: Bool?
    public let latencyMs: Int?
    public let httpStatus: Int?
}

/// POST /system/config/notification/test-channel 总结果。
public struct SystemConfigNotificationTestResponse: Codable, Sendable {
    public let success: Bool?
    public let message: String?
    public let errorCode: String?
    public let stage: String?
    public let retryable: Bool?
    public let latencyMs: Int?
    public let attempts: [NotificationTestAttempt]?
}

/// POST /system/config/llm/test-channel 单项能力结果。
public struct LLMCapabilityResult: Codable, Sendable {
    public let status: String?      // passed / failed / skipped
    public let message: String?
    public let errorCode: String?
    public let stage: String?
    public let latencyMs: Int?
}

/// POST /system/config/llm/test-channel 总结果。
public struct SystemConfigLLMTestResponse: Codable, Sendable {
    public let success: Bool?
    public let message: String?
    public let error: String?
    public let errorCode: String?
    public let latencyMs: Int?
    public let capabilityResults: [String: LLMCapabilityResult]?
}

/// POST /system/config/llm/discover-models 结果。
public struct SystemConfigLLMDiscoverResponse: Codable, Sendable {
    public let success: Bool?
    public let message: String?
    public let error: String?
    public let models: [String]?
    public let latencyMs: Int?
}

/// POST /backtest/run 结果。
public struct BacktestRunResponse: Codable, Sendable {
    public let processed: Int?
    public let saved: Int?
    public let completed: Int?
    public let insufficient: Int?
    public let errors: Int?
}

public struct SystemConfigItem: Codable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let value: String?
    public let isMasked: Bool?
    public let rawValueExists: Bool?
    public let schema: SystemConfigFieldSchema?
}

public struct SystemConfigFieldSchema: Codable, Sendable {
    public let key: String?
    public let title: String?
    public let category: String?
    public let isSensitive: Bool?
    public let uiControl: String?
    public let fieldDescription: String?

    enum CodingKeys: String, CodingKey {
        case key, title, category, isSensitive, uiControl
        case fieldDescription = "description"
    }
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

/// 图片 / 文本提取结果（POST /stocks/extract-from-image、/stocks/parse-import）。
/// 注意：后端 confidence 是字符串 "high"/"medium"/"low"，非数值。
public struct ExtractItem: Codable, Sendable {
    public let code: String?
    public let name: String?
    public let confidence: String?
}

public struct ExtractFromImageResponse: Codable, Sendable {
    public let codes: [String]?
    public let items: [ExtractItem]?
    public let rawText: String?
}

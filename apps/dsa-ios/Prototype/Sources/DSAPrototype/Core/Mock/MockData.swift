import Foundation

public enum MockData {
    public static let watchlist: [StockQuote] = [
        StockQuote(stockCode: "600519", stockName: "贵州茅台", currentPrice: 1680.00,
                   change: 20.50, changePercent: 1.23,
                   open: 1660, high: 1690, low: 1655, prevClose: 1659.50,
                   volume: 28_500_000, amount: 47_700_000_000, updateTime: "2026-06-23 15:00"),
        StockQuote(stockCode: "00700", stockName: "腾讯控股", currentPrice: 385.20,
                   change: -3.30, changePercent: -0.85,
                   open: 388, high: 390, low: 384, prevClose: 388.50,
                   volume: nil, amount: nil, updateTime: "2026-06-23 16:00"),
        StockQuote(stockCode: "AAPL", stockName: "Apple Inc", currentPrice: 192.30,
                   change: 0.80, changePercent: 0.42,
                   open: 191.5, high: 193.2, low: 191.0, prevClose: 191.50,
                   volume: nil, amount: nil, updateTime: "2026-06-23 04:00"),
        StockQuote(stockCode: "NVDA", stockName: "NVIDIA", currentPrice: 132.05,
                   change: -2.45, changePercent: -1.82,
                   open: 134.5, high: 134.8, low: 131.5, prevClose: 134.50,
                   volume: nil, amount: nil, updateTime: "2026-06-23 04:00")
    ]

    public static let history: [HistoryItem] = [
        HistoryItem(id: "h1", queryId: "q1", stockCode: "600519", stockName: "贵州茅台",
                    reportType: "full", trendPrediction: "看多", analysisSummary: "白酒板块情绪修复，公司基本面稳健。",
                    sentimentScore: 78, operationAdvice: "1,580-1,620 区间分批建仓",
                    action: .buy, actionLabel: "买入",
                    currentPrice: 1680, changePct: 1.23, modelUsed: "gpt-4o",
                    createdAt: "2 小时前"),
        HistoryItem(id: "h2", queryId: "q2", stockCode: "00700", stockName: "腾讯控股",
                    reportType: "brief", trendPrediction: nil, analysisSummary: "短期承压，等待关键支撑确认。",
                    sentimentScore: 50, operationAdvice: nil,
                    action: .watch, actionLabel: "观望",
                    currentPrice: 385, changePct: -0.85, modelUsed: "claude-3.5",
                    createdAt: "昨天")
    ]

    public static let report: AnalysisReport = AnalysisReport(
        meta: ReportMeta(id: "h1", queryId: "q1", stockCode: "600519", stockName: "贵州茅台",
                         reportType: "full", reportLanguage: "zh",
                         createdAt: "2026-06-23 15:30",
                         currentPrice: 1680, changePct: 1.23, modelUsed: "gpt-4o"),
        summary: ReportSummary(
            analysisSummary: "白酒板块情绪修复，公司基本面稳健、Q1 现金流环比改善。",
            operationAdvice: "建议在 1,580-1,620 区间分批建仓，仓位上限 30%。",
            action: .buy, actionLabel: "买入",
            trendPrediction: "短期偏多，关注 1,720 压力位；中期 200 日均线上方维持多头结构。",
            sentimentScore: 78, sentimentLabel: "乐观"),
        strategy: ReportStrategy(idealBuy: "1,580", secondaryBuy: "1,620", stopLoss: "1,520", takeProfit: "1,780")
    )

    public static let kline: [KLineData] = (0..<60).map { i in
        let base: Double = 1500
        let drift = Double(i) * 3.0
        let noise = Double((i * 7) % 30 - 15)
        let close = base + drift + noise
        let open = close - 4 + Double((i * 11) % 8 - 4)
        return KLineData(date: "2026-04-\(String(format: "%02d", (i % 28) + 1))",
                         open: open, high: max(open, close) + 6, low: min(open, close) - 6,
                         close: close, volume: 1_000_000, amount: nil,
                         changePercent: ((close - open) / open) * 100)
    }

    public static let skills: [AgentSkill] = [
        .init(key: "bull_trend", name: "趋势", description: "趋势跟随策略", icon: "📈"),
        .init(key: "chan_theory", name: "缠论", description: "缠中说禅", icon: "🔮"),
        .init(key: "wave_theory", name: "波浪", description: "艾略特波浪", icon: "🌊"),
        .init(key: "box_oscillation", name: "箱体", description: "箱体震荡", icon: "📦"),
        .init(key: "emotion_cycle", name: "情绪", description: "市场情绪周期", icon: "💡")
    ]

    public static let tasks: [TaskInfo] = [
        TaskInfo(id: "t-1", stockCode: "600519", stockName: "贵州茅台",
                 status: "processing", progress: 62, message: "抓取技术指标",
                 createdAt: "刚刚", analysisPhase: "postmarket"),
        TaskInfo(id: "t-2", stockCode: "00700", stockName: "腾讯控股",
                 status: "pending", progress: 0, message: "排队中",
                 createdAt: "刚刚", analysisPhase: "intraday")
    ]

    public static let chatSessions: [ChatSessionInfo] = [
        .init(id: "s-1", title: "茅台追问", messageCount: 8, updatedAt: "2 小时前"),
        .init(id: "s-2", title: "腾讯回调讨论", messageCount: 12, updatedAt: "昨天")
    ]

    // MARK: - Portfolio

    public static let portfolio = PortfolioSnapshot(
        totalEquity: 523_180,
        totalMarketValue: 491_730,
        cash: 31_450,
        dailyPnl: 3_212,
        dailyPnlPct: 0.62,
        positions: [
            Position(stockCode: "600519", stockName: "贵州茅台", quantity: 100,
                     avgCost: 1520, marketValue: 168_000, pnl: 16_000, pnlPct: 10.5, weight: 0.42),
            Position(stockCode: "00700", stockName: "腾讯控股", quantity: 200,
                     avgCost: 410, marketValue: 77_040, pnl: -4_960, pnlPct: -6.0, weight: 0.22),
            Position(stockCode: "AAPL", stockName: "Apple Inc", quantity: 300,
                     avgCost: 175.20, marketValue: 57_690, pnl: 5_130, pnlPct: 9.8, weight: 0.18)
        ],
        sectorAllocation: [
            SectorWeight(sector: "白酒消费", weight: 0.42),
            SectorWeight(sector: "科技互联", weight: 0.22),
            SectorWeight(sector: "新能源", weight: 0.18),
            SectorWeight(sector: "医药", weight: 0.12),
            SectorWeight(sector: "现金", weight: 0.06)
        ]
    )

    public static let portfolioRisk = PortfolioRisk(
        maxDrawdown: -8.4,
        stopLossLine: 480_000,
        analysisCoverage: 0.92,
        alerts: ["腾讯仓位接近 -6% 止损线", "整体回撤距上限仍有 4.2%"]
    )

    // MARK: - Decision Signals

    public static let decisionSignals: [DecisionSignal] = [
        .init(id: "ds-1", stockCode: "600519", stockName: "贵州茅台",
              action: .buy, actionLabel: "买入", confidence: 0.78,
              entry: 1580, stopLoss: 1520, target: 1780,
              phase: "postmarket", status: "active",
              createdAt: "2 小时前", sourceReportId: "h1"),
        .init(id: "ds-2", stockCode: "00700", stockName: "腾讯控股",
              action: .watch, actionLabel: "观望", confidence: 0.62,
              entry: nil, stopLoss: nil, target: nil,
              phase: "intraday", status: "closed",
              createdAt: "昨天", sourceReportId: "h2"),
        .init(id: "ds-3", stockCode: "NVDA", stockName: "NVIDIA",
              action: .reduce, actionLabel: "减仓", confidence: 0.71,
              entry: 130, stopLoss: 138, target: 118,
              phase: "premarket", status: "active",
              createdAt: "昨天", sourceReportId: nil),
        .init(id: "ds-4", stockCode: "AAPL", stockName: "Apple",
              action: .hold, actionLabel: "持有", confidence: 0.65,
              entry: nil, stopLoss: 175, target: nil,
              phase: "postmarket", status: "expired",
              createdAt: "3 天前", sourceReportId: nil)
    ]

    public static let decisionStats = DecisionSignalStats(total: 126, hit: 52, miss: 30, hitRate: 0.635)

    // MARK: - Alerts

    public static let alertRules: [AlertRule] = [
        AlertRule(id: "a-1", name: "茅台跌破 1,520", alertType: "price_threshold",
                  severity: "critical", target: "600519", enabled: true, channels: 4),
        AlertRule(id: "a-2", name: "自选股 5% 异动", alertType: "watchlist",
                  severity: "warning", target: "watchlist", enabled: true, channels: 2),
        AlertRule(id: "a-3", name: "持仓亏损 -8%", alertType: "portfolio_holdings",
                  severity: "critical", target: "portfolio", enabled: true, channels: 3),
        AlertRule(id: "a-4", name: "大盘 RSI < 30", alertType: "market",
                  severity: "info", target: "market", enabled: false, channels: 1)
    ]

    public static let alertTriggers: [AlertTrigger] = [
        AlertTrigger(id: "t-1", ruleName: "NVIDIA -3.2% 异动", stockCode: "NVDA",
                     triggeredAt: "2 小时前", severity: "critical", status: "delivered",
                     message: "推送 ✓ Telegram + 飞书"),
        AlertTrigger(id: "t-2", ruleName: "茅台日内 +2.5%", stockCode: "600519",
                     triggeredAt: "3 小时前", severity: "warning", status: "delivered",
                     message: "推送 ✓"),
        AlertTrigger(id: "t-3", ruleName: "大盘 RSI 超买", stockCode: nil,
                     triggeredAt: "昨天 14:30", severity: "info", status: "suppressed",
                     message: "静默（冷却中）")
    ]

    // MARK: - RunFlow

    public static let runFlow: RunFlow = RunFlow(
        traceId: "8f3a0c",
        totalDurationMs: 258_000,
        overallStatus: "normal",
        nodes: [
            RunFlowNode(id: "quote", label: "行情", status: "success", durationMs: 320, detail: "实时报价"),
            RunFlowNode(id: "tech", label: "技术指标", status: "success", durationMs: 1200, detail: "MA/MACD"),
            RunFlowNode(id: "fundamentals", label: "财报", status: "success", durationMs: 880, detail: "Q1 数据"),
            RunFlowNode(id: "sector", label: "板块", status: "fallback", durationMs: 60, detail: "缓存命中"),
            RunFlowNode(id: "news", label: "新闻", status: "success", durationMs: 1500, detail: "8 条"),
            RunFlowNode(id: "sentiment", label: "情绪", status: "success", durationMs: 200, detail: nil),
            RunFlowNode(id: "llm", label: "LLM", status: "success", durationMs: 128_000, detail: "gpt-4o · 5,299 tokens"),
            RunFlowNode(id: "report", label: "报告", status: "success", durationMs: 80, detail: "已生成")
        ],
        edges: [
            .init(from: "quote", to: "tech"),
            .init(from: "tech", to: "fundamentals"),
            .init(from: "fundamentals", to: "news"),
            .init(from: "sector", to: "news"),
            .init(from: "news", to: "sentiment"),
            .init(from: "sentiment", to: "llm"),
            .init(from: "llm", to: "report")
        ]
    )

    public static let markdownReport: String = """
    # 贵州茅台 个股深度分析

    **600519.SH · 完整报告**

    ## 一、操作建议

    综合行情、基本面、资金面三方面信号，**给出"买入"评级**，置信度 0.78。建议在 1,580–1,620 区间分批建仓，仓位上限 30%，破位 1,520 严格止损。

    ## 二、技术面

    日线收盘 1,680 元，**+1.23%**。MACD 已在零轴上方运行 18 个交易日，DIF 与 DEA 形成持续金叉。

    - 5 日均线：1,648（多头排列）
    - 10 日均线：1,612
    - 20 日均线：1,565
    - 200 日均线：1,498（中期支撑）

    ## 三、基本面

    Q1 2026 营业收入同比 **+13.2%**，归母净利润 **+15.8%**。经营性现金流环比改善，估值 PE-TTM 26x 低于近 5 年中位数。

    ## 四、风险提示

    - 短期 1,720 压力位若放量突破，可上看 1,800
    - 跌破 1,520 视为多头结构性破坏，须执行止损
    """

    // MARK: - Screening

    public static let hotspots: [Hotspot] = [
        Hotspot(topic: "AI 算力", count: 12, changePct: 8.2,
                trend: [10, 12, 14, 13, 18, 16, 20, 24]),
        Hotspot(topic: "机器人", count: 9, changePct: 5.4,
                trend: [8, 10, 9, 12, 11, 14, 13, 16]),
        Hotspot(topic: "新能源", count: 22, changePct: -2.1,
                trend: [22, 20, 19, 17, 16, 18, 15, 14]),
        Hotspot(topic: "医药", count: 15, changePct: 3.8,
                trend: [10, 11, 13, 12, 14, 13, 15, 16])
    ]

    public static let strategies: [ScreeningStrategy] = [
        .init(key: "breakout", name: "短线突破", description: "20 日新高 + 量能放大"),
        .init(key: "trend_follow", name: "趋势跟随", description: "MA 多头排列 + RSI 健康"),
        .init(key: "mean_reversion", name: "均值回归", description: "RSI < 30 + 布林下轨"),
        .init(key: "high_dividend", name: "高股息", description: "股息率 > 4%")
    ]

    public static let candidates: [ScreeningCandidate] = [
        ScreeningCandidate(stockCode: "603019", stockName: "中科曙光", score: 92, changePct: 5.2, theme: "AI 算力"),
        ScreeningCandidate(stockCode: "688256", stockName: "寒武纪", score: 88, changePct: 7.8, theme: "AI 算力"),
        ScreeningCandidate(stockCode: "688041", stockName: "海光信息", score: 85, changePct: 3.1, theme: "AI 算力"),
        ScreeningCandidate(stockCode: "300750", stockName: "宁德时代", score: 78, changePct: -1.2, theme: "新能源"),
        ScreeningCandidate(stockCode: "002415", stockName: "海康威视", score: 75, changePct: 1.4, theme: "智能硬件")
    ]

    // MARK: - Backtest

    public static let backtestPerformance = BacktestPerformance(
        directionalAccuracy: 0.684, winRate: 0.612, avgReturn: 0.0234, stopLossRate: 0.082,
        phaseDistribution: [
            PhaseDistribution(phase: "盘前", count: 28),
            PhaseDistribution(phase: "盘中", count: 52),
            PhaseDistribution(phase: "盘后", count: 40),
            PhaseDistribution(phase: "未知", count: 12)
        ]
    )

    public static let backtestResults: [BacktestResult] = [
        .init(id: "br-1", stockCode: "600519", stockName: "贵州茅台", date: "06-22", phase: "盘后",
              predicted: "多", actual: "多", outcome: "命中"),
        .init(id: "br-2", stockCode: "00700", stockName: "腾讯", date: "06-21", phase: "盘中",
              predicted: "空", actual: "多", outcome: "未命中"),
        .init(id: "br-3", stockCode: "AAPL", stockName: "Apple", date: "06-20", phase: "盘前",
              predicted: "多", actual: nil, outcome: "止盈"),
        .init(id: "br-4", stockCode: "NVDA", stockName: "NVIDIA", date: "06-19", phase: "盘中",
              predicted: "空", actual: "空", outcome: "命中")
    ]

    // MARK: - Usage

    public static let usageDashboard = UsageDashboard(
        totalTokens: 1_280_000, totalCalls: 2148,
        promptTokens: 980_000, completionTokens: 300_000,
        modelStats: [
            UsageModelStat(model: "gpt-4o", tokens: 792_000, weight: 0.62),
            UsageModelStat(model: "claude-3.5", tokens: 308_000, weight: 0.24),
            UsageModelStat(model: "deepseek", tokens: 152_000, weight: 0.12),
            UsageModelStat(model: "gemini", tokens: 28_000, weight: 0.02)
        ],
        callTypes: [
            UsageCallType(type: "个股分析", count: 1160, weight: 0.54),
            UsageCallType(type: "AI 对话", count: 644, weight: 0.30),
            UsageCallType(type: "大盘点评", count: 344, weight: 0.16)
        ],
        recent: [
            UsageRecord(id: "r-1", time: "14:32", type: "个股分析", model: "gpt-4o", promptTokens: 4200, completionTokens: 1100),
            UsageRecord(id: "r-2", time: "14:21", type: "对话", model: "claude-3.5", promptTokens: 2800, completionTokens: 600),
            UsageRecord(id: "r-3", time: "14:08", type: "大盘点评", model: "gpt-4o", promptTokens: 6500, completionTokens: 2000)
        ]
    )

    // MARK: - LLM / Notification / Scheduler / Env

    public static let llmChannels: [LLMChannel] = [
        LLMChannel(id: "ch-1", name: "OpenAI 主通道", provider: "openai",
                   baseURL: "https://api.openai.com/v1",
                   apiKeyMasked: "sk-•••••••••••••",
                   models: ["gpt-4o", "gpt-4o-mini"], isPrimary: true, status: "online"),
        LLMChannel(id: "ch-2", name: "Anthropic", provider: "anthropic",
                   baseURL: "https://api.anthropic.com",
                   apiKeyMasked: "sk-ant-•••••••",
                   models: ["claude-3.5-sonnet"], isPrimary: false, status: "online"),
        LLMChannel(id: "ch-3", name: "DeepSeek", provider: "deepseek",
                   baseURL: "https://api.deepseek.com",
                   apiKeyMasked: "sk-ds-•••••••",
                   models: ["deepseek-chat"], isPrimary: false, status: "online"),
        LLMChannel(id: "ch-4", name: "Ollama (本地)", provider: "ollama",
                   baseURL: "http://localhost:11434",
                   apiKeyMasked: "—",
                   models: [], isPrimary: false, status: "offline")
    ]

    public static let notificationChannels: [NotificationChannel] = [
        NotificationChannel(id: "n-1", name: "Telegram · 主", kind: "telegram",
                            target: "@dsa_alert_bot", status: "online", lastSentAt: "2 小时前"),
        NotificationChannel(id: "n-2", name: "飞书 · 群机器人", kind: "feishu",
                            target: "投研群", status: "online", lastSentAt: "1 天前"),
        NotificationChannel(id: "n-3", name: "邮件 · SMTP", kind: "email",
                            target: "smtp.gmail.com:587", status: "untested", lastSentAt: nil),
        NotificationChannel(id: "n-4", name: "企业微信", kind: "wecom",
                            target: "webhook", status: "failed", lastSentAt: "—")
    ]

    public static let schedulerStatus = SchedulerStatus(
        enabled: true,
        nextRun: "明天 09:00",
        lastRun: "今天 09:00",
        lastRunStatus: "success",
        times: [
            ScheduledTime(id: "sc-1", time: "09:00", enabled: true, scope: "盘前 · 全市场分析 · 推送"),
            ScheduledTime(id: "sc-2", time: "12:30", enabled: true, scope: "午间 · 自选股"),
            ScheduledTime(id: "sc-3", time: "16:00", enabled: true, scope: "盘后 · 大盘点评 + 个股"),
            ScheduledTime(id: "sc-4", time: "21:30", enabled: false, scope: "夜盘 · 美股盘前")
        ]
    )

    public static let envBackupPreview = EnvBackupPreview(
        added: ["LLM_PROVIDER_OPENAI_KEY"],
        modified: [
            "SCHEDULE_TIMES: 09:00,16:00 → 09:00,12:30,16:00",
            "NOTIFICATION_TELEGRAM_TOKEN: ••• → ••• (变更)"
        ],
        removed: ["DEPRECATED_FLAG_X"]
    )

    public static let intelligentImportItems: [IntelligentImportItem] = [
        IntelligentImportItem(stockCode: "600519", stockName: "贵州茅台", market: "上交所", confidence: 0.95, selected: true),
        IntelligentImportItem(stockCode: "000858", stockName: "五粮液", market: "深交所", confidence: 0.93, selected: true),
        IntelligentImportItem(stockCode: "600036", stockName: "招商银行", market: "上交所", confidence: 0.91, selected: true),
        IntelligentImportItem(stockCode: "601012", stockName: "隆基绿能", market: nil, confidence: 0.72, selected: true),
        IntelligentImportItem(stockCode: "?", stockName: "XX 科技", market: nil, confidence: 0.32, selected: false)
    ]
}

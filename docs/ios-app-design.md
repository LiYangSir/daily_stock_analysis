# iOS 原生 App 设计方案

> 本文档是 iOS 原生 App 的设计与协作真源。后端零改动，全部复用现有 `/api/v1/*`（cookie 鉴权 `dsa_session`，SSE 任务流）。
>
> 维护守则：每次重大设计调整须更新本文件并在 `docs/CHANGELOG.md` 的 `[Unreleased]` 段追加一行扁平条目。

## 1. 概述

- **定位**：股票智能分析系统的 iOS 原生客户端，覆盖 A 股 / 港股 / 美股 / 日股 / 韩股，对齐 Web/Desktop 现有能力。
- **平台**：iPhone 为主，iPad 通过 `NavigationSplitView` 自适应；不做 watchOS / macOS Catalyst。
- **最低版本**：iOS 16.0（Swift Charts、`URLSession.bytes` AsyncStream、`.searchable`、`.presentationDetents` 全部内置）。
- **技术栈**：SwiftUI + Swift Concurrency + `URLSession`，依赖管理用 SwiftPM；Markdown 渲染用 [`swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui)（与 Web 端 `react-markdown + remark-gfm` 同源 GFM）。
- **与后端关系**：仅消费 `/api/v1/*`，不引入新的服务端接口；如需 APNs，未来通过 `bot/platforms/` 新增平台桥接，不在本期范围。

## 2. 设计哲学

设计参考苹果内置 App，目标是 **「克制、信息密度、排版纪律」**：

| 来源 App | 借鉴点 | 落地位置 |
| --- | --- | --- |
| Stocks | 顶部大数字 + Sparkline；列表项极简（名/码/价/涨跌胶囊）；底部固定新闻 Sheet | 自选股列表、报告详情顶区、底部新闻 Sheet |
| Health | 卡片堆叠的模块化信息架构；颜色仅作分类 tag | 投资组合 / 决策信号汇总 |
| Fitness | 圆环作为唯一视觉锚点 | 情绪指针、组合盈亏环 |
| Wallet | 卡片质感（顶部高光 + 底部柔和阴影），列表纯排版 | 账户切换器 |
| Weather | 沉浸式分组卡（10 日 / 紫外线 / 风力）；模块卡无强边框 | 报告详情按模块卡组织 |
| News | 大标题 + 充分行高 + 摘要灰字 | 报告标题区、资讯列表 |
| Settings | `InsetGrouped` Form；零装饰；图标统一规格 | 设置页 / 系统配置 |
| Mail / Files | 大标题 + 内嵌 `.searchable` | 全局导航规范 |

**核心一句话**：不靠"设计感"，靠**结构清晰 + 系统组件 + 排版纪律**。

## 3. 股票配色规范

中美股票色相反，必须做成用户可选项。

```
设置 > 外观 > 涨跌颜色
  ○ 跟随股票市场（推荐，默认）   A 股 / 港股 红涨；美股 / 日股 / 韩股 绿涨
  ○ 红涨绿跌                    全局红涨
  ○ 绿涨红跌                    全局绿涨
```

色值（与系统语义色对齐，不自定义）：

```
Up     : Color.systemRed       (CN/HK 默认) / .systemGreen (US/JP/KR)
Down   : Color.systemGreen     (CN/HK 默认) / .systemRed   (US/JP/KR)
Flat   : Color.secondary
强调色 : Color.accentColor      (古铜 #B8895A，仅用于交互强调，不用于涨跌)
```

**强约束**：

- 涨跌色只出现在：价格数字、涨跌箭头、Sparkline、列表右侧胶囊
- Action Chip（buy / hold / sell）**不用**涨跌色，用中性灰 + 文字区分（与 Stocks app 一致）
- 同屏混合涨跌时，各自用各自的 up/down 色，**不做底色强调**
- 强调色只用于：选中态 Tab、链接、关键 CTA 按钮

## 4. 视觉系统

### 4.1 字体（完全跟随系统）

| 用途 | Modifier |
| --- | --- |
| 大数字（价格、涨跌幅） | `.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()` |
| 大标题 | `.largeTitle.bold()`（由 `NavigationStack` 自动管理 inline / large） |
| Section Header | `.footnote.uppercased().foregroundStyle(.secondary)` |
| 报告正文 | `.body`（默认 SF Pro，**不用 Serif**，与系统一致） |
| 元信息（时间、来源） | `.caption.foregroundStyle(.secondary)` |

> 数字与文字混排时，数字一律 `.monospacedDigit()`，对齐感与 Stocks 一致。

### 4.2 排版

- 全局水平边距 16pt
- Section 间距 32pt
- 模块卡内距 16pt
- 大标题与首个内容间距 8pt（系统默认）

### 4.3 列表与卡片

- **优先用** `List(.insetGrouped)` / `Form` —— Settings / Health / Fitness 标准做法
- 自定义模块卡仅用于报告详情，背景 `Color(.secondarySystemGroupedBackground)`，圆角 12，无描边、无阴影
- 分隔线用系统默认（`.listRowSeparator(.visible)`）

### 4.4 材质（克制使用）

- 顶部导航：报告详情等阅读页采用**浮空玻璃返回按钮**（圆形 36pt，`.regularMaterial` + 0.5pt 描边 + 柔和阴影）+ 中央**胶囊标题**，避免传统贴边导航栏与底部胶囊 Tab 视觉打架；列表 / Form 类页面仍用系统默认大标题
- 底部 Tab Bar：**浮空胶囊**（高 64pt，左右 10pt 内距，圆角 999pt 全圆角，`.regularMaterial` 模糊 + saturate(1.4) + 0.5pt 描边 + 柔和阴影）；选中态 = 古铜色文字 / 图标 + 古铜 12% 透明圆形背景，呼应 iOS 26 Liquid Glass 但不滥用
- 底部 Sheet：`.presentationBackground(.regularMaterial)` + `.presentationDetents([.medium, .large])`，Stocks 新闻 Sheet 同款
- 不做：全屏玻璃覆盖、Pill 视差倾斜、自定义折射动效

### 4.5 SF Symbols

- 全部 SF Symbols 6
- Tab Bar：选中填充，未选中线性，颜色 = `accentColor`
- 列表前缀图标：`.foregroundStyle(.secondary)`，`frame(width: 28)`

## 5. 信息架构

底部 5 个 Tab，参考 Stocks / Health 的扁平结构：

| Tab | 主页面 | 二级页 | 后端依赖 |
| --- | --- | --- | --- |
| 行情 | 自选股 + 大盘速览 | 股票详情 / K 线全屏 | `/stocks/watchlist`, `/stocks/{code}/quote`, `/stocks/{code}/history` |
| 分析 | 报告历史 + 快速分析入口 | 报告详情 / 大盘复盘 / 任务流 | `/analysis/*`, `/history/*` |
| 助手 | AI 对话 | 会话列表 / 选股 / 决策信号 | `/agent/*`, `/alphasift/*`, `/decision-signals/*` |
| 组合 | 投资组合总览 | 持仓 / 流水 / 告警 / 回测 / 风险 | `/portfolio/*`, `/alerts/*`, `/backtest/*` |
| 我的 | 账户 + 设置 | Token 用量 / 系统配置 / 主题 / 涨跌色 | `/auth/*`, `/system/*`, `/usage/*` |

全局元素：

- **顶部任务条**：当存在进行中的分析任务时，吸顶展示 1 行（股名 + 进度），点击展开任务流抽屉；订阅 `/analysis/tasks/stream`
- **全局搜索**：`.searchable` 注入到行情 / 分析两个 Tab，搜索源使用 `/stocks.index.json`（本地 fuzzy 匹配）

### 5.1 21 屏完整清单（与视觉稿一一对应）

视觉稿位于 `docs/assets/ios-mockup/index.html`。

#### 主屏 · 11

| # | 屏幕 | 所属 Tab | ViewModel | 主要 API |
| --- | --- | --- | --- | --- |
| 1 | 登录 / 首次设置 | — | `LoginViewModel` | `GET /auth/status` · `POST /auth/login` |
| 2 | 我的 / 设置主页 | 我的 | `SettingsViewModel` | `GET /auth/status` · `GET /system/config/setup/status` |
| 3 | 行情主页（自选 + StockBar + 历史） | 行情 | `MarketsViewModel` | `GET /stocks/watchlist` · `GET /stocks/{code}/quote` · `GET /history/stocks` · `GET /history` |
| 4 | 提交分析（多股 + 技能 + 参数） | 分析 | `AnalysisSubmitViewModel` | `POST /analysis/analyze` · `POST /analysis/market-review` · SSE `/analysis/tasks/stream` · `GET /agent/skills` |
| 5 | 报告详情（K 线 + MA + MACD + 7 模块卡） | 行情 / 分析 | `ReportDetailViewModel` | `GET /history/{id}` · `GET /history/{id}/news` · `GET /stocks/{code}/history` · `POST /stocks/watchlist/*` |
| 6 | AI 对话 | 助手 | `ChatViewModel` | SSE `/agent/chat/stream` · `GET /agent/skills` · `GET /agent/chat/sessions` · `DELETE /agent/chat/sessions/{id}` · `POST /agent/chat/send` |
| 7 | 投资组合（账户 + 圆环 + 持仓） | 组合 | `PortfolioViewModel` | `GET /portfolio/snapshot` · `GET /portfolio/risk` · `GET /portfolio/accounts` · `POST /portfolio/fx/refresh` |
| 8 | 决策信号（过滤 + 统计 + 详情抽屉） | 组合 | `DecisionSignalsViewModel` | `GET /decision-signals` · `GET /decision-signals/outcomes/stats` · `PUT /{id}/feedback` · `PATCH /{id}/status` |
| 9 | AlphaSift 选股（热点 + 策略 + 候选） | 分析 | `ScreeningViewModel` | `GET /alphasift/status` · `GET /alphasift/hotspots` · `GET /alphasift/strategies` · `POST /alphasift/screen/tasks` · `GET /alphasift/screen/tasks/{id}` |
| 10 | 回测（参数 + 性能 + 阶段 + 结果） | 分析 | `BacktestViewModel` | `POST /backtest/run` · `GET /backtest/results` · `GET /backtest/performance` |
| 11 | 预警（规则 + 触发历史 + 通知记录） | 组合 | `AlertsViewModel` | `GET/POST/PATCH/DELETE /alerts/rules` · `POST /alerts/rules/{id}/{enable\|disable\|test}` · `GET /alerts/triggers` · `GET /alerts/notifications` |

#### 系统类 · 2

| # | 屏幕 | 所属 Tab | ViewModel | 主要 API |
| --- | --- | --- | --- | --- |
| 12 | Token 用量 | 我的 | `UsageViewModel` | `GET /usage/dashboard` |
| 13 | LLM 通道编辑（设置子页） | 我的 → 设置 | `LLMChannelViewModel` | `POST /system/config/llm/test-channel` · `POST /system/config/llm/discover-models` · `PUT /system/config` |

#### 设置子页 · 4

| # | 屏幕 | 入口 | ViewModel | 主要 API |
| --- | --- | --- | --- | --- |
| 14 | 通知通道（14 渠道列表 + 测试发送） | 我的 → 设置 | `NotificationChannelsViewModel` | `POST /system/config/notification/test-channel` · `PUT /system/config` |
| 15 | 定时调度（多时间任务 + 立即运行） | 我的 → 设置 | `SchedulerViewModel` | `GET /system/scheduler/status` · `POST /system/scheduler/run-now` · `PUT /system/config` |
| 16 | 智能导入自选（图片 OCR / CSV / 文本） | 我的 → 设置 / 行情 → + | `IntelligentImportViewModel` | `POST /stocks/extract-from-image` · `POST /stocks/parse-import` · `POST /stocks/watchlist/add` |
| 17 | 认证 + 配置备份（密码 / .env 导入导出） | 我的 → 设置 | `AuthBackupViewModel` | `POST /auth/settings` · `POST /auth/change-password` · `GET /system/config/export` · `POST /system/config/import` · `POST /system/config/validate` |

#### 抽屉浮层 · 4（`.sheet` + `.presentationDetents`）

| # | 屏幕 | 触发位置 | ViewModel | 主要 API |
| --- | --- | --- | --- | --- |
| 18 | RunFlow（任务流可视化） | 报告详情 / 顶部任务条 | `RunFlowViewModel` | `GET /history/{id}/flow` · `GET /analysis/tasks/{id}/flow` |
| 19 | Markdown 全文（Serif 阅读） | 报告详情 → 分享 | `MarkdownDrawerViewModel` | `GET /history/{id}/markdown` |
| 20 | 个股历史趋势（曲线 + Action 散点） | 报告详情 → 历史趋势 | `StockHistoryTrendViewModel` | `GET /history?stock_code=...&days=...` |
| 21 | CSV 导入向导（3 步：选券商 → 预览 → 提交） | 投资组合 → CSV 导入 | `CSVImportWizardViewModel` | `GET /portfolio/imports/csv/brokers` · `POST /portfolio/imports/csv/parse` · `POST /portfolio/imports/csv/commit` |

#### 共享子组件（跨多屏复用）

- `TaskPill`（顶部任务条，全局）
- `KLineChart` / `IndicatorSubChart` / `IndicatorTabs`（屏 5）
- `ModuleCard`（屏 5、7、8、10）
- `WatchlistRow` / `ChangeChip`（屏 3、5、20）
- `ActionChip`（屏 3、5、8、20）
- `SegmentedControl`（屏 4、7、8、9、10、11、13、14、20、21）
- `FloatingBackButton` + `CapsuleTitle`（屏 5、6、12-21 所有二级页）
- `CapsuleTabBar`（主屏 1-12）
- `Sheet` 容器（屏 18-21）

## 6. 关键页面设计

### 6.1 行情主页（参考 Stocks 主屏）

```
┌─────────────────────────────────────┐
│  行情                          [+]  │  ← Large Title
├─────────────────────────────────────┤
│  🔍  搜索股票/代码                   │  ← .searchable
├─────────────────────────────────────┤
│  关注                                │
│  贵州茅台   600519   ¥1,680.00 [+1.23%] │  ← 胶囊用 up 色
│  腾讯控股   00700    HK$385.20 [-0.85%] │
│  Apple Inc  AAPL     $192.30 [+0.42%]  │  ← 美股默认绿涨
├─────────────────────────────────────┤
│  最近分析                            │
│  贵州茅台    2 小时前       买入     │
│  ...                                 │
└─────────────────────────────────────┘
```

**组件**：`PriceCell` / `ChangeChip` / `SearchBar` / `WatchlistRow`
**数据**：列表静态读 `/stocks/watchlist`；价/涨跌按需调 `/stocks/{code}/quote`，下拉刷新触发批量

### 6.2 报告详情（参考 Stocks 个股详情 + Weather 模块卡）

```
┌─────────────────────────────────────┐
│ ◯  贵州茅台 · 600519          ◯···  │  ← 浮空玻璃返回 + 中央胶囊标题
├─────────────────────────────────────┤
│  ¥1,680.00                           │  ← 38pt rounded
│  ▲ +20.50  +1.23%                    │  ← 涨跌色
│                                      │
│  MA5 1,648  MA10 1,612  MA20 1,565   │  ← 图例（金/蓝/紫）
│  ┃┃┃╱╲┃╱╲╱╲┃╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱╲╱     │  ← 蜡烛 + 3 均线
│  1日 5日 1月 [3月] 1年 全部           │  ← 时段切换
│  [MACD] KDJ RSI BOLL VOL              │  ← 指标切换胶囊
│  DIF +18.4  DEA +12.0  MACD +12.7    │
│  ▎▎▎▍▍▍▌▌▍▌▍▎▎▎▎▎▎▎▎▎▎▎▎▎▎▎▎▎     │  ← MACD 柱 + DIF/DEA 双线
├─────────────────────────────────────┤
│  ┌─ 操作建议 ─────────────────────┐  │
│  │ 买入 · 置信 0.78                │  │
│  │ 摘要正文…（3 行 truncate）      │  │
│  └─────────────────────────────────┘  │
│  ┌─ 策略点位 ─────────────────────┐  │
│  │ 理想买入 1,580   止损   1,520   │  │
│  │ 次优买入 1,620   止盈   1,780   │  │
│  └─────────────────────────────────┘  │
│  ┌─ 情绪 ─────────────────────────┐  │
│  │ ●━━━━━━━○━━━ 78 / 100 乐观      │  │
│  └─────────────────────────────────┘  │
│  ┌─ 数据来源 ─────────────────────┐  │
│  │ 实时行情 ✓  财报 ✓  新闻 8 条   │  │
│  └─────────────────────────────────┘  │
├─────────────────────────────────────┤
│  ↑ 上拉查看相关新闻                  │  ← 底部固定 Sheet（medium/large）
│       ┌─ 浮空胶囊 Tab Bar ─┐         │
└──────[行情][分析][助手][组合][我的]──┘
```

**组件**：`FloatingBackButton` / `PriceCell` / `KLineChart` / `IndicatorTabs` / `IndicatorSubChart` / `PeriodSegment` / `ModuleCard` / `SentimentDial` / `NewsSheet` / `CapsuleTabBar`
**数据**：报告体来自 `/history/{record_id}`；K 线来自 `/stocks/{code}/history?period=daily&days=120`（多取 30 根用于均线 warm-up）；新闻来自 `/history/{record_id}/news?limit=8`
**指标计算**：MA / MACD / KDJ / RSI / BOLL / VOL 全部**客户端计算**，避免后端改造；输入为 `KLineData[]` 数组
**Action**：分享 / 复制 Markdown（`/history/{record_id}/markdown`）/ 再分析（`force_refresh=true`）/ 跳 Chat 追问

### 6.3 投资组合（参考 Health 摘要）

```
┌─────────────────────────────────────┐
│  组合                        [账户]  │
├─────────────────────────────────────┤
│  ¥523,180.00                         │  ← Display
│  ↑ ¥3,212  +0.62%  今日              │  ← 涨跌色仅前缀箭头
├─────────────────────────────────────┤
│  ◯ Pie Chart 仓位占比                │  ← Swift Charts SectorMark
├─────────────────────────────────────┤
│  持仓        →                       │  ← 子页
│  现金台账    →                       │
│  风险报告    →                       │
│  告警规则    →                       │
└─────────────────────────────────────┘
```

**数据**：`/portfolio/snapshot`、`/portfolio/risk`、`/alerts/rules`

### 6.4 AI 对话（参考 Messages）

- 用户气泡：右对齐，`accentColor` 背景，白字
- 助手气泡：左对齐，`Color(.systemGray6)` 背景，主文字色
- 工具调用：行内 `Label`（"📡 fetching news…" 级别极简）
- SSE：调 `/agent/chat/stream`（POST + `URLSession.bytes(for:)`），事件 `thinking / tool_start / tool_done / generating / done / error`

### 6.5 决策信号

- 顶部过滤改为 BottomSheet（避免横向拥挤）
- 卡片：股 + Action（中性 chip）+ 来源报告链 + 反馈 👍/👎（`PUT /decision-signals/{id}/feedback`）
- 点击进入：详情 + outcomes + 状态切换（`PATCH /{id}/status`）

### 6.6 设置（完全 Settings App 风格）

`Form` + `Section`：

- 账户：登录态 / 修改密码 / 退出
- 外观：主题（亮/暗/系统）、UI 语言（zh/en）、**涨跌颜色方案**
- 服务：服务器地址（私有部署，存 Keychain）、连接测试
- 数据：缓存清理、报告导出
- 高级（只读 + 跳浏览器）：LLM 通道、通知通道、调度器
- 关于：版本、开源协议、反馈

## 7. 核心组件库（DesignSystem/）

| 组件 | 形态 | 关键属性 |
| --- | --- | --- |
| `PriceCell` | 大数字 + 涨跌 | `price / change / changePct / market` |
| `ChangeChip` | 列表右侧胶囊 | `pct / market` |
| `Sparkline` | 列表内嵌单线缩略图 | `points / market`，无网格、无坐标，仅用于自选股行内 |
| `KLineChart` | 报告详情主图 | `bars / period / overlays`；蜡烛 + MA5/MA10/MA20 三条均线（金/蓝/紫）+ 价格刻度 + 当前价虚线 + 网格虚线（A 股惯例：红涨绿跌；美股自动反转） |
| `IndicatorSubChart` | 主图下方副图 | `kind: .macd / .kdj / .rsi / .boll / .vol`，默认 MACD（柱 + DIF + DEA） |
| `IndicatorTabs` | 副图切换胶囊条 | `[MACD, KDJ, RSI, BOLL, VOL]`，选中态古铜底色 |
| `PeriodSegment` | 时段切换 | `[1日, 5日, 1月, 3月, 1年, 全部]` |
| `CapsuleTabBar` | 浮空胶囊 Tab | 5 项；选中态古铜文字 + 12% 透明圆形高亮 |
| `FloatingBackButton` | 浮空玻璃返回按钮 | 圆形 36pt，左上角悬浮，配中央胶囊标题 |
| `SectionHeader` | Footnote + 大写 | `title / accessory` |
| `ModuleCard` | 圆角 12 容器 | `title / @ViewBuilder content` |
| `SentimentDial` | 水平刻度 0-100 | `score / label` |
| `TaskPill` | 顶部任务条 | `taskName / progress / onTap` |
| `ActionChip` | buy/hold/sell 中性胶囊 | `action`（不携涨跌色） |
| `WatchlistRow` | 名/码/价/胶囊 | `quote / market` |
| `NewsSheet` | 底部固定 Sheet | `items / detents` |

每个组件唯一规则：**最多一个强调色 + 一种材质 + 一种字号**，超过即降级。

## 8. 状态机与数据流

### 8.1 分析任务（推荐 SSE 主路径 + 轮询 fallback）

```
[Idle]
  └─ user submit ──► POST /analysis/analyze (async_mode=true)
                              │
                              ▼
                       [Pending] (task_id)
                              │
                       订阅 /analysis/tasks/stream (SSE)
                              │
   ┌──────── task_progress ───┤
   ▼                          │
[Running] ──── task_failed ──► [Failed]
   │                          │
   └─ task_completed ────────►[Completed]──► 拉 /history/{record_id}
```

- SSE 主路径：单连接全局共享（`URLSession.bytes(for:)` AsyncStream）
- 弱网降级：检测到连接断开 5s 未恢复 → 切换为每 2s 轮询 `/analysis/status/{task_id}`（与 Web 端 fallback 一致）
- 重连：指数退避（1s → 2s → 4s → 8s，封顶 30s），保留 `last_event_id`（若服务端支持）
- Duplicate（409）：直接接管 `existing_task_id` 显示进度

### 8.2 鉴权流

```
启动 ──► GET /auth/status
   │
   ├─ authEnabled=false ──────────────► 主界面
   ├─ setupState=no_password ─► 首次设置（password + passwordConfirm）
   └─ 否则 ─► 登录页（password）
                  │
                  ▼ POST /auth/login
            cookie 自动入 HTTPCookieStorage
                  │
                  ▼
              主界面
                  │
                  ▼ 任意 401 ─────► 弹登录页（保留路由现场）
```

- `URLSessionConfiguration.default.httpCookieAcceptPolicy = .always`
- 登出 = `POST /auth/logout`，cookie 自动清理
- 私有部署 baseURL 存 Keychain；密码不本地缓存

## 9. 后端 API 映射表

| iOS 页面 | 端点 | 方法 | 模型 | 错误码 |
| --- | --- | --- | --- | --- |
| 登录 | `/auth/status` `/auth/login` `/auth/logout` | GET/POST | `AuthStatus` | `password_mismatch / invalid_password / rate_limited` |
| 行情列表 | `/stocks/watchlist` `/stocks/{code}/quote` | GET | `StockQuote` | `not_found` |
| K 线 | `/stocks/{code}/history` | GET | `KLineData[]` | `unsupported_period`（仅 daily 安全） |
| 提交分析 | `/analysis/analyze` | POST | `AnalyzeAsyncResponse` | `duplicate_task / validation_error` |
| 任务流 | `/analysis/tasks/stream` | SSE | `TaskEvent` | 网络错误 → 轮询 fallback |
| 任务状态 | `/analysis/status/{task_id}` | GET | `TaskStatus` | `not_found` |
| 大盘复盘 | `/analysis/market-review` | POST | `AnalyzeAsyncResponse` | `duplicate_market_review` |
| 报告详情 | `/history/{record_id}` `/history/{record_id}/markdown` `/history/{record_id}/news` | GET | `AnalysisReport` | `not_found` |
| AI 对话 | `/agent/chat/stream` | SSE-POST | `ChatEvent` | 网络错误 → 重试 |
| 选股 | `/alphasift/screen/tasks` `/alphasift/screen/tasks/{task_id}` | POST/GET | `ScreenTask` | `alphasift_screen_task_not_found` |
| 决策信号 | `/decision-signals` `/decision-signals/{id}/feedback` | GET/PUT | `DecisionSignal` | `unauthorized` |
| 投资组合 | `/portfolio/snapshot` `/portfolio/risk` | GET | `PortfolioSnapshot` | `portfolio_busy` |
| 持仓再分析 | `/portfolio/positions/{symbol}/analysis` | POST | `AnalyzeAsyncResponse` | `ambiguous_position_account` |
| 告警 | `/alerts/rules` `/alerts/triggers` | GET/POST/PATCH/DELETE | `AlertRule` | `unsupported_alert_type` |
| 回测 | `/backtest/run` 等 | POST/GET | `BacktestResult` | — |
| Token 用量 | `/usage/dashboard` | GET | `UsageDashboard` | — |
| 系统配置 | `/system/config*` `/system/scheduler/*` | GET/POST/PUT | `SystemConfig` | `config_version_conflict` |

错误统一映射 `{error, message}` → `enum APIError`；任意 401 拦截 → 路由登录页。

## 10. 本地化与暗色模式

- 全部字符串走 `Localizable.strings`，zh / en 双语；可写脚本一次性从 Web `apps/dsa-web/src/i18n/uiText.ts` 同步术语
- 暗色背景纯黑 `#000`（OLED 省电 + 模块卡对比更准）
- 强调色暗色态略提亮至 `#D4A37B`
- Dynamic Type 全支持，价格大字号上限到 AX2

## 11. 动效与触感反馈

- 标准 spring：`.spring(response: 0.45, dampingFraction: 0.85)`
- 列表 → 详情：`matchedGeometryEffect`
- 触感：`.sensoryFeedback(.selection, trigger:)` 仅用于 Tab 切换、Chip 选中、Toolbar 操作
- **不做**：CoreMotion 视差、彩虹渐变、霓虹光晕、自定义阴影动画

## 12. 降级策略

| 维度 | iOS 16-25 | iOS 26+ |
| --- | --- | --- |
| 顶部 Sheet | `.presentationBackground(.regularMaterial)` | 同左（不用 `.glassEffect`，避免破坏克制语言） |
| Tab Bar | 系统默认 | 系统默认（自动 Liquid Glass，不主动开启） |
| 数字字体 | `.rounded` | 同左 |
| Markdown | `swift-markdown-ui` | 同左 |
| K 线 | Swift Charts | 同左 |

> 决策：**全版本统一不主动启用 `.glassEffect`**，确保视觉一致；如未来需要，开关收口到 `DesignSystem/Materials.swift`。

## 13. 实施里程碑

| 周 | 交付 |
| --- | --- |
| W1 | 工程脚手架 + `APIClient` + Auth + 行情 Tab 骨架 |
| W2 | 分析提交 + SSE 任务流 + 报告详情（含 Markdown / Sparkline） |
| W3 | AI 对话（SSE）+ 投资组合 + 决策信号 |
| W4 | 选股 / 告警 / 回测 / Token 用量 / 设置 |
| W5 | 本地化、暗色模式、TestFlight 灰度、可观测性（OSLog）|

## 14. 验收 checklist

- [ ] 全部页面优先使用 `List(.insetGrouped)` / `Form`，自定义视图占比 < 30%
- [ ] 涨跌色仅出现在：价格数字、涨跌箭头、K 线蜡烛、Sparkline、列表胶囊、MACD 柱
- [ ] Action Chip / 按钮 / 标题不携涨跌色
- [ ] 设置页提供「涨跌颜色方案」切换，默认按市场自动
- [ ] 底部 Sheet 行为与 Stocks app 一致（始终可拉起 medium/large）
- [ ] 数字一律 `.monospacedDigit()` + `.rounded`
- [ ] 不出现自定义阴影 / 自定义模糊 / 自定义圆角进度条
- [ ] 401 全局拦截到登录页且不丢失现场
- [ ] SSE 中断 5s 自动降级为 2s 轮询
- [ ] 涨跌色方案切换 1s 内全屏生效
- [ ] zh / en 切换无需重启
- [ ] OLED 暗色模式背景纯黑
- [ ] 报告详情顶栏使用浮空玻璃返回按钮 + 中央胶囊标题，与底部胶囊 Tab 视觉风格一致
- [ ] 底部 Tab 为浮空胶囊，宽度自适应内容、不贴边
- [ ] K 线图同时呈现蜡烛 + MA5 / MA10 / MA20 三条均线，图例数字与最新值同步
- [ ] MACD 副图柱形与 0 轴对齐，DIF / DEA 双线渲染顺畅
- [ ] 副图指标可在 MACD / KDJ / RSI / BOLL / VOL 之间切换

## 15. 参考链接

- Apple Human Interface Guidelines — https://developer.apple.com/design/human-interface-guidelines/
- Stocks app（系统内置）—— 主屏 / 个股详情 / 新闻 Sheet 行为
- Health / Fitness app —— 模块卡与圆环
- Settings app —— `Form` + `Section` 范式
- Swift Charts — https://developer.apple.com/documentation/charts
- swift-markdown-ui — https://github.com/gonzalezreal/swift-markdown-ui
- 项目内对照：`apps/dsa-web/src/components/report/ReportSummary.tsx`（报告渲染顺序真源）、`api/v1/schemas/`（响应模型真源）、`apps/dsa-web/src/types/analysis.ts`（前端 Codable 镜像参考）

## 16. 后续动作

- 经用户确认后，在 `apps/dsa-ios/Prototype/` 输出可在 Xcode 16+ 直接运行的 SwiftUI 高保真原型（首页 + 报告详情，含 Mock 数据）
- 视觉对齐确认无误后，再接入真实 `APIClient` 与 SSE
- 工程化（CI、TestFlight）单独立项

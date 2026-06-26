import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PortfolioViewModel: ObservableObject {
    @Published var snapshot: PortfolioSnapshotResponse?
    @Published var risk: PortfolioRiskResponse?
    @Published var loading = false
    @Published var errorMessage: String?

    // 写侧辅助数据
    @Published var accounts: [PortfolioAccountItem] = []
    @Published var brokers: [PortfolioImportBrokerItem] = []
    @Published var recentTrades: [PortfolioTradeListItem] = []

    // 表单 / 弹窗状态
    @Published var sheet: PortfolioSheet?
    @Published var busy = false
    @Published var info: String?

    @Published var accountDraft = AccountDraft()
    @Published var tradeDraft = TradeDraft()
    @Published var cashDraft = CashDraft()
    @Published var corpDraft = CorpActionDraft()
    @Published var csvDraft = CSVDraft()

    enum PortfolioSheet: Identifiable { case account, trade, cash, corp, csv
        var id: Self { self }
    }
    struct AccountDraft { var name = ""; var broker = ""; var market = "cn"; var baseCurrency = "CNY"; var ownerId = "" }
    struct TradeDraft { var accountId: Int? = nil; var symbol = ""; var date = Date(); var side = "buy"; var quantity = ""; var price = ""; var fee = ""; var tax = ""; var note = "" }
    struct CashDraft { var accountId: Int? = nil; var date = Date(); var direction = "in"; var amount = ""; var note = "" }
    struct CorpActionDraft { var accountId: Int? = nil; var symbol = ""; var date = Date(); var actionType = "cash_dividend"; var cashDividendPerShare = ""; var splitRatio = ""; var note = "" }
    struct CSVDraft { var accountId: Int? = nil; var broker = "huatai"; var fileName: String?; var fileData: Data?; var parse: PortfolioImportParseResponse?; var commit: PortfolioImportCommitResponse? }

    func load(env: AppEnvironment) async {
        loading = true; defer { loading = false }
        do {
            self.snapshot = try await env.auth.api.send(.get("/portfolio/snapshot"))
        } catch {
            errorMessage = "/snapshot · " + ((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
        do {
            self.risk = try await env.auth.api.send(.get("/portfolio/risk"))
        } catch {
            let msg = "/risk · " + ((error as? APIError)?.errorDescription ?? error.localizedDescription)
            errorMessage = errorMessage.map { "\($0)\n\(msg)" } ?? msg
        }
        // 写侧辅助数据并发拉取（失败不阻断主快照）
        async let acctTask: PortfolioAccountListResponse? = try? env.auth.api.send(.get("/portfolio/accounts", query: ["include_inactive": "false"]))
        async let brokerTask: PortfolioImportBrokerListResponse? = try? env.auth.api.send(.get("/portfolio/imports/csv/brokers"))
        async let tradesTask: PortfolioTradeListResponse? = try? env.auth.api.send(.get("/portfolio/trades", query: ["page_size": "20"]))
        self.accounts = (await acctTask)?.accounts ?? []
        self.brokers = (await brokerTask)?.brokers ?? []
        self.recentTrades = (await tradesTask)?.items ?? []
    }

    func openSheet(_ s: PortfolioSheet, env: AppEnvironment) {
        errorMessage = nil; info = nil
        switch s {
        case .account: accountDraft = AccountDraft()
        case .trade: tradeDraft = TradeDraft(); tradeDraft.accountId = accounts.first?.id
        case .cash: cashDraft = CashDraft(); cashDraft.accountId = accounts.first?.id
        case .corp: corpDraft = CorpActionDraft(); corpDraft.accountId = accounts.first?.id
        case .csv: csvDraft = CSVDraft(); csvDraft.accountId = accounts.first?.id; csvDraft.broker = brokers.first?.broker ?? "huatai"
        }
        sheet = s
    }

    private func isoDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: d)
    }

    // MARK: 写操作

    /// 新建账户：POST /portfolio/accounts。
    func createAccount(env: AppEnvironment) async {
        guard !accountDraft.name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "请填写账户名称"; return }
        struct Body: Encodable { let name: String; let broker: String?; let market: String; let baseCurrency: String; let ownerId: String? }
        busy = true; defer { busy = false }
        let body = Body(name: accountDraft.name,
                        broker: accountDraft.broker.isEmpty ? nil : accountDraft.broker,
                        market: accountDraft.market, baseCurrency: accountDraft.baseCurrency,
                        ownerId: accountDraft.ownerId.isEmpty ? nil : accountDraft.ownerId)
        do {
            let _: PortfolioAccountItem = try await env.auth.api.send(
                Endpoint(path: "/portfolio/accounts", method: .POST, body: try JSONEncoder.dsa.encode(body)))
            info = "账户已创建"; sheet = nil
            await load(env: env)
        } catch {
            errorMessage = "创建账户失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 录入交易：POST /portfolio/trades。
    func createTrade(env: AppEnvironment) async {
        guard let aid = tradeDraft.accountId else { errorMessage = "请选择账户"; return }
        guard !tradeDraft.symbol.isEmpty else { errorMessage = "请填写股票代码"; return }
        guard let qty = Double(tradeDraft.quantity), let price = Double(tradeDraft.price), qty > 0, price > 0 else { errorMessage = "数量/价格无效"; return }
        struct Body: Encodable {
            let accountId: Int; let symbol: String; let tradeDate: String; let side: String
            let quantity: Double; let price: Double; let fee: Double; let tax: Double; let note: String?
        }
        busy = true; defer { busy = false }
        let body = Body(accountId: aid, symbol: tradeDraft.symbol, tradeDate: isoDate(tradeDraft.date), side: tradeDraft.side,
                        quantity: qty, price: price, fee: Double(tradeDraft.fee) ?? 0, tax: Double(tradeDraft.tax) ?? 0,
                        note: tradeDraft.note.isEmpty ? nil : tradeDraft.note)
        do {
            let _: PortfolioEventCreatedResponse = try await env.auth.api.send(
                Endpoint(path: "/portfolio/trades", method: .POST, body: try JSONEncoder.dsa.encode(body)))
            info = "交易已录入"; sheet = nil
            await load(env: env)
        } catch {
            errorMessage = "录入交易失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 录入现金：POST /portfolio/cash-ledger。
    func createCash(env: AppEnvironment) async {
        guard let aid = cashDraft.accountId else { errorMessage = "请选择账户"; return }
        guard let amt = Double(cashDraft.amount), amt > 0 else { errorMessage = "金额无效"; return }
        struct Body: Encodable { let accountId: Int; let eventDate: String; let direction: String; let amount: Double; let note: String? }
        busy = true; defer { busy = false }
        let body = Body(accountId: aid, eventDate: isoDate(cashDraft.date), direction: cashDraft.direction,
                        amount: amt, note: cashDraft.note.isEmpty ? nil : cashDraft.note)
        do {
            let _: PortfolioEventCreatedResponse = try await env.auth.api.send(
                Endpoint(path: "/portfolio/cash-ledger", method: .POST, body: try JSONEncoder.dsa.encode(body)))
            info = "现金已记录"; sheet = nil
            await load(env: env)
        } catch {
            errorMessage = "记录失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 录入分红/拆股：POST /portfolio/corporate-actions。
    func createCorp(env: AppEnvironment) async {
        guard let aid = corpDraft.accountId else { errorMessage = "请选择账户"; return }
        guard !corpDraft.symbol.isEmpty else { errorMessage = "请填写股票代码"; return }
        let dps = Double(corpDraft.cashDividendPerShare)
        let ratio = Double(corpDraft.splitRatio)
        if corpDraft.actionType == "cash_dividend", dps == nil { errorMessage = "请填写每股分红"; return }
        if corpDraft.actionType == "split_adjustment", ratio == nil { errorMessage = "请填写拆股比例"; return }
        struct Body: Encodable {
            let accountId: Int; let symbol: String; let effectiveDate: String; let actionType: String
            let cashDividendPerShare: Double?; let splitRatio: Double?; let note: String?
        }
        busy = true; defer { busy = false }
        let body = Body(accountId: aid, symbol: corpDraft.symbol, effectiveDate: isoDate(corpDraft.date),
                        actionType: corpDraft.actionType,
                        cashDividendPerShare: corpDraft.actionType == "cash_dividend" ? dps : nil,
                        splitRatio: corpDraft.actionType == "split_adjustment" ? ratio : nil,
                        note: corpDraft.note.isEmpty ? nil : corpDraft.note)
        do {
            let _: PortfolioEventCreatedResponse = try await env.auth.api.send(
                Endpoint(path: "/portfolio/corporate-actions", method: .POST, body: try JSONEncoder.dsa.encode(body)))
            info = "公司行为已记录"; sheet = nil
            await load(env: env)
        } catch {
            errorMessage = "记录失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 删除交易：DELETE /portfolio/trades/{id}。
    func deleteTrade(env: AppEnvironment, id: Int) async {
        try? await env.auth.api.sendVoid(.init(path: "/portfolio/trades/\(id)", method: .DELETE))
        recentTrades.removeAll { $0.id == id }
        await load(env: env)
    }

    /// CSV 解析预览：POST /portfolio/imports/csv/parse（multipart）。
    func parseCsv(env: AppEnvironment) async {
        guard let data = csvDraft.fileData, let name = csvDraft.fileName else { errorMessage = "请选择 CSV 文件"; return }
        busy = true; defer { busy = false }
        let file = UploadFile(field: "file", filename: name, mimeType: "text/csv", data: data)
        do {
            csvDraft.parse = try await env.auth.api.sendMultipart(
                path: "/portfolio/imports/csv/parse", fields: ["broker": csvDraft.broker], files: [file])
            csvDraft.commit = nil
        } catch {
            errorMessage = "解析失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// CSV 提交：POST /portfolio/imports/csv/commit（multipart）。
    func commitCsv(env: AppEnvironment, dryRun: Bool) async {
        guard let aid = csvDraft.accountId else { errorMessage = "请选择账户"; return }
        guard let data = csvDraft.fileData, let name = csvDraft.fileName else { errorMessage = "请选择 CSV 文件"; return }
        busy = true; defer { busy = false }
        let file = UploadFile(field: "file", filename: name, mimeType: "text/csv", data: data)
        do {
            let resp: PortfolioImportCommitResponse = try await env.auth.api.sendMultipart(
                path: "/portfolio/imports/csv/commit",
                fields: ["account_id": "\(aid)", "broker": csvDraft.broker, "dry_run": dryRun ? "true" : "false"],
                files: [file])
            csvDraft.commit = resp
            if !dryRun {
                info = "导入完成：新增 \(resp.insertedCount ?? 0) · 重复 \(resp.duplicateCount ?? 0) · 失败 \(resp.failedCount ?? 0)"
                await load(env: env)
            }
        } catch {
            errorMessage = "导入失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 刷新汇率：POST /portfolio/fx/refresh。
    func refreshFx(env: AppEnvironment) async {
        busy = true; defer { busy = false }
        do {
            let resp: PortfolioFxRefreshResponse = try await env.auth.api.send(
                .init(path: "/portfolio/fx/refresh", method: .POST))
            if resp.refreshEnabled == true {
                info = "汇率已刷新：\(resp.updatedCount ?? 0) 更新 · \(resp.staleCount ?? 0) 仍过期"
            } else {
                info = "汇率刷新未启用：\(resp.disabledReason ?? "—")"
            }
            await load(env: env)
        } catch {
            errorMessage = "刷新失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }
}

public struct PortfolioView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var segment: Int = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CompactPageTitle("组合")
                segmentControl
                Group {
                    switch segment {
                    case 0: PortfolioOverviewView()
                    case 1: ScreeningView()
                    case 2: DecisionSignalsView()
                    default: AlertsView()
                    }
                }
            }
            .background(Color.dsGroupedBackground)
            .hideNavBar()
        }
    }

    private var segmentControl: some View {
        HStack(spacing: 6) {
            segChip("总览", index: 0)
            segChip("选股", index: 1)
            segChip("决策信号", index: 2)
            segChip("预警", index: 3)
        }
        .padding(.horizontal, 16)
    }

    private func segChip(_ title: String, index: Int) -> some View {
        Button {
            withAnimation(.snappy) { segment = index }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(segment == index ? DSColor.accent.opacity(0.14) : Color.gray.opacity(0.1),
                            in: Capsule())
                .foregroundStyle(segment == index ? DSColor.accent : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overview

struct PortfolioOverviewView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = PortfolioViewModel()
    @State private var showCsvPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let snap = vm.snapshot {
                    totalsBlock(snap)
                    actionsCard
                    if let accounts = snap.accounts, accounts.count > 1 {
                        accountsCard(accounts)
                    }
                    if let accounts = snap.accounts {
                        let positions = accounts.flatMap { $0.positions ?? [] }
                        if !positions.isEmpty { positionsCard(positions) }
                    }
                } else if vm.loading {
                    ContentSkeleton(lines: 4)
                } else if let err = vm.errorMessage {
                    ErrorStateView(message: err) { Task { await vm.load(env: env) } }
                } else {
                    // 无账户、无错误：允许新建账户
                    actionsCard
                }
                if !vm.recentTrades.isEmpty { recentTradesCard(vm.recentTrades) }
                if let risk = vm.risk { riskCard(risk) }
                if let info = vm.info {
                    Label(info, systemImage: "checkmark.seal.fill")
                        .font(.footnote).foregroundStyle(.green).padding(.horizontal, 20)
                }
                // 有快照但仍有（如 /risk）错误时，底部小字提示
                if vm.snapshot != nil, let err = vm.errorMessage {
                    Text(err).font(.footnote).foregroundStyle(.orange).padding(.horizontal, 20)
                }
                Color.clear.frame(height: 100)
            }
            .padding(.top, 6)
        }
        .task { await vm.load(env: env) }
        .refreshable { await vm.load(env: env) }
        .sheet(item: $vm.sheet) { s in
            switch s {
            case .account: accountSheetForm()
            case .trade: tradeSheetForm()
            case .cash: cashSheetForm()
            case .corp: corpSheetForm()
            case .csv: csvSheetForm()
            }
        }
        .fileImporter(isPresented: $showCsvPicker, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { vm.errorMessage = "无法读取文件"; return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    vm.csvDraft.fileData = data
                    vm.csvDraft.fileName = url.lastPathComponent
                    vm.csvDraft.parse = nil; vm.csvDraft.commit = nil
                    Task { await vm.parseCsv(env: env) }
                } else {
                    vm.errorMessage = "无法读取文件"
                }
            case .failure: vm.errorMessage = "无法读取文件"
            }
        }
    }

    private var actionsCard: some View {
        ModuleCard("操作") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                actionButton("添加账户", system: "creditcard.fill", color: DSColor.accent) { vm.openSheet(.account, env: env) }
                actionButton("录入交易", system: "arrow.up.arrow.down", color: DSColor.accent) { vm.openSheet(.trade, env: env) }
                actionButton("现金", system: "yensign.circle.fill", color: .green) { vm.openSheet(.cash, env: env) }
                actionButton("分红/拆股", system: "gift.fill", color: .orange) { vm.openSheet(.corp, env: env) }
                actionButton("导入CSV", system: "square.and.arrow.down", color: DSColor.accent) {
                    vm.openSheet(.csv, env: env); showCsvPicker = true
                }
                actionButton(vm.busy ? "刷新中…" : "刷新汇率", system: "arrow.clockwise", color: .blue) {
                    Task { await vm.refreshFx(env: env) }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func actionButton(_ title: String, system: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: system).font(.title3).foregroundStyle(color)
                Text(title).font(.caption2).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.plain)
    }

    private func recentTradesCard(_ trades: [PortfolioTradeListItem]) -> some View {
        ModuleCard("最近交易 · \(trades.count)") {
            VStack(spacing: 0) {
                ForEach(trades) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(t.symbol) · \(t.side == "buy" ? "买入" : "卖出")")
                                .font(.system(size: 15, weight: .medium))
                            Text("\(t.tradeDate ?? "—") · \(formatQty(t.quantity ?? 0))@\(String(format: "%.3f", t.price ?? 0))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("费税 \(formatMoney((t.fee ?? 0) + (t.tax ?? 0)))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("删除", role: .destructive) { Task { await vm.deleteTrade(env: env, id: t.id) } }
                    }
                    if t.id != trades.last?.id { Divider() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 表单

    private func accountPicker(_ selection: Binding<Int?>) -> some View {
        Picker("账户", selection: selection) {
            Text("请选择").tag(nil as Int?)
            ForEach(vm.accounts) { acct in Text(acct.name).tag(acct.id as Int?) }
        }
    }

    private func accountSheetForm() -> some View {
        NavigationStack {
            Form {
                Section("账户") {
                    TextField("名称", text: $vm.accountDraft.name)
                    TextField("券商（可选）", text: $vm.accountDraft.broker)
                    Picker("市场", selection: $vm.accountDraft.market) {
                        Text("A股").tag("cn"); Text("港股").tag("hk"); Text("美股").tag("us")
                        Text("日本").tag("jp"); Text("韩国").tag("kr")
                    }
                    TextField("基础货币", text: $vm.accountDraft.baseCurrency)
                    TextField("所有者 ID（可选）", text: $vm.accountDraft.ownerId)
                }
                if let err = vm.errorMessage { Section { Text(err).font(.caption).foregroundStyle(.red) } }
            }
            .navigationTitle("新建账户").dsInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { vm.sheet = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { Task { await vm.createAccount(env: env) } }
                        .disabled(vm.accountDraft.name.isEmpty || vm.busy)
                }
            }
        }
    }

    private func tradeSheetForm() -> some View {
        NavigationStack {
            Form {
                Section("账户") { accountPicker($vm.tradeDraft.accountId) }
                Section("交易") {
                    TextField("股票代码", text: $vm.tradeDraft.symbol).autocorrectionDisabled()
                    Picker("方向", selection: $vm.tradeDraft.side) { Text("买入").tag("buy"); Text("卖出").tag("sell") }
                    DatePicker("日期", selection: $vm.tradeDraft.date, displayedComponents: .date)
                    TextField("数量", text: $vm.tradeDraft.quantity).autocorrectionDisabled()
                    TextField("价格", text: $vm.tradeDraft.price).autocorrectionDisabled()
                    TextField("手续费", text: $vm.tradeDraft.fee).autocorrectionDisabled()
                    TextField("税费", text: $vm.tradeDraft.tax).autocorrectionDisabled()
                }
                Section("备注") { TextField("可选", text: $vm.tradeDraft.note) }
                if let err = vm.errorMessage { Section { Text(err).font(.caption).foregroundStyle(.red) } }
            }
            .navigationTitle("录入交易").dsInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { vm.sheet = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") { Task { await vm.createTrade(env: env) } }.disabled(vm.busy)
                }
            }
        }
    }

    private func cashSheetForm() -> some View {
        NavigationStack {
            Form {
                Section("账户") { accountPicker($vm.cashDraft.accountId) }
                Section("现金") {
                    Picker("方向", selection: $vm.cashDraft.direction) { Text("入账").tag("in"); Text("出账").tag("out") }
                    DatePicker("日期", selection: $vm.cashDraft.date, displayedComponents: .date)
                    TextField("金额", text: $vm.cashDraft.amount).autocorrectionDisabled()
                }
                Section("备注") { TextField("可选", text: $vm.cashDraft.note) }
                if let err = vm.errorMessage { Section { Text(err).font(.caption).foregroundStyle(.red) } }
            }
            .navigationTitle("记录现金").dsInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { vm.sheet = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") { Task { await vm.createCash(env: env) } }.disabled(vm.busy)
                }
            }
        }
    }

    private func corpSheetForm() -> some View {
        NavigationStack {
            Form {
                Section("账户") { accountPicker($vm.corpDraft.accountId) }
                Section("公司行为") {
                    TextField("股票代码", text: $vm.corpDraft.symbol).autocorrectionDisabled()
                    Picker("类型", selection: $vm.corpDraft.actionType) {
                        Text("现金分红").tag("cash_dividend"); Text("拆股调整").tag("split_adjustment")
                    }
                    DatePicker("生效日", selection: $vm.corpDraft.date, displayedComponents: .date)
                    if vm.corpDraft.actionType == "cash_dividend" {
                        TextField("每股分红", text: $vm.corpDraft.cashDividendPerShare).autocorrectionDisabled()
                    } else {
                        TextField("拆股比例（如 0.5）", text: $vm.corpDraft.splitRatio).autocorrectionDisabled()
                    }
                }
                Section("备注") { TextField("可选", text: $vm.corpDraft.note) }
                if let err = vm.errorMessage { Section { Text(err).font(.caption).foregroundStyle(.red) } }
            }
            .navigationTitle("分红 / 拆股").dsInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { vm.sheet = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") { Task { await vm.createCorp(env: env) } }.disabled(vm.busy)
                }
            }
        }
    }

    private func csvSheetForm() -> some View {
        NavigationStack {
            Form {
                Section("目标") {
                    accountPicker($vm.csvDraft.accountId)
                    Picker("券商", selection: $vm.csvDraft.broker) {
                        ForEach(vm.brokers.isEmpty ? [PortfolioImportBrokerItem(broker: "huatai", aliases: nil, displayName: nil)] : vm.brokers) { b in
                            Text(b.displayName ?? b.broker).tag(b.broker)
                        }
                    }
                }
                Section("文件") {
                    Button { showCsvPicker = true } label: {
                        HStack { Image(systemName: "doc.text"); Text(vm.csvDraft.fileName ?? "选择 CSV 文件") }
                    }
                    if vm.busy { ProgressView() }
                }
                if let parse = vm.csvDraft.parse {
                    Section("解析预览 · \(parse.recordCount ?? 0) 条") {
                        ForEach(Array((parse.records ?? []).prefix(8))) { r in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(r.symbol) · \(r.side == "buy" ? "买" : "卖") \(formatQty(r.quantity ?? 0))@\(String(format: "%.3f", r.price ?? 0))")
                                    .font(.caption)
                                Text(r.tradeDate ?? "—").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if let errs = parse.errors, !errs.isEmpty {
                            Text(errs.prefix(3).joined(separator: "\n")).font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
                if let commit = vm.csvDraft.commit {
                    Section(commit.dryRun == true ? "预演结果" : "导入结果") {
                        Text("新增 \(commit.insertedCount ?? 0) · 重复 \(commit.duplicateCount ?? 0) · 失败 \(commit.failedCount ?? 0)")
                            .font(.caption)
                    }
                }
                if let err = vm.errorMessage { Section { Text(err).font(.caption).foregroundStyle(.red) } }
            }
            .navigationTitle("导入 CSV").dsInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { vm.sheet = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("预演（dry-run）") { Task { await vm.commitCsv(env: env, dryRun: true) } }
                        Button("正式导入") { Task { await vm.commitCsv(env: env, dryRun: false) } }
                    } label: { Text("导入") }
                    .disabled(vm.csvDraft.fileData == nil || vm.busy)
                }
            }
        }
    }

    private func totalsBlock(_ snap: PortfolioSnapshotResponse) -> some View {
        let pnl = snap.unrealizedPnl ?? 0
        let equity = snap.totalEquity ?? 0
        let pnlPct = equity > 0 ? pnl / equity * 100 : 0
        let market = Market.cn
        let cur = snap.currency ?? "¥"
        return VStack(alignment: .leading, spacing: 4) {
            Text("总权益").font(.caption).foregroundStyle(.secondary).tracking(0.5)
            Text("\(cur)\(equity, format: .number.precision(.fractionLength(2)))")
                .font(DSFont.display(38)).monospacedDigit()
            HStack(spacing: 8) {
                Image(systemName: pnl >= 0 ? "triangle.fill" : "triangle.fill")
                    .rotationEffect(pnl >= 0 ? .zero : .degrees(180))
                    .imageScale(.small)
                Text((pnl >= 0 ? "+" : "") + String(format: "%.0f", pnl))
                Text("(\(String(format: "%+.2f%%", pnlPct)))")
                Text("未实现").font(.footnote).foregroundStyle(.secondary)
            }
            .font(.callout.weight(.medium)).monospacedDigit()
            .foregroundStyle(DSColor.change(pnl, market: market, scheme: env.colorScheme))
            // 市值 / 现金 / 汇率状态（对齐 web 汇总卡）
            HStack(spacing: 16) {
                if let mv = snap.totalMarketValue {
                    miniStat("市值", "\(cur)\(formatMoney(mv))")
                }
                if let cash = snap.totalCash {
                    miniStat("现金", "\(cur)\(formatMoney(cash))")
                }
                if snap.fxStale == true {
                    Label("汇率待更新", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    private func accountsCard(_ accounts: [PortfolioAccountSnapshot]) -> some View {
        ModuleCard("账户 · \(accounts.count)") {
            VStack(spacing: 0) {
                ForEach(accounts) { acct in
                    HStack {
                        Text(acct.accountName ?? "账户 \(acct.accountId ?? 0)")
                            .font(.system(size: 15, weight: .medium))
                        Spacer()
                        Text("\(acct.baseCurrency ?? "")\(acct.totalEquity ?? 0, format: .number.precision(.fractionLength(0)))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    if acct.id != accounts.last?.id { Divider() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func positionsCard(_ positions: [PortfolioPositionItem]) -> some View {
        ModuleCard("持仓 · \(positions.count)") {
            VStack(spacing: 0) {
                ForEach(positions) { p in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.symbol).font(.system(size: 16, weight: .medium))
                            HStack(spacing: 6) {
                                Text("\(formatQty(p.quantity ?? 0)) 股")
                                Text("· 成本 \(String(format: "%.3f", p.avgCost ?? 0))")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            if let lp = p.lastPrice {
                                HStack(spacing: 4) {
                                    Text("现价 \(p.marketEnum.currencySymbol)\(String(format: "%.2f", lp))")
                                    if p.priceStale == true {
                                        Text("· 估值待更新").foregroundStyle(.orange)
                                    } else if let src = p.priceSource, !src.isEmpty, src != "unknown" {
                                        Text("· \(src)").foregroundStyle(.tertiary)
                                    }
                                }
                                .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(p.marketEnum.currencySymbol)\(formatMoney(p.marketValueBase ?? 0))")
                                .font(.system(size: 15, weight: .medium)).monospacedDigit()
                            if let pnlAbs = p.unrealizedPnlBase {
                                Text((pnlAbs >= 0 ? "+" : "") + "\(p.marketEnum.currencySymbol)\(formatMoney(pnlAbs))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DSColor.change(pnlAbs, market: p.marketEnum, scheme: env.colorScheme))
                            }
                            let pct = p.unrealizedPnlPct ?? 0
                            Text("\((pct >= 0 ? "+" : "") + String(format: "%.1f%%", pct))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DSColor.change(pct, market: p.marketEnum, scheme: env.colorScheme))
                        }
                    }
                    .padding(.vertical, 8)
                    if p.id != positions.last?.id { Divider() }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func riskCard(_ risk: PortfolioRiskResponse) -> some View {
        ModuleCard("风险报告") {
            VStack(alignment: .leading, spacing: 10) {
                Text("成本方法 \(risk.costMethod ?? "—") · 截至 \(risk.asOf ?? "—")")
                    .font(.footnote).foregroundStyle(.secondary)

                if let dd = risk.drawdown,
                   let maxDD = dd["max_drawdown_pct"]?.doubleValue {
                    riskRow("最大回撤", String(format: "%.1f%%", maxDD), color: .red)
                }
                if let sl = risk.stopLoss {
                    let triggered = sl["triggered_count"]?.doubleValue
                    let near = sl["near_count"]?.doubleValue
                    if triggered != nil || near != nil {
                        riskRow("止损预警",
                                "\(Int(triggered ?? 0)) 已触发 · \(Int(near ?? 0)) 临近",
                                color: .orange)
                    }
                }
                let conc = risk.concentration ?? risk.sectorConcentration
                if let c = conc, let top = c["top_weight_pct"]?.doubleValue {
                    riskRow("集中度", String(format: "%.1f%% 头部权重", top), color: top > 40 ? .orange : .secondary)
                }
                if let dsr = risk.decisionSignalRisk, dsr.available == true, let total = dsr.total, total > 0 {
                    decisionSignalRiskBlock(dsr)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func decisionSignalRiskBlock(_ dsr: PortfolioDecisionSignalRiskBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AI 决策信号风险").font(.caption.weight(.medium))
                Spacer()
                Text("\(dsr.total ?? 0) 条").font(.caption).foregroundStyle(.secondary)
            }
            if let items = dsr.items, !items.isEmpty {
                ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { _, it in
                    HStack {
                        Text(it.symbol ?? "—").font(.caption)
                        Spacer()
                        let label = it.signal?["action_label"]?.stringValue ?? it.signal?["action"]?.stringValue
                        if let label { Text(label).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func riskRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(color)
        }
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
            Text(value).font(.footnote.monospacedDigit())
        }
    }

    private func formatMoney(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1e8 { return String(format: "%.2f亿", v / 1e8) }
        if a >= 1e4 { return String(format: "%.2f万", v / 1e4) }
        return String(format: "%.2f", v)
    }

    private func formatQty(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%.4f", v)
    }
}

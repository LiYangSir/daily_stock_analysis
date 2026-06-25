import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class IntelligentImportViewModel: ObservableObject {
    @Published var items: [IntelligentImportItem] = []
    @Published var mode: Int = 0            // 0 图片 · 1 文件 · 2 文本
    @Published var text: String = ""
    @Published var busy = false
    @Published var errorMessage: String?
    @Published var info: String?
    @Published var showPicker = false

    var selectedCount: Int { items.filter(\.selected).count }

    /// 图片提取：POST /stocks/extract-from-image（multipart, field=file）。
    func extractFromImage(env: AppEnvironment, data: Data, filename: String) async {
        busy = true; defer { busy = false }
        let mime = Self.imageMIME(for: filename) ?? "image/jpeg"
        let file = UploadFile(field: "file", filename: filename, mimeType: mime, data: data)
        do {
            let resp: ExtractFromImageResponse = try await env.auth.api.sendMultipart(
                path: "/stocks/extract-from-image", files: [file])
            apply(resp)
            info = "识别到 \(items.count) 支"
        } catch {
            errorMessage = "识别失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 文件解析：POST /stocks/parse-import（multipart, field=file）。
    func parseFile(env: AppEnvironment, data: Data, filename: String) async {
        busy = true; defer { busy = false }
        let mime = filename.lowercased().hasSuffix(".csv") ? "text/csv" : "application/octet-stream"
        let file = UploadFile(field: "file", filename: filename, mimeType: mime, data: data)
        do {
            let resp: ExtractFromImageResponse = try await env.auth.api.sendMultipart(
                path: "/stocks/parse-import", files: [file])
            apply(resp)
            info = "解析到 \(items.count) 支"
        } catch {
            errorMessage = "解析失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 文本解析：POST /stocks/parse-import（application/json, {text}）。
    func parseText(env: AppEnvironment) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "请粘贴文本"; return }
        struct Body: Encodable { let text: String }
        busy = true; defer { busy = false }
        do {
            let resp: ExtractFromImageResponse = try await env.auth.api.send(
                Endpoint(path: "/stocks/parse-import", method: .POST, body: try JSONEncoder.dsa.encode(Body(text: trimmed))))
            apply(resp)
            info = "解析到 \(items.count) 支"
        } catch {
            errorMessage = "解析失败：\((error as? APIError)?.errorDescription ?? "")"
        }
    }

    /// 合并到自选：对已勾选项批量 POST /stocks/watchlist/add。
    func merge(env: AppEnvironment) async {
        let codes = items.filter(\.selected).map(\.stockCode)
        guard !codes.isEmpty else { return }
        struct Body: Encodable { let stockCode: String }
        busy = true; defer { busy = false }
        var added = 0, failed = 0
        await withTaskGroup(of: Bool.self) { group in
            for code in codes {
                group.addTask {
                    do {
                        try await env.auth.api.sendVoid(
                            Endpoint(path: "/stocks/watchlist/add", method: .POST,
                                     body: try JSONEncoder.dsa.encode(Body(stockCode: code))))
                        return true
                    } catch { return false }
                }
            }
            for await ok in group { if ok { added += 1 } else { failed += 1 } }
        }
        info = "已合并 \(added) 支" + (failed > 0 ? " · 失败 \(failed)" : "")
        errorMessage = failed > 0 ? errorMessage : nil
        if failed == 0 { items = [] }
    }

    private func apply(_ resp: ExtractFromImageResponse) {
        items = (resp.items ?? []).compactMap { it in
            guard let code = it.code, !code.isEmpty else { return nil }
            return IntelligentImportItem(stockCode: code, stockName: it.name ?? code,
                                         market: nil, confidence: Self.confidenceToDouble(it.confidence),
                                         selected: true)
        }
        errorMessage = nil
    }

    private static func confidenceToDouble(_ s: String?) -> Double {
        switch (s ?? "").lowercased() {
        case "high": return 0.9
        case "medium": return 0.6
        default: return 0.3
        }
    }

    private static func imageMIME(for filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "jpg", "jpeg": return "image/jpeg"
        default: return nil
        }
    }
}

public struct IntelligentImportView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm = IntelligentImportViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    chip("📷 图片", index: 0)
                    chip("📄 文件", index: 1)
                    chip("📋 文本", index: 2)
                    Spacer()
                }
                .padding(.horizontal, 16)

                sourceCard
                resultCard
                mergeButton
                Color.clear.frame(height: 80)
            }
            .padding(.top, 6)
        }
        .background(Color.dsGroupedBackground)
        .navigationTitle("智能导入自选")
        .dsInlineTitle()
        .fileImporter(isPresented: $vm.showPicker,
                      allowedContentTypes: vm.mode == 0 ? [.image] : [.commaSeparatedText, .plainText, .data]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { vm.errorMessage = "无法读取文件"; return }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { vm.errorMessage = "无法读取文件"; return }
                let name = url.lastPathComponent
                Task {
                    if vm.mode == 0 { await vm.extractFromImage(env: env, data: data, filename: name) }
                    else { await vm.parseFile(env: env, data: data, filename: name) }
                }
            case .failure: vm.errorMessage = "无法读取文件"
            }
        }
        .alert("提示", isPresented: .constant(vm.info != nil)) {
            Button("好的") { vm.info = nil }
        } message: { Text(vm.info ?? "") }
    }

    private var sourceCard: some View {
        ModuleCard(vm.mode == 0 ? "图片识别" : (vm.mode == 1 ? "文件解析" : "文本解析")) {
            VStack(spacing: 10) {
                if vm.mode < 2 {
                    Button { vm.showPicker = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: vm.mode == 0 ? "photo.on.rectangle.angled" : "doc.text.viewfinder")
                                .font(.system(size: 40, weight: .light)).foregroundStyle(DSColor.accent)
                            Text(vm.mode == 0 ? "点击选择截图" : "点击选择 CSV / 文本文件")
                                .font(.system(size: 14, weight: .semibold))
                            Text(vm.mode == 0 ? "支持券商持仓 / 股票群截图 · OCR 自动识别"
                                             : "支持 CSV / 文本，自动解析股票代码")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)
                    if vm.busy { ProgressView() }
                } else {
                    TextEditor(text: $vm.text)
                        .frame(minHeight: 120)
                        .font(.subheadline)
                        .overlay(alignment: .topLeading) {
                            if vm.text.isEmpty {
                                Text("粘贴股票代码 / 名称列表…").foregroundStyle(.tertiary)
                                    .font(.subheadline).padding(.top, 8).padding(.leading, 6).allowsHitTesting(false)
                            }
                        }
                    Button {
                        Task { await vm.parseText(env: env) }
                    } label: {
                        Text("解析文本").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 38)
                            .background(DSColor.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(DSColor.accent)
                    }
                    .buttonStyle(.plain).disabled(vm.busy)
                }
                if let err = vm.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var resultCard: some View {
        ModuleCard("已识别 · \(vm.items.count)（已勾选 \(vm.selectedCount)）") {
            if vm.items.isEmpty {
                Text("选择图片 / 文件或粘贴文本后，识别结果将出现在这里")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach($vm.items) { $item in
                        HStack(spacing: 10) {
                            Image(systemName: item.selected ? "checkmark.square.fill" : "square")
                                .foregroundStyle(item.selected ? DSColor.accent : .secondary)
                                .onTapGesture { item.selected.toggle() }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.stockName).font(.system(size: 15, weight: .medium))
                                Text(item.stockCode).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            confidenceTag(item.confidence)
                        }
                        .padding(.vertical, 8)
                        if item.id != vm.items.last?.id { Divider() }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var mergeButton: some View {
        Button {
            Task { await vm.merge(env: env) }
        } label: {
            HStack {
                if vm.busy { ProgressView().tint(.white) }
                Text("合并到自选（\(vm.selectedCount) 支）").font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(vm.selectedCount == 0 ? Color.gray.opacity(0.3) : DSColor.accent, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(vm.selectedCount == 0 || vm.busy)
        .padding(.horizontal, 16)
    }

    private func chip(_ title: String, index: Int) -> some View {
        let active = vm.mode == index
        return Button { vm.mode = index; vm.errorMessage = nil } label: {
            Text(title).font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(active ? DSColor.accent.opacity(0.16) : Color.gray.opacity(0.10), in: Capsule())
                .foregroundStyle(active ? DSColor.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func confidenceTag(_ c: Double) -> some View {
        let (label, color): (String, Color) = {
            switch c {
            case 0.85...: return ("高", .green)
            case 0.6..<0.85: return ("中", .orange)
            default: return ("低", .red)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }
}

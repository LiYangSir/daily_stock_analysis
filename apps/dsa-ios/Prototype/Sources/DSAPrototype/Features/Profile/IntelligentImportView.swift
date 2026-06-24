import SwiftUI

public struct IntelligentImportView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var mode: Int = 0
    @State private var items: [IntelligentImportItem] = []

    public init() {}

    public var body: some View {
        List {
            Section {
                HStack(spacing: 6) {
                    chip("📷 图片", index: 0)
                    chip("📄 文件", index: 1)
                    chip("📋 文本", index: 2)
                }
            }
            .listRowBackground(Color.clear)

            Section {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(DSColor.accent)
                    Text("点击选择 / 拖入截图").font(.system(size: 14, weight: .semibold))
                    Text("支持券商持仓 / 股票群截图 · OCR 自动识别")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(DSColor.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4])))
            }
            .listRowBackground(Color.clear)

            Section("已识别 · \(items.count)（已勾选 \(items.filter(\.selected).count)）") {
                ForEach($items) { $item in
                    HStack(spacing: 10) {
                        Image(systemName: item.selected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.selected ? DSColor.accent : .secondary)
                            .onTapGesture { item.selected.toggle() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.stockName).font(.system(size: 15, weight: .medium))
                            Text("\(item.stockCode)\(item.market.map { " · \($0)" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        confidenceTag(item.confidence)
                    }
                }
            }

            Section {
                Button { } label: {
                    Text("合并到自选（\(items.filter(\.selected).count) 支）")
                        .frame(maxWidth: .infinity).font(.system(size: 15, weight: .semibold))
                }
                .disabled(items.filter(\.selected).isEmpty)
            }
        }
        .dsListStyle()
        .scrollContentBackground(.hidden)
        .background(Color.dsGroupedBackground)
        .navigationTitle("智能导入自选")
        .dsInlineTitle()
    }

    private func chip(_ title: String, index: Int) -> some View {
        let active = mode == index
        return Button { mode = index } label: {
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

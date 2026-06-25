import SwiftUI
import MarkdownUI

/// 把 Markdown 文本按标题自动切分成多个卡片。
/// 策略（与 Web UI MarketReviewReportView 对齐）：
/// 1. 去掉顶部一级标题（如 "# 大盘复盘"）
/// 2. 按所有 ## 和 ### 标题统一切分
/// 3. 标题前的引导文字作为"概览"卡片
public struct MarkdownCards: View {
    let text: String

    public init(text: String) { self.text = text }

    public var body: some View {
        let sections = splitSections(text)
        if sections.count <= 1 {
            singleCard(text)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    sectionCard(section)
                }
            }
        }
    }

    private func singleCard(_ content: String) -> some View {
        Markdown(content)
            .reportMarkdown()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
    }

    private func sectionCard(_ section: MdSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = section.title {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Divider().padding(.horizontal, 12)
            }
            if !section.body.isEmpty {
                Markdown(section.body)
                    .reportMarkdown()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
    }

    // MARK: - Parsing (aligned with Web UI splitMarketReviewSections)

    private struct MdSection {
        let title: String?
        let body: String
    }

    private func splitSections(_ text: String) -> [MdSection] {
        var markdown = text

        // 1. 去掉顶部一级标题（# xxx）
        let lines = markdown.components(separatedBy: "\n")
        if let firstNonEmpty = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           firstNonEmpty.hasPrefix("# ") && !firstNonEmpty.hasPrefix("## ") {
            // 去掉第一个一级标题行
            if let range = markdown.range(of: firstNonEmpty) {
                markdown = String(markdown[range.upperBound...]).trimmingCharacters(in: .newlines)
            }
        }

        // 2. 找所有 ## 和 ### 标题的位置
        let pattern = #"(?m)^(#{2,3})\s+(.+?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [MdSection(title: nil, body: text)]
        }

        let nsMarkdown = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length))

        if matches.isEmpty {
            return [MdSection(title: nil, body: markdown)]
        }

        var sections: [MdSection] = []

        // 3. 标题前的内容作为"概览"
        let firstMatchStart = matches[0].range.location
        if firstMatchStart > 0 {
            let intro = nsMarkdown.substring(to: firstMatchStart).trimmingCharacters(in: .whitespacesAndNewlines)
            if !intro.isEmpty {
                sections.append(MdSection(title: nil, body: intro))
            }
        }

        // 4. 逐个标题切分
        for (i, match) in matches.enumerated() {
            let titleRange = match.range(at: 2)
            let title = nsMarkdown.substring(with: titleRange).trimmingCharacters(in: .whitespaces)

            let contentStart = match.range.location + match.range.length
            let contentEnd: Int
            if i + 1 < matches.count {
                contentEnd = matches[i + 1].range.location
            } else {
                contentEnd = nsMarkdown.length
            }

            let content = nsMarkdown.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !content.isEmpty || !title.isEmpty {
                sections.append(MdSection(title: title, body: content))
            }
        }

        return sections.isEmpty ? [MdSection(title: nil, body: text)] : sections
    }
}

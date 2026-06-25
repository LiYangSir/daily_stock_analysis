import SwiftUI
import MarkdownUI

extension Theme {
    /// 报告正文 Markdown 主题，对齐 Web UI `prose prose-sm`（`ReportMarkdownBody`）。
    ///
    /// 用于大盘复盘分节正文等场景：在卡片内渲染 markdown 时，标题按比例缩放、
    /// GFM 表格描边 + 交替行、列表更紧凑、引用块带左侧 accent 色条、代码段为圆角 chip，
    /// 避免默认主题的大字号标题 / 裸表格撑乱小卡片。
    ///
    /// 参考 `.build/checkouts/swift-markdown-ui/.../Theme+GitHub.swift`，颜色改用 App `Color.ds*` token。
    public static let reportProse = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(14)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
            ForegroundColor(.secondary)
            BackgroundColor(Color.dsSystemFill)
        }
        .strong {
            FontWeight(.semibold)
            ForegroundColor(.primary)
        }
        .link {
            ForegroundColor(DSColor.accent)
        }
        // 标题：分节正文里多为 #### 子标题；整体缩放，避免大字号撑爆卡片，且不画分隔线。
        .heading1 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 14, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.25))
                }
        }
        .heading2 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 12, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.18))
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 10, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.05))
                }
        }
        .heading4 { configuration in
            configuration.label
                .markdownMargin(top: 8, bottom: 2)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.95))
                    ForegroundColor(.secondary)
                }
        }
        .paragraph { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.32))
                .markdownMargin(top: 0, bottom: 8)
        }
        // 引用块：左侧 accent 色条 + 次级文字（对齐 prose-blockquote:text-secondary-text）。
        .blockquote { configuration in
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(DSColor.accent.opacity(0.8))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle { ForegroundColor(.secondary) }
            }
            .padding(.vertical, 2)
            .markdownMargin(top: 0, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.15), bottom: .em(0.15))
                .relativeLineSpacing(.em(0.25))
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                }
                .padding(12)
                .background(Color.dsSystemFill, in: RoundedRectangle(cornerRadius: 8))
                .markdownMargin(top: 6, bottom: 8)
        }
        // GFM 表格：浅描边 + 交替行底色 + 表头行 semibold，紧凑 padding。
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: Color.gray.opacity(0.2)))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clear, Color.dsSystemFill.opacity(0.35))
                )
                .markdownMargin(top: 4, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    BackgroundColor(nil)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .relativeLineSpacing(.em(0.2))
        }
}

extension View {
    /// 用报告正文主题渲染 MarkdownUI 内容（对齐 Web `prose prose-sm`）。
    public func reportMarkdown() -> some View {
        self.markdownTheme(.reportProse)
    }
}

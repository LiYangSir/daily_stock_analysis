import SwiftUI

/// 居中空态：图标 + 标题 + 可选副标题 + 可选动作按钮。
/// 用于列表/卡片在「无数据且非错误」时给出可读说明，替代零散的 `Text("暂无…")`。
public struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String?
    let actionTitle: String?
    let action: (() -> Void)?

    public init(icon: String, title: String, subtitle: String? = nil,
                actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon; self.title = title; self.subtitle = subtitle
        self.actionTitle = actionTitle; self.action = action
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).frame(height: 34)
                        .background(DSColor.accent.opacity(0.14), in: Capsule())
                        .foregroundStyle(DSColor.accent)
                }
                .buttonStyle(.plain).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 32)
    }
}

/// 居中错误态：图标 + 「加载失败」+ 后端文案 + 可选「重试」按钮。
/// 替代各屏零散的 `if let err { Text(err) }`，并提供可操作的重试入口。
public struct ErrorStateView: View {
    let message: String
    let retry: (() -> Void)?

    public init(message: String, retry: (() -> Void)? = nil) {
        self.message = message; self.retry = retry
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 38, weight: .light)).foregroundStyle(.orange)
            Text("加载失败").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            Text(message).font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).lineLimit(4)
            if let retry {
                Button(action: retry) {
                    Label("重试", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).frame(height: 34)
                        .background(DSColor.accent.opacity(0.14), in: Capsule())
                        .foregroundStyle(DSColor.accent)
                }
                .buttonStyle(.plain).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36).padding(.horizontal, 32)
    }
}

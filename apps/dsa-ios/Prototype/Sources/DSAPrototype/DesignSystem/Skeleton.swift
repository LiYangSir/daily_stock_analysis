import SwiftUI

/// 骨架屏 shimmer 效果（类似 shadcn Skeleton）
public struct Skeleton: View {
    let width: CGFloat?
    let height: CGFloat

    public init(width: CGFloat? = nil, height: CGFloat = 16) {
        self.width = width
        self.height = height
    }

    @State private var phase: CGFloat = 0

    public var body: some View {
        RoundedRectangle(cornerRadius: height / 3)
            .fill(Color.gray.opacity(0.12))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: height / 3)
                    .fill(
                        LinearGradient(colors: [.clear, Color.white.opacity(0.3), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .offset(x: phase)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = (width ?? 200) + 100
                }
            }
    }
}

/// 行情列表骨架屏
public struct WatchlistSkeleton: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Skeleton(width: 80, height: 14)
                        Skeleton(width: 50, height: 10)
                    }
                    Spacer()
                    Skeleton(width: 70, height: 14)
                    Skeleton(width: 60, height: 26)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                Divider().padding(.leading, 16)
            }
        }
        .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

/// 通用内容骨架
public struct ContentSkeleton: View {
    let lines: Int
    public init(lines: Int = 4) { self.lines = lines }
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<lines, id: \.self) { i in
                Skeleton(width: i == lines - 1 ? 120 : nil, height: 12)
            }
        }
        .padding(16)
        .background(Color.dsSecondaryGrouped, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

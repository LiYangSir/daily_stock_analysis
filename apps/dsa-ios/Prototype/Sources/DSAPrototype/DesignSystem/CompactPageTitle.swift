import SwiftUI

/// 紧凑的主 Tab 页大标题：贴近 SafeArea，约 12pt 顶部 padding，标题 28pt
/// 用于替换 NavigationStack 的 large title（默认 large title 约 96pt 顶空）。
public struct CompactPageTitle<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .default))
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

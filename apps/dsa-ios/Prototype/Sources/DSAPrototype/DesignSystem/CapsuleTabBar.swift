import SwiftUI

/// 浮空胶囊 Tab Bar。正文从其下方穿过。
public struct CapsuleTabBar: View {
    public struct Item: Identifiable, Sendable {
        public let id: Int
        public let title: String
        public let symbol: String
        public init(id: Int, title: String, symbol: String) {
            self.id = id; self.title = title; self.symbol = symbol
        }
    }

    @Binding var selection: Int
    let items: [Item]

    public init(selection: Binding<Int>, items: [Item]) {
        self._selection = selection
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    selection = item.id
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: selection == item.id ? .semibold : .regular))
                        Text(item.title).font(.system(size: 10, weight: .medium))
                    }
                    .frame(width: 56, height: 48)
                    .foregroundStyle(selection == item.id ? DSColor.accent : Color.secondary)
                    .background(
                        Capsule().fill(selection == item.id ? DSColor.accent.opacity(0.12) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: selection)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 64)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 12)
        .padding(.bottom, 18)
    }
}

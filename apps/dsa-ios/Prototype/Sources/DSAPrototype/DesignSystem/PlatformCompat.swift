import SwiftUI

extension View {
    /// Hide navigation bar. No-op on macOS (allows CLI builds to succeed).
    @ViewBuilder
    public func hideNavBar() -> some View {
        #if os(iOS)
        self.navigationBarHidden(true)
        #else
        self
        #endif
    }

    /// iOS-only list style
    @ViewBuilder
    public func dsListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self
        #endif
    }

    /// iOS-only title display mode
    @ViewBuilder
    public func dsInlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

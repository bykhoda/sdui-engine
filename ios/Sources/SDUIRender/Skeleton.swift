#if canImport(SwiftUI)
import SwiftUI

/// An animated shimmer placeholder shown while remote content loads. A soft base
/// fill with a light gradient band sweeping across it — the pattern popularised
/// by Facebook Shimmer / SkeletonView, which reads as "loading" far better than
/// a static grey block.
struct SkeletonView: View {
    var cornerRadius: CGFloat = 0

    @State private var animate = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // A calm grey base with a soft light band sweeping across — no additive
        // blend, so it reads as a gentle shimmer rather than an over-bright glow.
        let base = (scheme == .dark ? Color.white : Color.black).opacity(0.07)
        let highlight = Color.white.opacity(scheme == .dark ? 0.09 : 0.45)

        GeometryReader { geo in
            let width = geo.size.width
            base.overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, highlight, .clear]),
                    startPoint: .leading, endPoint: .trailing)
                    .frame(width: width * 0.5)
                    .offset(x: animate ? width * 1.25 : -width * 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}
#endif

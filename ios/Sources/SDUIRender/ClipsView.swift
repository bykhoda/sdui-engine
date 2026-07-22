#if canImport(SwiftUI)
import SwiftUI
import SDUICore

/// A full-screen vertical snap-pager — a full-screen short-video feed driven
/// from JSON. Each page carries its own media (a gradient here; a remote image
/// or video URL on a real backend), a caption block and a right-side action
/// rail. Swipe up/down to page, double-tap to like.
///
/// Cross-platform note: this is pure paging + overlays, so it maps 1:1 to a
/// Compose `VerticalPager` and an Aurora scroll-snap container — the same
/// `pages` contract renders the same feed everywhere, no per-platform feed code.
struct ClipsView: View {
    let component: Component
    let ctx: RenderContext

    @State private var index = 0
    @State private var drag: CGFloat = 0
    @State private var liked: Set<Int> = []
    @State private var burst: Int?
    @State private var discAngle: Double = 0
    /// Pages whose "media" has finished buffering — until then the page shows a
    /// shimmering skeleton, mimicking a real video/photo feed loading.
    @State private var loaded: Set<Int> = []

    private var pages: [JSONValue] { component.prop("pages")?.arrayValue ?? [] }

    private func load(_ i: Int) {
        guard i >= 0, i < pages.count, !loaded.contains(i) else { return }
        Task {
            try? await Task.sleep(nanoseconds: 750_000_000)
            withAnimation(.easeOut(duration: 0.3)) { _ = loaded.insert(i) }
        }
    }

    /// A modern gradient-ring avatar with the creator's initial (Instagram-style).
    private func avatar(for handle: String) -> some View {
        let letter = handle.drop(while: { $0 == "@" }).first.map(String.init)?.uppercased() ?? "-"
        return ZStack {
            Circle().fill(AngularGradient(colors: [
                Color(.sRGB, red: 0.98, green: 0.29, blue: 0.36, opacity: 1),
                Color(.sRGB, red: 0.98, green: 0.55, blue: 0.19, opacity: 1),
                Color(.sRGB, red: 0.79, green: 0.24, blue: 0.86, opacity: 1),
                Color(.sRGB, red: 0.98, green: 0.29, blue: 0.36, opacity: 1)
            ], center: .center))
            Circle().fill(.black.opacity(0.82)).padding(2.5)
            Text(letter).font(.subheadline.weight(.bold)).foregroundStyle(.white)
        }
        .frame(width: 38, height: 38)
    }

    var body: some View {
        ZStack {
            Color.black
            GeometryReader { geo in
                let h = geo.size.height
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { i in
                            page(pages[i], i: i)
                                .frame(width: geo.size.width, height: h)
                        }
                    }
                    .offset(y: -CGFloat(index) * h + drag)
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: index)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { v in drag = rubberBanded(v.translation.height, h: h) }
                            .onEnded { v in settle(v.translation.height, predicted: v.predictedEndTranslation.height, h: h) }
                    )
                    topBar
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { discAngle = 360 }
            load(0)
        }
    }

    // MARK: paging maths

    private func rubberBanded(_ dy: CGFloat, h: CGFloat) -> CGFloat {
        // Resist dragging past the first / last page.
        if (index == 0 && dy > 0) || (index == pages.count - 1 && dy < 0) { return dy * 0.3 }
        return dy
    }
    private func settle(_ dy: CGFloat, predicted: CGFloat, h: CGFloat) {
        let threshold = h * 0.18
        var next = index
        if (dy < -threshold || predicted < -h * 0.5), index < pages.count - 1 { next += 1 }
        else if (dy > threshold || predicted > h * 0.5), index > 0 { next -= 1 }
        let changed = next != index
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            index = next
            drag = 0
        }
        if changed { load(next) }
        #if os(iOS)
        if changed { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        #endif
    }

    // MARK: page

    private func page(_ p: JSONValue, i: Int) -> some View {
        ZStack {
            gradient(p)
            LinearGradient(colors: [.black.opacity(0.15), .clear, .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
            if burst == i {
                Image(systemName: "heart.fill")
                    .font(.system(size: 120)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 16)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            overlay(p, i: i)
            if !loaded.contains(i) {
                skeleton.transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { likeBurst(i) }
    }

    /// The buffering state: the media dims, placeholder blocks shimmer where the
    /// caption and rail will be, and a spinner sits centre — a real feed loader.
    private var skeleton: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        skelBar(150, 16)
                        skelBar(240, 12)
                        skelBar(120, 12)
                    }
                    Spacer()
                    VStack(spacing: 22) {
                        ForEach(0..<4, id: \.self) { _ in
                            Circle().fill(.white.opacity(0.16)).frame(width: 34, height: 34)
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 54)
            }
            // No spinner — Instagram loads reels as pure shimmering skeletons.
        }
        .modifier(ShimmerModifier())
    }

    private func skelBar(_ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: h / 2, style: .continuous)
            .fill(.white.opacity(0.16)).frame(width: w, height: h)
    }

    private func gradient(_ p: JSONValue) -> some View {
        let colors = (p["colors"]?.arrayValue?.compactMap { $0.stringValue })
            .map { $0.compactMap { Theme.color($0, ctx: ctx.binding) } } ?? []
        let resolved = colors.count >= 2 ? colors : [Color.purple, Color.black]
        return LinearGradient(colors: resolved, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: overlays

    private var topBar: some View {
        HStack(spacing: 22) {
            Text("Following").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Text("For You").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .overlay(alignment: .bottom) { Capsule().fill(.white).frame(width: 20, height: 2).offset(y: 6) }
            Spacer()
            Image(systemName: "camera").font(.title3).foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.top, 104)
        .shadow(color: .black.opacity(0.3), radius: 4)
    }

    private func overlay(_ p: JSONValue, i: Int) -> some View {
        let isLiked = liked.contains(i)
        return VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 12) {
                captionBlock(p)
                Spacer(minLength: 8)
                actionRail(p, i: i, isLiked: isLiked)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 54)
        }
    }

    private func captionBlock(_ p: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                avatar(for: p["author"]?.stringValue ?? "@creator")
                Text(p["author"]?.stringValue ?? "@creator")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text("Follow")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 1))
            }
            if let cap = p["caption"]?.stringValue {
                Text(cap).font(.subheadline).foregroundStyle(.white.opacity(0.96))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 7) {
                Image(systemName: "music.note").font(.caption)
                Text(p["audio"]?.stringValue ?? "Original audio").font(.footnote).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.95))
        }
        .shadow(color: .black.opacity(0.35), radius: 5)
    }

    private func actionRail(_ p: JSONValue, i: Int, isLiked: Bool) -> some View {
        VStack(spacing: 24) {
            railButton(isLiked ? "heart.fill" : "heart", p["likes"]?.stringValue ?? "0",
                       tint: isLiked ? Color(.sRGB, red: 1, green: 0.24, blue: 0.37, opacity: 1) : .white,
                       bump: isLiked) { toggleLike(i) }
            railButton("bubble.right.fill", p["comments"]?.stringValue ?? "0")
            railButton("arrowshape.turn.up.right.fill", p["shares"]?.stringValue ?? "Share")
            railButton("ellipsis", "")
            // Spinning audio disc.
            ZStack {
                Circle().fill(LinearGradient(colors: [.white.opacity(0.9), .gray], startPoint: .top, endPoint: .bottom))
                    .frame(width: 42, height: 42)
                Circle().fill(.black).frame(width: 14, height: 14)
                Image(systemName: "music.note").font(.caption2).foregroundStyle(.white)
            }
            .rotationEffect(.degrees(discAngle))
            .shadow(color: .black.opacity(0.3), radius: 4)
        }
    }

    private func railButton(_ icon: String, _ label: String, tint: Color = .white, bump: Bool = false, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.title2).foregroundStyle(tint)
                    .scaleEffect(bump ? 1.12 : 1)
                    .shadow(color: .black.opacity(0.3), radius: 3)
                if !label.isEmpty {
                    Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: actions

    private func toggleLike(_ i: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
            if liked.contains(i) { liked.remove(i) } else { liked.insert(i) }
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func likeBurst(_ i: Int) {
        liked.insert(i)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { burst = i }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            withAnimation(.easeOut(duration: 0.25)) { if burst == i { burst = nil } }
        }
    }
}

/// A sweeping highlight used by loading skeletons.
private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.22), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.55)
                        .offset(x: geo.size.width * phase)
                        .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { phase = 1.8 }
            }
    }
}
#endif

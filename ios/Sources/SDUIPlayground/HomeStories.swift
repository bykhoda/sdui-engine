#if canImport(SwiftUI)
import SwiftUI
import SDUIRender

// MARK: - Data

/// One "story" that showcases a product capability. Each has a few segments that
/// auto-advance, exactly like Instagram / WhatsApp / Telegram stories.
struct CapabilityStory: Identifiable {
    let id: Int
    let label: String
    let ringIcon: String
    let tint: [Color]
    let segments: [StorySegment]

    static let all: [CapabilityStory] = [
        CapabilityStory(id: 0, label: "Server-driven", ringIcon: "arrow.triangle.2.circlepath",
                        tint: [c(0.40, 0.40, 0.96), c(0.46, 0.29, 0.71)],
                        segments: [
                            StorySegment(icon: "arrow.triangle.2.circlepath", title: "Ship whole screens",
                                         body: "Your backend returns JSON. The app renders it natively — no App Store release.",
                                         colors: [c(0.40, 0.40, 0.96), c(0.29, 0.24, 0.64)]),
                            StorySegment(icon: "bolt.fill", title: "Change UI in seconds",
                                         body: "Reorder a feed, swap a paywall, restyle checkout — live, for everyone.",
                                         colors: [c(0.36, 0.36, 0.94), c(0.20, 0.18, 0.55)])
                        ]),
        CapabilityStory(id: 1, label: "One contract", ringIcon: "square.on.square",
                        tint: [c(0.00, 0.72, 0.62), c(0.00, 0.45, 0.55)],
                        segments: [
                            StorySegment(icon: "square.on.square", title: "iOS + Android, one JSON",
                                         body: "The same payload renders with SwiftUI here and Jetpack Compose there.",
                                         colors: [c(0.00, 0.72, 0.62), c(0.00, 0.42, 0.48)]),
                            StorySegment(icon: "checkmark.seal.fill", title: "Validated before it ships",
                                         body: "A zero-dependency validator catches bad payloads before they reach a screen.",
                                         colors: [c(0.05, 0.62, 0.55), c(0.02, 0.38, 0.42)])
                        ]),
        CapabilityStory(id: 2, label: "Live theming", ringIcon: "paintpalette.fill",
                        tint: [c(0.98, 0.55, 0.19), c(0.85, 0.30, 0.30)],
                        segments: [
                            StorySegment(icon: "paintpalette.fill", title: "Design tokens over the wire",
                                         body: "Colors, type scale and spacing ship as data. Re-theme the whole app instantly.",
                                         colors: [c(0.98, 0.55, 0.19), c(0.80, 0.28, 0.20)]),
                            StorySegment(icon: "circle.lefthalf.filled", title: "A/B test the look",
                                         body: "Run ten palettes in production and measure which one users prefer.",
                                         colors: [c(0.96, 0.45, 0.24), c(0.72, 0.20, 0.30)])
                        ]),
        CapabilityStory(id: 3, label: "Rich components", ringIcon: "square.grid.2x2.fill",
                        tint: [c(0.79, 0.24, 0.86), c(0.55, 0.18, 0.72)],
                        segments: [
                            StorySegment(icon: "square.grid.2x2.fill", title: "Charts, forms, calendars",
                                         body: "Dozens of native components — plus a clips feed and a stories player like this one.",
                                         colors: [c(0.79, 0.24, 0.86), c(0.50, 0.16, 0.68)]),
                            StorySegment(icon: "hand.tap.fill", title: "Gestures & motion built in",
                                         body: "Swipe, double-tap, spring and haptics — all declared in the contract.",
                                         colors: [c(0.70, 0.22, 0.82), c(0.42, 0.14, 0.60)])
                        ])
    ]

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

struct StorySegment {
    let icon: String
    let title: String
    let body: String
    let colors: [Color]
}

// MARK: - Rail (the entry point on Home)

struct HomeStoriesRail: View {
    @State private var openStory: CapabilityStory?
    @State private var spin = false
    @State private var appeared = false
    private let stories = CapabilityStory.all

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(stories.enumerated()), id: \.element.id) { index, story in
                    Button { openStory = story } label: { bubble(story) }
                        .buttonStyle(SDUIPressableStyle())
                        // A lively staggered spring pop-in, so the rail feels alive
                        // when the Home appears rather than snapping in flat.
                        .scaleEffect(appeared ? 1 : 0.55)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.42, dampingFraction: 0.68)
                            .delay(Double(index) * 0.06), value: appeared)
                }
            }
            // Instagram's strip is compact: minimal vertical padding so the rail
            // reads as a thin, tidy band rather than a thick block.
            .padding(.horizontal, 20).padding(.vertical, 2)
        }
        .onAppear { spin = true; appeared = true }
        #if os(iOS)
        .fullScreenCover(item: $openStory) { story in
            StoriesPlayer(stories: stories, start: story.id) { openStory = nil }
        }
        #else
        .sheet(item: $openStory) { story in
            StoriesPlayer(stories: stories, start: story.id) { openStory = nil }
        }
        #endif
    }

    private func bubble(_ story: CapabilityStory) -> some View {
        VStack(spacing: 6) {
            ZStack {
                // The Instagram-style "unseen" ring: a stroked gradient ring that
                // does one graceful sweep on appear, then settles. Thinner and
                // smaller so the strip stays compact and crisp like IG's.
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                story.tint.first ?? .purple,
                                story.tint.last ?? .pink,
                                story.tint.first ?? .purple
                            ]),
                            center: .center),
                        lineWidth: 2.75)
                    .frame(width: 62, height: 62)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.easeOut(duration: 1.0), value: spin)
                // A thin gap ring, so the cover doesn't touch the gradient — the
                // exact IG/Telegram look.
                Circle().fill(bubbleInner).frame(width: 55, height: 55)
                // The vivid cover — a saturated gradient orb, NOT a flat white
                // circle with a grey glyph. This is what makes the rail feel alive.
                Circle()
                    .fill(LinearGradient(colors: story.tint, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: story.ringIcon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    )
                    .shadow(color: (story.tint.first ?? .purple).opacity(0.30), radius: 5, y: 2)
            }
            Text(story.label).font(.caption2.weight(.semibold)).foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: 72)
    }

    private var bubbleInner: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color.white
        #endif
    }
}

// MARK: - Player

struct StoriesPlayer: View {
    let stories: [CapabilityStory]
    @State private var storyIndex: Int
    @State private var segmentIndex = 0
    @State private var progress: CGFloat = 0
    @State private var paused = false
    @State private var dragY: CGFloat = 0
    /// Live horizontal drag — the cube follows the finger by this offset.
    @State private var dragX: CGFloat = 0
    /// When the current press began — lets us tell a quick tap (advance) from a
    /// deliberate hold (pause only, never advances, anywhere on screen).
    @State private var pressStart: Date?
    /// A transient toast message (proper HIG feedback — not an inline checkmark).
    @State private var toast: String?
    @State private var liked = false
    let onClose: () -> Void

    private let tick = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()
    private let segmentDuration: CGFloat = 4.0

    init(stories: [CapabilityStory], start: Int, onClose: @escaping () -> Void) {
        self.stories = stories
        self.onClose = onClose
        _storyIndex = State(initialValue: start)
    }

    private var story: CapabilityStory { stories[storyIndex] }
    private var segment: StorySegment { story.segments[segmentIndex] }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                // Plain black behind the cube — exactly like Instagram/Snapchat
                // stories. The safe-area strips just read as black; no tint to notice.
                Color.black.ignoresSafeArea()

                // Drag-following CUBE pager: every story face sits side by side and
                // rotates around its edge by its live horizontal offset — so the face
                // follows the finger and TWO stories are visible mid-swipe.
                HStack(spacing: 0) {
                    ForEach(stories.indices, id: \.self) { i in
                        GeometryReader { pg in
                            let minX = pg.frame(in: .named("cube")).minX
                            let angle = max(-90, min(90, (minX / max(w, 1)) * 90))
                            storyFace(for: i)
                                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0),
                                                  anchor: minX < 0 ? .trailing : .leading, perspective: 0.6)
                                .brightness(-abs(angle) / 320)
                        }
                        .frame(width: w)
                    }
                }
                .frame(width: w, alignment: .leading)
                .offset(x: -CGFloat(storyIndex) * w + dragX)
                .coordinateSpace(name: "cube")
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: storyIndex)
                .offset(y: dragY)
                .scaleEffect(1 - min(dragY, 240) / 1400)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: dragY)

                // One unified gesture: horizontal drives the cube live, vertical
                // dismisses, a tap moves segments, a hold pauses.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                if pressStart == nil { pressStart = Date() }
                                paused = true
                                if abs(v.translation.width) > abs(v.translation.height) {
                                    dragX = rubberBand(v.translation.width, w: w); dragY = 0
                                } else {
                                    dragY = max(0, v.translation.height); dragX = 0
                                }
                            }
                            .onEnded { v in
                                paused = false
                                let held = pressStart.map { Date().timeIntervalSince($0) } ?? 0
                                pressStart = nil
                                settleGesture(v, w: w, midX: geo.size.width * 0.33, held: held)
                            }
                    )

                // Fixed close control — never rotates with the cube, always tappable.
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                            .onTapGesture { onClose() }
                    }
                    Spacer()
                }
                // Sit on the header row, clear of the thin progress bars up top.
                .padding(.horizontal, 16).padding(.top, 34)
                .zIndex(100)

                // A generous dark bottom band — Instagram keeps a roomy dark zone
                // under the story so the actions read cleanly over any content.
                // Fixed (never rotates with the cube), fades out while dismissing.
                VStack {
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.45), .black.opacity(0.92), .black],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 260)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .opacity(Double(max(0, 1 - dragY / 70)))
                .zIndex(94)

                // Instagram-style action bar sitting in that dark band. In a social
                // app this is the reply field + like/share; here it's the developer
                // payoff — grab the JSON that renders this very screen, like it, share
                // it. Fixed (never rotates with the cube) and hidden while dismissing.
                VStack {
                    Spacer()
                    actionBar
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 26)
                // Fade proportionally with the pull, so it rides the spring back in
                // smoothly instead of flashing when the drag snaps to zero.
                .opacity(Double(max(0, 1 - dragY / 70)))
                .zIndex(95)

                // Transient HIG toast (glass capsule, no inline checkmark), floats
                // above the action bar and auto-dismisses.
                if let toast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.callout.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
                            .padding(.bottom, 96)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .task(id: toast) {
                                try? await Task.sleep(nanoseconds: 1_900_000_000)
                                withAnimation(.easeOut(duration: 0.28)) { self.toast = nil }
                            }
                    }
                    .allowsHitTesting(false)
                    .zIndex(120)
                }
            }
        }
        .onReceive(tick) { _ in advance() }
        .onAppear { progress = 0 }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
    }

    private func rubberBand(_ dx: CGFloat, w: CGFloat) -> CGFloat {
        if (storyIndex == 0 && dx > 0) || (storyIndex == stories.count - 1 && dx < 0) { return dx * 0.32 }
        return dx
    }

    // MARK: - Bottom action bar

    private var actionBar: some View {
        VStack(spacing: 12) {
            // The primary CTA — styled like a sponsored story's "Book now" pill: a
            // prominent, centred frosted-glass capsule. Here it hands the developer
            // the JSON that renders this very screen.
            Button(action: copyJSON) {
                HStack(spacing: 8) {
                    Image(systemName: "curlybraces").font(.system(size: 16, weight: .semibold))
                    Text("Copy this screen's JSON")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 15)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
                .contentShape(Capsule())
            }
            .buttonStyle(SDUIPressableStyle())

            // Sponsored-style footer row: a label on the left, reactions on the right.
            HStack(spacing: 4) {
                Text("SDUI showcase")
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 8)
                Button {
                    liked.toggle()
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                } label: { actionIcon(liked ? "heart.fill" : "heart", tint: liked ? .pink : .white) }
                .buttonStyle(SDUIPressableStyle())
                Button(action: copyJSON) { actionIcon("square.and.arrow.down", tint: .white) }
                .buttonStyle(SDUIPressableStyle())
            }
        }
    }

    private func actionIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }

    /// A representative payload for the current story — the point being that in a
    /// real app this button would hand the developer the exact contract on screen.
    private func copyJSON() {
        let story = stories[min(storyIndex, stories.count - 1)]
        let seg = story.segments[min(segmentIndex, story.segments.count - 1)]
        let sample = """
        {
          "type": "screen",
          "showcase": "\(story.label)",
          "content": [
            { "type": "icon", "name": "\(seg.icon)" },
            { "type": "text", "style": "title", "value": "\(seg.title)" },
            { "type": "text", "style": "body", "value": "\(seg.body)" }
          ]
        }
        """
        #if os(iOS)
        UIPasteboard.general.string = sample
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { toast = "Copied to clipboard" }
    }

    private func settleGesture(_ v: DragGesture.Value, w: CGFloat, midX: CGFloat, held: Double) {
        let dx = v.translation.width, dy = v.translation.height
        // Vertical (and no horizontal cube drag active) → dismiss or bounce back.
        if dragX == 0, abs(dy) > abs(dx) {
            if dy > 130 || v.predictedEndTranslation.height > 320 { onClose(); return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragY = 0 }
            return
        }
        // Horizontal cube drag → snap to the nearest story.
        if dragX != 0 {
            let fwd = dx < -w * 0.28 || v.predictedEndTranslation.width < -w * 0.5
            let back = dx > w * 0.28 || v.predictedEndTranslation.width > w * 0.5
            // Swiping the cube forward past the LAST story closes the player — the
            // natural end-of-reel behaviour in Instagram/Snapchat.
            if fwd, storyIndex >= stories.count - 1 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragX = 0 }
                onClose(); return
            }
            var next = storyIndex
            if fwd, storyIndex < stories.count - 1 { next += 1 }
            else if back, storyIndex > 0 { next -= 1 }
            let changed = next != storyIndex
            if changed { segmentIndex = 0; progress = 0 }
            #if os(iOS)
            if changed { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            #endif
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { storyIndex = next; dragX = 0 }
            return
        }
        // A tap — but ONLY if it was quick. A deliberate hold (anywhere, incl. the
        // right side) just paused and must not advance on release.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragX = 0; dragY = 0 }
        if held < 0.28 {
            if v.location.x < midX { goBack() } else { goForward() }
        }
    }

    // MARK: face

    @ViewBuilder private func storyFace(for i: Int) -> some View {
        let s = stories[i]
        let segI = (i == storyIndex) ? segmentIndex : 0
        let prog: CGFloat = (i == storyIndex) ? progress : 0
        let seg = s.segments[segI]
        // Only the current story and its immediate neighbours (which are visible on
        // a cube face mid-swipe) render full content; the rest are just a cheap
        // gradient, so the pager stays at 60fps no matter how many stories exist.
        let near = abs(i - storyIndex) <= 1
        ZStack {
            // No `.ignoresSafeArea()` — the story sits WITHIN the safe area so the
            // black base shows as clean top/bottom strips, and the whole face is
            // gently rounded (modern Instagram: a rounded card on black).
            LinearGradient(colors: seg.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if near {
                LinearGradient(colors: [.black.opacity(0.16), .clear, .black.opacity(0.22)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 14) {
                    progressBars(for: s, active: segI, progress: prog)
                    header(for: s)
                    Spacer()
                    content(for: seg)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func progressBars(for s: CapabilityStory, active: Int, progress: CGFloat) -> some View {
        HStack(spacing: 5) {
            ForEach(s.segments.indices, id: \.self) { i in
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white)
                                .frame(width: geo.size.width * (i < active ? 1 : (i > active ? 0 : progress)))
                        }
                }
                .frame(height: 3)
            }
        }
    }

    private func header(for s: CapabilityStory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: s.ringIcon)
                .font(.footnote.weight(.bold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.2), in: Circle())
            Text(s.label).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private func content(for seg: StorySegment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: seg.icon)
                .font(.system(size: 46, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text(seg.title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(seg.body)
                .font(.title3).foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: logic

    private func advance() {
        guard !paused, dragY == 0 else { return }
        progress += 0.02 / segmentDuration
        if progress >= 1 { goForward() }
    }

    private func goForward() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        if segmentIndex < story.segments.count - 1 {
            // Snap the bars instantly (no drain animation), never wrapped in
            // withAnimation — otherwise the previous bar keeps animating while the
            // next segment is already ticking.
            segmentIndex += 1; progress = 0
        } else if storyIndex < stories.count - 1 {
            forwardStory()
        } else {
            onClose()
        }
    }

    /// Jump straight to the next story (used by tap-through end and horizontal
    /// swipe). Progress snaps; only the cube animates.
    private func forwardStory() {
        guard storyIndex < stories.count - 1 else { onClose(); return }
        segmentIndex = 0; progress = 0
        storyIndex += 1   // .animation(value: storyIndex) springs the cube
    }

    private func backwardStory() {
        guard storyIndex > 0 else { progress = 0; return }
        segmentIndex = 0; progress = 0
        storyIndex -= 1
    }

    private func goBack() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        if progress > 0.15 {
            progress = 0
        } else if segmentIndex > 0 {
            segmentIndex -= 1; progress = 0
        } else if storyIndex > 0 {
            segmentIndex = 0; progress = 0
            storyIndex -= 1
        } else {
            progress = 0
        }
    }
}

/// One face of the story cube: a 3D Y-axis rotation around an edge, with
/// perspective depth and a shading dip as it turns away.
#endif

#if canImport(SwiftUI)
import SwiftUI
import SDUICore
import SDUIRender
#if canImport(UIKit)
import UIKit
#endif

/// The Home tab, built as a **calm-but-rich showcase** in the spirit of Apple
/// Mail: restrained color, but real content-bearing CARDS with soft shadows and
/// depth — never flat list rows. Every card is a designed, instant surface drawn
/// from the catalog manifest (no live `SDUIScreenView` renders anywhere). Taps
/// open the real SDUI screens through the same `CatalogStack` + `catalogLink`
/// mechanism the rest of the catalog uses.
///
/// Top → bottom: a quiet header, the one intentionally colorful stories rail, a
/// rich featured hero card, then grouped **showcase carousels** of shadowed
/// cards that SHOW each screen (a muted-tint icon chip + title + descriptor), and
/// a closing wide "pipeline" card. One accent color; per-card tints are muted and
/// desaturated. No rainbow gradients, no full-bleed banners, no badges.
public struct AirbnbHomeView: View {
    private let categories: [PlaygroundCategory]
    private let tokens: JSONValue

    @State private var path: [CatalogDestination] = []
    @State private var didOpenDebug = false

    public init(categories: [PlaygroundCategory] = ScreenLibrary.catalog(),
                tokens: JSONValue = ScreenLibrary.tokens()) {
        self.categories = categories
        self.tokens = tokens
    }

    private var accent: Color { Color(.sRGB, red: 0.357, green: 0.357, blue: 0.941) }

    public var body: some View {
        CatalogStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    header
                    HomeStoriesRail()
                    bannerCarousel
                    ForEach(showcaseSections) { section in
                        showcaseCarousel(section)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 44)
            }
            .sduiHiddenScrollIndicators()
            .background(SpatialBackground())
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
            .onAppear(perform: openDebugScreenIfRequested)
        }
        .tint(accent)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SDUI")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)
            Text("Server-Driven UI, live from JSON")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    // MARK: - Featured hero card

    /// The top promo banners — the featured hero and the pipeline card — combined
    /// into ONE horizontal, swipeable rail (super-app promo-banner language). Each
    /// banner is a fixed width just under the screen so the next one peeks at the
    /// trailing edge. Tap still opens the banner's real destination; same soft-shadow
    /// card look and the same tightened ~16pt horizontal inset as the rest of Home.
    private var bannerCarousel: some View {
        Group {
            let banners = self.banners
            if !banners.isEmpty {
                GeometryReader { geo in
                    let inset: CGFloat = 16
                    let peek: CGFloat = 26
                    let cardWidth = max(240, geo.size.width - inset - peek)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(banners) { banner in
                                catalogLink(banner.destination) {
                                    BannerCard(banner: banner, accent: accent)
                                        .frame(width: cardWidth)
                                }
                                .buttonStyle(SDUIPressableStyle())
                            }
                        }
                        .padding(.horizontal, inset)
                        .padding(.vertical, 10)
                    }
                    .padding(.vertical, -10)
                }
                .frame(height: 176)
            }
        }
    }

    /// The banners shown in the top rail: the featured hero first, then the Figma →
    /// tokens pipeline banner, in that order.
    private var banners: [BannerModel] {
        var out: [BannerModel] = []
        if let feature = featured {
            out.append(BannerModel(eyebrow: feature.eyebrow.uppercased(),
                                   icon: feature.icon,
                                   title: feature.title,
                                   subtitle: feature.subtitle,
                                   tint: accent,
                                   destination: feature.destination))
        }
        if let category = categories.first(where: { $0.name == "Figma & Tokens" }),
           let figma = category.examples.first {
            out.append(BannerModel(eyebrow: "PIPELINE",
                                   icon: screenIcon(for: figma.screenId, fallback: category.icon),
                                   title: "From Figma to live theming",
                                   subtitle: figma.subtitle.isEmpty ? "Turn design tokens into live theming" : figma.subtitle,
                                   tint: mutedTint(for: category),
                                   destination: .example(figma)))
        }
        return out
    }

    private var featured: FeaturedItem? {
        guard let dest = firstExample("Real apps", "discover") else { return nil }
        return FeaturedItem(eyebrow: "Featured",
                            icon: "square.stack.3d.up.fill",
                            title: "Ship whole screens from JSON",
                            subtitle: "One contract renders live on iOS and Android — no app-store release.",
                            destination: dest)
    }

    // MARK: - Showcase carousels

    /// The sections that get their own horizontal carousel of showcase cards, in
    /// catalog order. "Figma & Tokens" is surfaced separately as the pipeline card.
    private var showcaseSections: [ShowcaseSection] {
        let blurbs: [String: String] = [
            "Real apps": "Whole products, shipped from JSON",
            "Live": "Live data, charts and motion",
            "Design System": "Every primitive, one tap away",
            "Interactions": "Gestures, springs and effects",
            "Engine": "Fetch, lists, tables — the core"
        ]
        let order = ["Real apps", "Live", "Design System", "Interactions", "Engine"]
        return order.compactMap { name in
            guard let category = categories.first(where: { $0.name == name }),
                  !category.examples.isEmpty else { return nil }
            let tint = mutedTint(for: category)
            let cards = category.examples.map { ex in
                ShowcaseCardModel(
                    icon: screenIcon(for: ex.screenId, fallback: category.icon),
                    title: ex.name,
                    subtitle: ex.subtitle.isEmpty ? "Open screen" : ex.subtitle,
                    tint: tint,
                    destination: .example(ex))
            }
            return ShowcaseSection(title: name,
                                   subtitle: blurbs[name] ?? "\(category.examples.count) screens",
                                   cards: cards)
        }
    }

    private func showcaseCarousel(_ section: ShowcaseSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(section.title, section.subtitle)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(section.cards) { card in
                        catalogLink(card.destination) {
                            ShowcaseCard(card: card)
                        }
                        .buttonStyle(SDUIPressableStyle())
                    }
                }
                // Give the horizontal scroller room on every side so the soft card
                // shadow is never clipped by the ScrollView's bounds.
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            // Pull the carousel's own vertical padding back out of the section
            // rhythm so the extra breathing room doesn't inflate inter-section gaps.
            .padding(.vertical, -10)
        }
    }

    // MARK: - Shared bits

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    /// A lively per-category icon tint. Per HIG, SF Symbol / icon accents can carry
    /// healthy, vibrant color while surfaces stay neutral — so the chip GLYPH keeps
    /// the category's real hue at a tasteful saturation (never over-desaturated to a
    /// lifeless gray), and the chip fill is a soft translucent wash of that same hue.
    private func mutedTint(for category: PlaygroundCategory) -> Color {
        guard let hex = category.colors.first else { return accent }
        return livelyTint(hex)
    }

    private func livelyTint(_ hex: String) -> Color {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return accent }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        // Keep ~92% of the source hue: only a whisper of a pull toward gray so the
        // color stays healthy and vibrant (HIG-level lively) rather than flat/dull.
        let keep = 0.92
        let gray = 0.5
        let mr = gray + (r - gray) * keep
        let mg = gray + (g - gray) * keep
        let mb = gray + (b - gray) * keep
        return Color(.sRGB, red: mr, green: mg, blue: mb)
    }

    private func firstExample(_ category: String, _ screen: String) -> CatalogDestination? {
        guard let category = categories.first(where: { $0.name == category }),
              !category.examples.isEmpty else { return nil }
        let target = category.examples.first { $0.screenId == screen } ?? category.examples[0]
        return .example(target)
    }

    // MARK: - Debug

    private func example(withId id: String) -> PlaygroundExample? {
        categories.flatMap(\.examples).first { $0.screenId == id }
    }

    /// Debug: `SDUI_SCREEN=<screen.id>` opens straight to that screen for snapshots.
    private func openDebugScreenIfRequested() {
        guard !didOpenDebug, path.isEmpty,
              let target = ProcessInfo.processInfo.environment["SDUI_SCREEN"]
        else { return }
        let hit = example(withId: target)
            ?? ScreenLibrary.rawJSON(withId: target).map {
                PlaygroundExample(screenId: target, name: target, subtitle: "", json: $0)
            }
        guard let hit else { return }
        didOpenDebug = true
        path.append(.example(hit))
    }
}

// MARK: - Models

private struct FeaturedItem {
    let eyebrow: String
    let icon: String
    let title: String
    let subtitle: String
    let destination: CatalogDestination
}

private struct ShowcaseSection: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let cards: [ShowcaseCardModel]
}

private struct ShowcaseCardModel: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let destination: CatalogDestination
}

private struct BannerModel: Identifiable {
    let id = UUID()
    let eyebrow: String
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let destination: CatalogDestination
}

// MARK: - Banner card

/// One promo banner in the top swipeable rail: an elevated grouped surface with a
/// soft shadow, a tinted icon chip, an eyebrow label, a bold headline and a calm
/// subtitle. Fixed height so the banners read as a uniform paged rail; width is set
/// by the carousel so the next banner peeks at the trailing edge. Depth via shadow.
private struct BannerCard: View {
    let banner: BannerModel
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: banner.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(banner.tint)
                    .frame(width: 44, height: 44)
                    .background(banner.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(banner.eyebrow)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(banner.title)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(banner.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .padding(18)
        .softCard(20)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Showcase card

/// One rich showcase card in a carousel: a white/grouped rounded surface with a
/// soft shadow (Mail/Inbox card language), a muted-tint icon chip, a bold title
/// and a one-line descriptor. Fixed width so cards read as a paged rail.
private struct ShowcaseCard: View {
    let card: ShowcaseCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: card.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(card.tint)
                .frame(width: 46, height: 46)
                .background(card.tint.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(card.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 210, height: 158, alignment: .topLeading)
        .softCard(18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Soft card surface

private extension View {
    /// The Mail/Inbox card language: a solid grouped surface, a hairline border
    /// and a soft drop shadow with a touch more depth than `glassPanel`. Adapts to
    /// light/dark and stays platform-safe (no `Color(uiColor:)` off iOS).
    @ViewBuilder func softCard(_ radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if os(iOS)
        self
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        #else
        self
            .background(.regularMaterial, in: shape)
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        #endif
    }
}
#endif

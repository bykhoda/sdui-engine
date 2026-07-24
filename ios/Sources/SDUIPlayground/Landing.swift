#if canImport(SwiftUI)
import SwiftUI
import SDUICore
import SDUIRender
#if canImport(UIKit)
import UIKit
#endif

/// The demo's root: a product-style landing that pitches Server-Driven UI, a live
/// catalog of feature screens, and a navigation demo. The landing's call to
/// action jumps straight into the catalog.
public struct SDUIDemoRootView: View {
    @AppStorage("sduiAppearance") private var appearance = "system"
    public init() {
        #if canImport(UIKit)
        // Pin one tab-bar appearance for every scroll position, so the bar keeps
        // its material and never flips to the page colour when you reach the
        // bottom of a screen (the default scroll-edge behaviour).
        let bar = UITabBarAppearance()
        bar.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = bar
        UITabBar.appearance().scrollEdgeAppearance = bar
        #endif
    }

    // HIG tab structure: tabs are destinations, not brand names, with consistent
    // filled SF Symbols. Home (editorial), Browse (catalog), Design (the Figma /
    // tokens pipeline), and Settings.
    public var body: some View {
        TabView {
            SDUIHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            SDUIBrowseView()
                .tabItem { Label("Browse", systemImage: "square.grid.2x2.fill") }
            SDUIFigmaTabView()
                .tabItem { Label("Design", systemImage: "circle.hexagongrid.fill") }
            SDUISettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Color(.sRGB, red: 0.357, green: 0.357, blue: 0.941))
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
    }
}

/// Settings — designed in the app's own card language (not a bare native Form):
/// an appearance selector styled like iOS wallpaper light/dark tiles, an engine
/// summary, and a short explainer, all on the shared grouped canvas.
struct SDUISettingsView: View {
    @AppStorage("sduiAppearance") private var appearance = "system"

    private var accent: Color { Color(.sRGB, red: 0.357, green: 0.357, blue: 0.941) }

    private struct Appearance: Identifiable {
        let id: String; let icon: String; let label: String
    }
    private let appearances: [Appearance] = [
        .init(id: "system", icon: "iphone", label: "System"),
        .init(id: "light", icon: "sun.max.fill", label: "Light"),
        .init(id: "dark", icon: "moon.stars.fill", label: "Dark")
    ]

    var body: some View {
        SDUINavContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    appearanceSection
                    engineSection
                    backendSection
                    Text("SDUI — an open server-driven UI engine. One JSON contract, native on every platform.")
                        .font(.footnote).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(SpatialBackground())
            .navigationTitle("Settings")
        }
    }

    // MARK: Appearance — three tappable tiles, selected one fills with the accent.

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Appearance")
            HStack(spacing: 10) {
                ForEach(appearances) { option in
                    let selected = appearance == option.id
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { appearance = option.id }
                    } label: {
                        VStack(spacing: 9) {
                            Image(systemName: option.icon).font(.system(size: 21, weight: .semibold))
                            Text(option.label).font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(selected ? accent : Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(selected ? 0 : 0.06), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Engine — a stat card in the shared elevated-panel language.

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Engine")
            VStack(spacing: 0) {
                settingRow(icon: "number", tint: accent, title: "Contract version", value: "0.1")
                Divider().padding(.leading, 58)
                settingRow(icon: "square.on.square", tint: .blue, title: "Platforms", value: "iOS · Android")
                Divider().padding(.leading, 58)
                settingRow(icon: "rectangle.stack.fill", tint: .purple, title: "Screens bundled",
                           value: "\(ScreenLibrary.catalog().flatMap(\.examples).count)")
            }
            .glassPanel(18)
        }
    }

    // MARK: Backend explainer.

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Icons & images")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(.teal)
                        .frame(width: 42, height: 42)
                        .background(Color.teal.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Serve from your backend").font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                Text("The image component loads any URL your backend returns; on Android an icon resolver maps names to your own drawables. Design tokens come from Figma — see the Design tab.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(18)
        }
    }

    // MARK: Building blocks

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private func settingRow(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title).font(.body).foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

// MARK: - VisionOS-style glass system

/// The app canvas — a calm, system-grouped background. Solid and cheap to draw:
/// no heavy blurs, so scrolling stays smooth and text on the cards stays legible.
struct SpatialBackground: View {
    var body: some View {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        #else
        Color.gray.opacity(0.12).ignoresSafeArea()
        #endif
    }
}

extension View {
    /// A clean, readable elevated card: a solid grouped surface, a hairline border
    /// and a soft shadow. Adapts to light/dark automatically. No material blur —
    /// fast to render and high-contrast for text.
    @ViewBuilder func glassPanel(_ radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if os(iOS)
        self
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        #else
        self
            .background(.regularMaterial, in: shape)
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        #endif
    }
}

/// A polished landing page that sells the idea: build your app from JSON, with no
/// frontend developers — rendered in a visionOS-style glass language.
public struct SDUILandingView: View {
    private let onExplore: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    public init(onExplore: @escaping () -> Void = {}) {
        self.onExplore = onExplore
    }

    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let title: String
        let detail: String
    }

    private let features: [Feature] = [
        .init(icon: "bolt.fill", tint: .orange,
              title: "Ship instantly", detail: "Change any screen from your backend — no app-store release."),
        .init(icon: "square.on.square", tint: .blue,
              title: "One JSON, every platform", detail: "The same contract renders on iOS and Android, natively."),
        .init(icon: "checkmark.shield.fill", tint: .green,
              title: "Safe by design", detail: "Every payload is validated before it reaches a device."),
        .init(icon: "hand.tap.fill", tint: .purple,
              title: "Truly native", detail: "Real gestures, charts, animations and navigation — never a web view.")
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                VStack(spacing: 12) {
                    ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                        featureCard(feature)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 24)
                            .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.06 * Double(index)), value: appeared)
                    }
                }
                howItWorks
                cta
            }
            .padding(20)
            .padding(.bottom, 8)
        }
        .background(SpatialBackground())
        .onAppear { appeared = true }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.white.opacity(0.18)))
                Spacer()
                Text("SERVER-DRIVEN UI")
                    .font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 22)
            Text("Build your app.\nWithout frontend\ndevelopers.")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Native screens, streamed straight from JSON.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.75)).padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background {
            ZStack {
                heroBackground
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 26, y: 16)
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: appeared)
    }

    @ViewBuilder private var heroBackground: some View {
        if #available(iOS 18, macOS 15, *) {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    .init(0, 0), .init(0.5, 0), .init(1, 0),
                    .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                    .init(0, 1), .init(0.5, 1), .init(1, 1)
                ],
                colors: [
                    Color(.sRGB, red: 0.10, green: 0.16, blue: 0.42), .indigo, Color(.sRGB, red: 0.35, green: 0.20, blue: 0.55),
                    .blue, Color(.sRGB, red: 0.20, green: 0.28, blue: 0.60), .purple,
                    Color(.sRGB, red: 0.08, green: 0.12, blue: 0.32), .indigo, Color(.sRGB, red: 0.25, green: 0.18, blue: 0.50)
                ])
        } else {
            LinearGradient(colors: [Color(.sRGB, red: 0.12, green: 0.18, blue: 0.45), .indigo, .purple],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Feature card

    private func featureCard(_ feature: Feature) -> some View {
        HStack(spacing: 14) {
            Image(systemName: feature.icon)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(feature.tint)
                .frame(width: 42, height: 42)
                .background(feature.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(feature.detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(20)
    }

    // MARK: How it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HOW IT WORKS").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 6)
            HStack(spacing: 10) {
                step(1, "Author", "describe in JSON")
                step(2, "Validate", "against the schema")
                step(3, "Render", "native on device")
            }
        }
        .padding(.top, 4)
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Text("\(n)")
                .font(.headline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(.sRGB, red: 0.357, green: 0.357, blue: 0.941)))
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
            Text(detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassPanel(18)
    }

    // MARK: CTA

    private var cta: some View {
        Button(action: onExplore) {
            HStack(spacing: 8) {
                Text("Explore live examples").font(.headline)
                Image(systemName: "arrow.right").font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                LinearGradient(colors: [Color(.sRGB, red: 0.357, green: 0.357, blue: 0.941), .indigo],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .blue.opacity(0.45), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

#if DEBUG
@available(iOS 17, macOS 14, *)
#Preview("Landing") { SDUILandingView() }
#endif
#endif

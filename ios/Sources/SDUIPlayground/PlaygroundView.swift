#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import SDUICore
import SDUIRender
import SDUINetwork
#if canImport(UIKit)
import UIKit
#endif

/// Shared networking for the sandbox. Maps the logical `service` names used by
/// bundled screens to real base URLs. Swap `demo` for your own design-system
/// endpoint to render live documents. Built without force-unwraps: a malformed
/// URL is simply dropped rather than crashing.
enum PlaygroundData {
    static let loader: DataLoader = {
        var services: [String: URL] = [:]
        if let demo = URL(string: "https://jsonplaceholder.typicode.com") {
            services["demo"] = demo
        }
        return DataLoader(resolver: StaticServiceResolver(services: services))
    }()
}

/// A minimal host that surfaces SDUI actions as a transient toast, so taps and
/// navigation are observable without wiring a real router. `share` presents the
/// real system share sheet.
@MainActor
final class PlaygroundHost: ObservableObject, SDUIHostDelegate {
    @Published var lastEvent: String?
    /// A screen being presented as a bottom sheet from a `navigate` action.
    @Published var sheetScreen: PlaygroundExample?
    /// The capability-story index the full-screen stories player should open at,
    /// set by a `custom` action named "story" fired from a home story bubble.
    @Published var openStoryIndex: Int?
    /// Set by a presented sheet so a `dismiss` action can close it.
    var onDismiss: (() -> Void)?

    func dismiss() { onDismiss?() }

    func navigate(to screen: String, params: [String: JSONValue], transition: String) {
        // sheet / bottomSheet transitions present the target screen as a real
        // bottom sheet; everything else is surfaced as a toast in this sandbox.
        if transition == "sheet" || transition == "bottomSheet",
           let json = ScreenLibrary.rawJSON(withId: screen) {
            sheetScreen = PlaygroundExample(screenId: screen, name: screen, subtitle: "", json: json)
        } else {
            flash("navigate → \(screen)")
        }
    }
    func showToast(message: String, style: String?) { flash(message) }
    func custom(name: String, payload: JSONValue?) {
        // Home story bubbles open the real segmented stories player at their index.
        if name == "story" {
            openStoryIndex = payload?["index"]?.doubleValue.map { Int($0) } ?? 0
            return
        }
        flash("custom → \(name)")
    }

    func share(text: String?, url: String?) {
        #if canImport(UIKit)
        var items: [Any] = []
        if let text, !text.isEmpty { items.append(text) }
        if let url, let u = URL(string: url) { items.append(u) }
        guard !items.isEmpty, let window = Self.keyWindow() else { flash("share"); return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad requires an anchor for the popover; centre it on the window.
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = window
            pop.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        Self.topViewController(from: window)?.present(sheet, animated: true)
        #else
        flash("share \(url ?? text ?? "")")
        #endif
    }

    private func flash(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { lastEvent = text }
    }

    #if canImport(UIKit)
    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
    private static func topViewController(from window: UIWindow) -> UIViewController? {
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
    #endif
}

// MARK: - Catalog (master)

/// The Home tab. Its visual design lives in ``ShowcaseHomeView`` (an an editorial showcase
/// -grade product showcase); this wrapper preserves the public
/// `SDUIPlaygroundView` entry point and its initializer so call sites and the
/// tab bar are unchanged. Card taps push the real SDUI screen through the same
/// `CatalogStack` + `catalogLink` mechanism the rest of the catalog uses.
public struct SDUIPlaygroundView: View {
    private let categories: [PlaygroundCategory]
    private let tokens: JSONValue

    public init(categories: [PlaygroundCategory] = ScreenLibrary.catalog(),
                tokens: JSONValue = ScreenLibrary.tokens()) {
        self.categories = categories
        self.tokens = tokens
    }

    public var body: some View {
        ShowcaseHomeView(categories: categories, tokens: tokens)
    }
}

// MARK: - Browse tab

/// The full catalog as a flat, scannable list — its own tab, so Home stays light.
/// Single-screen categories push the screen directly (minimum navigation depth).
public struct SDUIBrowseView: View {
    private let categories: [PlaygroundCategory]
    private let tokens: JSONValue
    @State private var path: [CatalogDestination] = []

    public init(categories: [PlaygroundCategory] = ScreenLibrary.catalog(),
                tokens: JSONValue = ScreenLibrary.tokens()) {
        self.categories = categories
        self.tokens = tokens
    }

    private var browseCategories: [PlaygroundCategory] {
        // Browse is the full index — every category with a count. Figma has its own
        // tab, so it's the only one left out. (Home is the curated shelves; a search
        // tab overlapping the editorial home is the App Store pattern.)
        categories.filter { $0.name != "Figma & Tokens" && !$0.examples.isEmpty }
    }

    public var body: some View {
        CatalogStack(path: $path) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(browseCategories.enumerated()), id: \.element.id) { index, category in
                        Group {
                            if category.examples.count == 1, let only = category.examples.first {
                                catalogLink(.example(only)) { BrowseRow(category: category) }
                            } else {
                                catalogLink(.category(category)) { BrowseRow(category: category) }
                            }
                        }
                        .buttonStyle(PressableRow())
                        if index < browseCategories.count - 1 { Divider().padding(.leading, 58) }
                    }
                }
                .glassPanel(20)
                .padding(20)
            }
            .background(SpatialBackground())
            .navigationTitle("Browse")
        }
    }
}

// MARK: - Figma tab

/// The Figma pipeline as a first-class destination: the live tokens screen
/// (rendered from JSON like everything else) under a native title.
public struct SDUIFigmaTabView: View {
    private let tokens: JSONValue
    private let example: PlaygroundExample?
    @State private var showConverter = false

    public init(categories: [PlaygroundCategory] = ScreenLibrary.catalog(),
                tokens: JSONValue = ScreenLibrary.tokens()) {
        self.tokens = tokens
        self.example = categories.flatMap(\.examples).first { $0.screenId == "figma" }
    }

    public var body: some View {
        SDUINavContainer {
            VStack(spacing: 0) {
                Group {
                    if let example {
                        ScreenDetailView(example: example, tokens: tokens, embedded: true)
                    } else {
                        Text("Figma screen not bundled").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Design")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // The Figma → tokens converter is a top-right nav action now — modern and
            // clear of the tab bar, not a pinned bottom button competing with it.
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showConverter = true } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .accessibilityLabel("Convert Figma tokens")
                }
            }
            .sheet(isPresented: $showConverter) { FigmaConverterView() }
        }
    }
}

/// Relevant SF Symbol per design-system / engine screen, so cards and rows read
/// distinctly instead of repeating one category glyph.
func screenIcon(for id: String, fallback: String) -> String {
    switch id {
    case "buttons":    return "hand.point.up.left.fill"
    case "typography": return "textformat"
    case "layout":     return "rectangle.3.group.fill"
    case "components": return "cube.fill"
    case "cards":      return "rectangle.stack.fill"
    case "controls":   return "switch.2"
    case "inputs":     return "character.cursor.ibeam"
    case "feedback":   return "exclamationmark.bubble.fill"
    case "document":   return "doc.text.fill"
    case "actions":    return "bolt.fill"
    case "gestures":   return "hand.draw.fill"
    case "animation":  return "wand.and.rays"
    case "lists":      return "list.bullet.rectangle.fill"
    case "reorder":    return "arrow.up.arrow.down"
    case "calendar":   return "calendar"
    case "table":      return "tablecells"
    case "clips":      return "play.rectangle.fill"
    case "alert_sheet": return "bell.badge.fill"
    // Real-app flagships — distinct glyphs so the Home rows don't all share one.
    case "cart":       return "cart.fill"
    case "messenger":  return "bubble.left.and.bubble.right.fill"
    case "feed":       return "newspaper.fill"
    case "discover":   return "sparkles"
    case "product":    return "tag.fill"
    case "inbox":      return "tray.full.fill"
    case "settings":   return "gearshape.fill"
    case "delivery":   return "shippingbox.fill"
    case "figma":      return "paintbrush.pointed.fill"
    case "fitness":    return "figure.run"
    case "gym":        return "dumbbell.fill"
    case "stocks":     return "chart.line.uptrend.xyaxis"
    case "weather":    return "cloud.sun.fill"
    case "music":      return "music.note"
    case "todo":       return "checklist"
    case "paywall":    return "crown.fill"
    case "signup":     return "person.crop.circle.fill"
    case "gallery":    return "photo.on.rectangle.angled"
    default:           return fallback
    }
}

/// One category in the Browse list — flat, scannable, Settings-style.
private struct BrowseRow: View {
    let category: PlaygroundCategory

    var body: some View {
        let glyph = color(category.colors.last)
        let count = category.examples.count
        return HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(glyph)
                .frame(width: 32, height: 32)
                .background(glyph.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(category.name).font(.body).foregroundStyle(.primary)
            Spacer(minLength: 8)
            if count > 1 {
                Text("\(count)").font(.subheadline).foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// The screens inside one category — flat rows, same language as Browse.
struct CategoryScreensView: View {
    let category: PlaygroundCategory
    let tokens: JSONValue

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(category.examples.enumerated()), id: \.element.id) { index, example in
                    catalogLink(.example(example)) {
                        CatalogRow(icon: screenIcon(for: example.screenId, fallback: category.icon),
                                   tint: color(category.colors.last),
                                   title: example.name, subtitle: example.subtitle)
                    }
                    .buttonStyle(PressableRow())
                    if index < category.examples.count - 1 { Divider().padding(.leading, 58) }
                }
            }
            .glassPanel(20)
            .padding(20)
        }
        .background(SpatialBackground())
        .navigationTitle(category.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// One catalog card row: a gradient icon tile, a title and a subtitle.
private struct CatalogRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 11).padding(.horizontal, 14)
        .contentShape(Rectangle())
    }
}

/// A subtle press-down highlight so cards feel tappable.
private struct PressableRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private extension View {
    /// Liquid Glass on iOS/macOS 26+, with a material fallback for older systems
    /// so the same code stays beautiful across OS versions.
    @ViewBuilder func sduiGlass<S: Shape>(_ shape: S) -> some View {
        // `glassEffect` only exists in the iOS/macOS 26 SDK (Xcode 26 → Swift 6.2+).
        // A runtime `#available` check is not enough — the symbol must resolve at
        // compile time — so gate the whole branch on the compiler/SDK version, and
        // fall back to a material on every older Xcode (which is what CI and most
        // contributors build with). Keeps the repo compiling on any recent Xcode.
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        #else
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        #endif
    }
}

private func color(_ hex: String?) -> Color {
    guard var s = hex else { return .gray }
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt64(s, radix: 16) else { return .gray }
    return Color(.sRGB,
                 red: Double((v >> 16) & 0xFF) / 255,
                 green: Double((v >> 8) & 0xFF) / 255,
                 blue: Double(v & 0xFF) / 255)
}

// MARK: - Detail

/// Renders a single screen full-bleed. One toolbar button reveals its JSON in a
/// sheet you can edit while the screen re-renders behind it.
struct ScreenDetailView: View {
    private let example: PlaygroundExample
    private let tokens: JSONValue
    /// True when hosted inside a tab (no push): hides the custom back button.
    private let embedded: Bool
    /// Decided from the raw payload in `init` so the immersive-vs-standard body is
    /// stable from the first frame — switching bodies after an async parse leaves
    /// the nav-bar appearance stale (an opaque bar over an edge-to-edge screen).
    private let declaredImmersive: Bool

    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dismiss) private var dismiss
    @State private var jsonText: String
    @State private var document: SDUIDocument?
    @State private var parseError: String?
    @State private var showCode = false
    @State private var showExporter = false
    @State private var copied = false
    @State private var showTeach = false
    @State private var teachDrag: CGFloat = 0
    @StateObject private var host = PlaygroundHost()
    /// One-time discoverability hint for the "long-press to copy JSON" affordance —
    /// shown once ever, then remembered, so the feature isn't silently hidden.
    @AppStorage("sduiCopyJSONHintShown") private var copyHintShown = false
    @State private var showCopyHint = false

    /// Screens follow the app appearance, which is controlled only in Settings —
    /// no per-screen toggle. `systemScheme` already reflects that choice.
    private var isDark: Bool { systemScheme == .dark }

    init(example: PlaygroundExample, tokens: JSONValue, embedded: Bool = false) {
        self.example = example
        self.tokens = tokens
        self.embedded = embedded
        self.declaredImmersive = example.json.contains("\"chrome\"") && example.json.contains("\"immersive\"")
        _jsonText = State(initialValue: example.json)
        // Embedded (Design tab): parse up front — an async .task there gets cancelled
        // by TabView re-renders and sticks on the skeleton. Pushed screens instead
        // parse off-thread in `.task` so the push animation is instant and a skeleton
        // fills the first frames (restores the fast, Instagram-style perceived open).
        _document = State(initialValue: embedded ? (try? SDUIParser.decode(example.json)) : nil)
    }

    /// Immersive screens draw their own edge-to-edge background and control their
    /// chrome — no nav bar, no theme toggle (they carry a fixed palette).
    private var isImmersive: Bool { document?.screen.chrome == "immersive" || (document == nil && declaredImmersive) }

    /// A transient, once-ever tip that surfaces the hidden long-press affordance.
    @ViewBuilder private var copyJSONHint: some View {
        if showCopyHint {
            HStack(spacing: 9) {
                Image(systemName: "hand.tap.fill")
                Text("Long-press any component to copy its JSON")
                    .font(.footnote.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "curlybraces")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Capsule().fill(Color.black.opacity(0.82)))
            .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
            .padding(.horizontal, 24).padding(.bottom, 28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    var body: some View {
        Group {
            if isImmersive {
                immersiveBody
            } else {
                standardBody
            }
        }
        .sheet(isPresented: $showCode) { codeSheet }
        .sheet(item: $host.sheetScreen) { ex in
            BottomSheetScreen(example: ex, tokens: tokens, host: host)
        }
        .overlay(alignment: .top) { toast }
        .overlay(alignment: .top) { teachCard }
        .overlay(alignment: .bottom) { copyJSONHint }
        .onAppear {
            guard !copyHintShown, !isImmersive, !showCopyHint else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { showCopyHint = true }
                try? await Task.sleep(nanoseconds: 4_200_000_000)
                withAnimation(.easeOut(duration: 0.3)) { showCopyHint = false }
                copyHintShown = true
            }
        }
        // Parse off the main actor so the push animation never stutters; a
        // skeleton fills the first frames (Instagram-style perceived speed).
        .task {
            guard document == nil else { return }
            let text = jsonText
            let result = await Task.detached(priority: .userInitiated) { Self.parse(text) }.value
            withAnimation(.easeOut(duration: 0.2)) {
                document = result.document
                parseError = result.error
            }
        }
        .onChange(of: jsonText) { _ in reparse() }
    }

    private var standardBody: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background((isDark ? Color.black : Color.white).ignoresSafeArea())
            .environment(\.colorScheme, isDark ? .dark : .light)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(!embedded)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !embedded {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.backward").sduiFontWeight(.semibold)
                        }
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if hasTeach {
                        Button { toggleTeach() } label: {
                            Image(systemName: showTeach ? "info.circle.fill" : "info.circle")
                        }
                    }
                    Button { showCode = true } label: { Image(systemName: "curlybraces") }
                }
            }
            #if os(iOS)
            // Pushed screens hide the tab bar (standard iOS detail behaviour); the
            // embedded Design tab keeps it. (iOS 16+; on iOS 15 the tab bar stays.)
            .sduiTabBar(embedded ? .visible : .hidden)
            #endif
    }

    private var immersiveBody: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.colorScheme, .dark)
            #if os(iOS)
            // Keep the nav bar for correct system button placement, but make it
            // transparent so the edge-to-edge background shows through behind it.
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .sduiHiddenNavBarBackground()
            .sduiDarkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { immersiveButton("chevron.backward") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if hasTeach {
                        immersiveButton(showTeach ? "info.circle.fill" : "info.circle") { toggleTeach() }
                    }
                    immersiveButton("curlybraces") { showCode = true }
                }
            }
            .sduiTabBar(.hidden)
            #endif
    }

    /// A plain native bar button — a white glyph with a soft shadow for legibility
    /// on any immersive palette. No frosted-glass gimmick, so it behaves exactly
    /// like a system control.
    private func immersiveButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
        }
    }

    @ViewBuilder private var content: some View {
        if let document {
            // Wrap so live accessibility state (VoiceOver / Reduce Motion / Bold /
            // Dynamic Type) is merged into `$env.a11y.*` and updates on the fly.
            SDUIAccessibilityScreen(env: ["locale": .string("en"), "theme": .string(isDark ? "dark" : "light"), "platform": .string("ios")]) { env in
                SDUIScreenView(document: document, tokens: tokens,
                               env: env,
                               loader: PlaygroundData.loader,
                               delegate: host)
            }
        } else if parseError == nil {
            SkeletonScreen()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(.orange)
                Text("Invalid payload").font(.headline)
                Text(parseError ?? "").font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            }
        }
    }

    private var codeSheet: some View {
        SDUINavContainer {
            TextEditor(text: $jsonText)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .sduiHiddenScrollBackground()
                .padding(12)
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
                .navigationTitle("JSON")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Label(document != nil ? "Valid" : "Error",
                              systemImage: document != nil ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(document != nil ? .green : .red)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { copyJSON() } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copied ? .green : .accentColor)
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { showExporter = true } label: { Image(systemName: "square.and.arrow.down") }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { formatJSON() } label: { Label("Format", systemImage: "wand.and.stars") }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .disabled(document == nil)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showCode = false }.sduiFontWeight(.semibold)
                    }
                }
        }
        #if os(iOS)
        .sduiFractionDetents(0.5)
        #endif
        .fileExporter(isPresented: $showExporter,
                      document: JSONFileDocument(text: jsonText),
                      contentType: .json,
                      defaultFilename: "\(example.screenId).json") { _ in }
    }

    /// Copies the contract to the clipboard with a brief confirmation — the fastest
    /// way for someone to lift a screen's JSON straight into their backend.
    private func copyJSON() {
        #if canImport(UIKit)
        UIPasteboard.general.string = jsonText
        #endif
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { copied = false }
        }
    }

    @ViewBuilder private var toast: some View {
        if let event = host.lastEvent {
            ToastBanner(message: event) { withAnimation { host.lastEvent = nil } }
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(event)
        }
    }

    /// The interactive-teaching coach card. It never auto-covers the screen —
    /// the ⓘ nav-bar button toggles it, and it slides in from the top like a
    /// notification, then swipes back up (or ✕) to dismiss.
    @ViewBuilder private var teachCard: some View {
        if let teach = document?.screen.teach, showTeach {
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.tap.fill")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TRY THIS · \(teach.title.uppercased())")
                            .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Text(teach.task)
                            .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button { hideTeach() } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(accent.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
                // Swipe-up affordance: a small chevron hints the dismissal gesture.
                Label("Swipe up to dismiss", systemImage: "chevron.compact.up")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold)).foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 14).padding(.top, 8)
            .offset(y: min(teachDrag, 0))
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { v in teachDrag = min(v.translation.height, 12) }
                    .onEnded { v in
                        if v.translation.height < -32 || v.predictedEndTranslation.height < -80 {
                            hideTeach()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { teachDrag = 0 }
                        }
                    }
            )
            .environment(\.colorScheme, isImmersive ? .dark : (isDark ? .dark : .light))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// True when the current screen actually carries a teaching prompt — the ⓘ
    /// button only appears then.
    private var hasTeach: Bool { document?.screen.teach != nil }

    private func toggleTeach() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.76)) {
            teachDrag = 0
            showTeach.toggle()
        }
    }

    private func hideTeach() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            teachDrag = 0
            showTeach = false
        }
    }

    private var accent: Color { Color(.sRGB, red: 0.357, green: 0.357, blue: 0.941) }

    private func formatJSON() {
        guard
            let data = jsonText.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes]),
            let string = String(data: pretty, encoding: .utf8)
        else { return }
        jsonText = string
    }

    private func reparse() {
        do {
            document = try SDUIParser.decode(jsonText)
            parseError = nil
        } catch {
            document = nil
            parseError = "\(error)"
        }
    }

    /// Off-main-actor parse used by the initial `.task`.
    nonisolated private static func parse(_ text: String) -> (document: SDUIDocument?, error: String?) {
        do { return (try SDUIParser.decode(text), nil) }
        catch { return (nil, "\(error)") }
    }
}

/// Renders a screen inside a real bottom sheet (medium detent, drag to dismiss)
/// — how a `navigate` with a `sheet` transition presents an alert or picker.
private struct BottomSheetScreen: View {
    let example: PlaygroundExample
    let tokens: JSONValue
    /// The parent screen's host — so a `showToast` from inside the sheet surfaces
    /// on the parent (above the sheet), not cramped at the top of this small sheet.
    @ObservedObject var host: PlaygroundHost
    @Environment(\.colorScheme) private var scheme
    @State private var document: SDUIDocument?
    /// Measured content height, so the sheet hugs an alert instead of forcing a
    /// half-screen `.medium` with dead space (works on iOS 16+).
    @State private var contentHeight: CGFloat = 320

    var body: some View {
        let isDark = scheme == .dark
        Group {
            if let document {
                SDUIScreenView(document: document, tokens: tokens,
                               env: ["locale": .string("en"), "theme": .string(isDark ? "dark" : "light"), "platform": .string("ios")],
                               loader: PlaygroundData.loader, delegate: host)
            } else {
                SkeletonScreen()
            }
        }
        .environment(\.colorScheme, isDark ? .dark : .light)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .background(GeometryReader { geo in
            Color.clear.preference(key: SheetHeightKey.self, value: geo.size.height)
        })
        .onPreferenceChange(SheetHeightKey.self) { if $0 > 40 { contentHeight = $0 } }
        #if os(iOS)
        .sduiHeightDetents(contentHeight)
        #endif
        .task {
            document = try? SDUIParser.decode(example.json)
            host.onDismiss = { host.sheetScreen = nil }
        }
    }
}

private struct SheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A plain-text JSON file for the system export sheet, so a screen's contract can
/// be saved straight into Files / iCloud Drive.
struct JSONFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// A toast you can flick away — auto-dismisses after a beat, or swipe up to
/// dismiss it now, the way system banners behave.
private struct ToastBanner: View {
    let message: String
    let onDismiss: () -> Void
    @State private var offset: CGFloat = 0

    var body: some View {
        Text(message)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 18).padding(.vertical, 11)
            .sduiGlass(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            .offset(y: offset)
            .gesture(
                DragGesture()
                    .onChanged { v in offset = min(0, v.translation.height) }
                    .onEnded { v in
                        if v.translation.height < -20 { withAnimation(.easeIn(duration: 0.2)) { onDismiss() } }
                        else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = 0 } }
                    }
            )
            .task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                onDismiss()
            }
    }
}

/// An Instagram-style skeleton shown while a pushed screen parses/renders —
/// soft pulsing placeholder blocks in the shape of typical content.
private struct SkeletonScreen: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            bar(width: 110, height: 12)
            bar(width: 220, height: 30)
            bar(width: 170, height: 14)
            block(height: 150).padding(.top, 6)
            HStack(spacing: 12) {
                block(height: 90)
                block(height: 90)
            }
            block(height: 66)
            block(height: 66)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(pulse ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .frame(width: width, height: height)
    }
    private func block(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

#if DEBUG
@available(iOS 17, macOS 14, *)
#Preview("SDUI Catalog") { SDUIPlaygroundView() }
#endif
#endif

#if canImport(SwiftUI)
import SwiftUI
import SDUICore

/// A collapsible section — a tappable header (title, optional subtitle and icon)
/// that reveals or hides its children with a spring. The "expand / collapse
/// section" idiom (Settings groups, FAQ, a roadmap you can fold away).
///
/// Self-contained: the open/closed state lives here, so no `$state` wiring is
/// needed. Set `"expanded": true` to start open. Its `children` are rendered
/// only while open.
struct DisclosureView: View {
    let component: Component
    let ctx: RenderContext
    @State private var expanded: Bool

    init(component: Component, ctx: RenderContext) {
        self.component = component
        self.ctx = ctx
        _expanded = State(initialValue: component.prop("expanded")?.boolValue ?? false)
    }

    var body: some View {
        let accent = Theme.color(component.prop("accent")?.stringValue, ctx: ctx.binding) ?? .accentColor
        let title = BindingEngine.resolveString(component.prop("title")?.stringValue ?? "", in: ctx.binding)
        let subtitle = BindingEngine.resolveString(component.prop("subtitle")?.stringValue ?? "", in: ctx.binding)
        let icon = component.prop("icon")?.stringValue

        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { expanded.toggle() }
                #if os(iOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
            } label: {
                HStack(spacing: 12) {
                    if let icon, !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                            .frame(width: 32, height: 32)
                            .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().overlay(Color.primary.opacity(0.06))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(component.children.indices, id: \.self) { i in
                        ctx.registry.view(for: component.children[i], in: ctx)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Fade only — the card's height animates and its clip reveals the
                // content top-down like an accordion, with no sliding overlap.
                .transition(.opacity)
            }
        }
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private var surface: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color.gray.opacity(0.10)
        #endif
    }
}
#endif

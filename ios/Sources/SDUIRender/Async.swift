#if canImport(SwiftUI)
import SwiftUI
import SDUICore

/// A native activity indicator (circular, indeterminate). Use it inside an
/// `async` component's `loading` slot, or anywhere a "working…" affordance is
/// needed. `color` tints it; `scale` grows/shrinks it.
struct SpinnerView: View {
    let component: Component
    let ctx: RenderContext
    var body: some View {
        let tint = Theme.color(component.prop("color")?.stringValue, ctx: ctx.binding)
        let scale = component.prop("scale")?.doubleValue.map { CGFloat($0) } ?? 1
        ProgressView()
            .progressViewStyle(.circular)
            .tint(tint)
            .scaleEffect(scale)
    }
}

/// Fetch-then-render container — the declarative "loading component".
///
/// Declares one data `source`; shows the `loading` slot (a spinner by default)
/// while the request is in flight, then renders `content` with the response
/// bound as `$data.<source.id>`. On failure it renders the optional `error`
/// slot. This keeps async UI fully server-driven: the payload decides what a
/// spinner, a loaded document and an error state each look like.
struct AsyncView: View {
    let component: Component
    let ctx: RenderContext

    private enum Phase: Equatable {
        case loading
        case loaded(JSONValue)
        case failed
    }
    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                slot("loading") ?? AnyView(DefaultSpinner())
            case .loaded(let value):
                loadedContent(value)
            case .failed:
                slot("error") ?? AnyView(DefaultError())
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
        .task { await load() }
    }

    /// The declared data source, decoded from the node.
    private var source: DataSource? { component.prop("source")?.decode(DataSource.self) }

    private func load() async {
        guard let source, let loadSource = ctx.loadSource else { phase = .failed; return }
        phase = .loading
        if let value = await loadSource(source) {
            phase = .loaded(value)
        } else {
            phase = .failed
        }
    }

    /// Renders the `content` slot with the response injected as `$data.<id>`.
    private func loadedContent(_ value: JSONValue) -> AnyView {
        guard let content = component.prop("content")?.decode(Component.self), let source else {
            return AnyView(EmptyView())
        }
        var childCtx = ctx
        childCtx.binding.data[source.id] = value
        return ctx.registry.view(for: content, in: childCtx)
    }

    /// Decodes and renders a named child slot, or nil when absent.
    private func slot(_ key: String) -> AnyView? {
        guard let node = component.prop(key)?.decode(Component.self) else { return nil }
        return ctx.registry.view(for: node, in: ctx)
    }
}

private struct DefaultSpinner: View {
    @State private var sweep = false
    var body: some View {
        // A slim indeterminate bar reads as "loading" far better than a spinner.
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.accentColor.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(colors: [.accentColor.opacity(0), .accentColor, .accentColor.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * 0.4)
                    .offset(x: sweep ? w * 0.6 : -w * 0.4)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false), value: sweep)
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onAppear { sweep = true }
    }
}

private struct DefaultError: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text("Couldn't load content").foregroundColor(.secondary)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }
}
#endif

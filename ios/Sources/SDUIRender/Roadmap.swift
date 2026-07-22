#if canImport(SwiftUI)
import SwiftUI
import SDUICore

/// A vertical numbered roadmap / timeline whose steps expand like sections — the
/// "how it works" idiom. Each step is a numbered node on a connecting rail; steps
/// with a `detail` disclose it on tap with a spring. `done: true` marks a node
/// complete (a check on a filled node). Self-contained interaction — no `$state`.
struct RoadmapView: View {
    let component: Component
    let ctx: RenderContext

    private struct Step { let title: String; let detail: String; let done: Bool }

    var body: some View {
        let accent = Theme.color(component.prop("accent")?.stringValue, ctx: ctx.binding) ?? .accentColor
        let rail = Color.primary.opacity(0.10)
        let steps = parseSteps()
        VStack(spacing: 0) {
            ForEach(steps.indices, id: \.self) { i in
                row(index: i, step: steps[i], isLast: i == steps.count - 1, accent: accent, rail: rail)
            }
        }
    }

    @ViewBuilder
    private func row(index: Int, step: Step, isLast: Bool, accent: Color, rail: Color) -> some View {
        let hasDetail = !step.detail.isEmpty
        HStack(alignment: .top, spacing: 14) {
            // Node + connecting rail. The rail fills the row height so it always
            // reaches the next node, whatever the text length.
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(step.done ? accent : accent.opacity(0.14))
                        .frame(width: 30, height: 30)
                        .shadow(color: step.done ? accent.opacity(0.4) : .clear, radius: 5, y: 2)
                    if step.done {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    } else {
                        Text("\(index + 1)").font(.footnote.weight(.bold)).foregroundStyle(accent)
                    }
                }
                if !isLast {
                    Rectangle().fill(rail).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.body.weight(.semibold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if hasDetail {
                    Text(step.detail)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 5)
            .padding(.bottom, isLast ? 0 : 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func parseSteps() -> [Step] {
        (component.prop("steps")?.arrayValue ?? []).map { item in
            Step(title: BindingEngine.resolveString(item["title"]?.stringValue ?? "", in: ctx.binding),
                 detail: BindingEngine.resolveString(item["detail"]?.stringValue ?? "", in: ctx.binding),
                 done: item["done"]?.boolValue ?? false)
        }
    }
}
#endif

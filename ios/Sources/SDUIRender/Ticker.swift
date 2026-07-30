#if canImport(SwiftUI)
import SwiftUI
import SDUICore

/// An invisible clock that advances a numeric `$state` value on a fixed interval
/// — the engine's heartbeat. Powers a playing progress bar, a stopwatch, a live
/// counter, an auto-advancing carousel.
///
/// It ticks only while `while` (a bool state key) is true, adds `step` every
/// `interval` seconds, caps at `max`, and `loop`s back to 0 at the end. Because
/// it writes through the same two-way binding a `slider` reads, dragging the
/// slider and the tick stay in sync automatically.
struct TickerView: View {
    let component: Component
    let ctx: RenderContext

    var body: some View {
        let interval = max(0.05, component.prop("interval")?.doubleValue ?? 1)
        let step = component.prop("step")?.doubleValue ?? 0.01
        let bindKey = component.bindKey
        let maxV = component.prop("max")?.doubleValue ?? 1
        let loop = component.prop("loop")?.boolValue ?? false
        let running = component.prop("while")?.stringValue.map { ctx.boolBinding($0).wrappedValue } ?? true
        let progress = ctx.doubleBinding(bindKey)

        Color.clear
            .frame(width: 0, height: 0)
            // Restart the loop whenever `running` flips — pausing cancels it, so no
            // stray timers pile up. Sleeping off the main thread; the tiny state
            // write lands back on the main actor via the binding.
            .task(id: running) {
                guard running, !bindKey.isEmpty else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    if Task.isCancelled { break }
                    var next = progress.wrappedValue + step
                    if next >= maxV { next = loop ? 0 : maxV }
                    progress.wrappedValue = next
                }
            }
    }
}
#endif

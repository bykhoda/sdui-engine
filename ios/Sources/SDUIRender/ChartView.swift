#if canImport(SwiftUI) && canImport(Charts)
import SwiftUI
import Charts
import SDUICore

/// A native chart driven from JSON — line, area or bar. Proves the engine can
/// render Apple-quality data visuals (Stocks / Health style) from a payload,
/// via Swift Charts. Data comes from a `values` array (numbers, x = index) or a
/// `points` array of `{x, y}` objects; either may be a binding.
///
/// Interactive by default: drag a finger across the plot and a crosshair, a
/// highlighted point and a floating value pill track your position — the same
/// scrubbing you get in Apple Stocks and Health. Set `"interactive": false` to
/// disable, `"unit"` to prefix the read-out (e.g. `"$"`).
@available(iOS 16, macOS 13, *)
struct SDUIChartView: View {
    let component: Component
    let ctx: RenderContext

    @State private var selectedID: Int?

    private struct Point: Identifiable { let id: Int; let x: Double; let y: Double }

    var body: some View {
        let tint = Theme.color(component.prop("color")?.stringValue, ctx: ctx.binding) ?? .accentColor
        let style = component.prop("style")?.stringValue ?? "line"
        let showAxes = component.prop("axes")?.boolValue ?? false
        let interactive = component.prop("interactive")?.boolValue ?? true
        let unit = component.prop("unit")?.stringValue ?? ""
        let points = resolvedPoints()
        let selected = selectedID.flatMap { id in points.first { $0.id == id } }
        let domain = yDomain(points, style: style)
        // Pin the x-domain to the data range. Otherwise the big selection glow at
        // the first/last point makes Swift Charts widen the domain to fit the
        // symbol, shoving the whole line sideways as you scrub to the edge.
        let xs = points.map(\.x)
        // Bars sit ON their x value, so the first/last bars would be half-clipped
        // at the plot edges by `.clipped()`; pad the domain to give them room.
        let xPad: Double = style == "bar" ? 0.6 : 0
        let xDomain = ((xs.min() ?? 0) - xPad)...((xs.max() ?? 1) + xPad)

        Chart {
            ForEach(points) { point in
                mark(for: point, style: style, tint: tint)
            }
            if let selected {
                RuleMark(x: .value("x", selected.x))
                    .foregroundStyle(tint.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                // Outer glow + solid ring + white centre = a crisp "target" dot.
                // The read-out pill hangs off the point so it never clips at the top.
                PointMark(x: .value("x", selected.x), y: .value("y", selected.y))
                    .foregroundStyle(tint.opacity(0.18)).symbolSize(320)
                // The read-out pill is kept inside the plot with overflowResolution
                // so scrubbing to the first/last point never widens the chart and
                // shoves the layout sideways (iOS 17+); older systems fall back.
                if #available(iOS 17, macOS 14, *) {
                    PointMark(x: .value("x", selected.x), y: .value("y", selected.y))
                        .foregroundStyle(tint).symbolSize(120)
                        .annotation(position: annotationPosition(for: selected, in: domain), spacing: 8,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            callout(selected, unit: unit, tint: tint)
                        }
                } else {
                    PointMark(x: .value("x", selected.x), y: .value("y", selected.y))
                        .foregroundStyle(tint).symbolSize(120)
                        .annotation(position: annotationPosition(for: selected, in: domain), spacing: 8) {
                            callout(selected, unit: unit, tint: tint)
                        }
                }
                PointMark(x: .value("x", selected.x), y: .value("y", selected.y))
                    .foregroundStyle(.white).symbolSize(40)
            }
        }
        .chartXAxis(showAxes ? .automatic : .hidden)
        .chartYAxis(showAxes ? .automatic : .hidden)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: domain)
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in
            if interactive {
                GeometryReader { geo in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        // Scrubbing is armed by a brief press-and-hold, exactly like
                        // Apple Health: a quick vertical swipe fails the long-press and
                        // scrolls the page, while a deliberate touch inspects values.
                        .gesture(
                            LongPressGesture(minimumDuration: 0.12, maximumDistance: 12)
                                .sequenced(before: DragGesture(minimumDistance: 0))
                                .onChanged { value in
                                    if case .second(true, let drag?) = value {
                                        select(at: drag.location, proxy: proxy, geo: geo, points: points)
                                    }
                                }
                                .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { selectedID = nil } }
                        )
                }
            }
        }
    }

    @ChartContentBuilder
    private func mark(for point: Point, style: String, tint: Color) -> some ChartContent {
        switch style {
        case "bar":
            BarMark(x: .value("x", point.x), y: .value("y", point.y), width: .fixed(20))
                .foregroundStyle(tint.gradient)
                .cornerRadius(6)
        case "area":
            AreaMark(x: .value("x", point.x), y: .value("y", point.y))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("x", point.x), y: .value("y", point.y))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        default:
            LineMark(x: .value("x", point.x), y: .value("y", point.y))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    /// A floating read-out pill on frosted material — the value at the finger.
    private func callout(_ p: Point, unit: String, tint: Color) -> some View {
        Text("\(unit)\(format(p.y))")
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    /// Maps a drag location to the nearest data point and selects it, with a
    /// light selection tick whenever the highlighted point changes.
    private func select(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy, points: [Point]) {
        guard !points.isEmpty else { return }
        let originX = geo[proxy.plotAreaFrame].origin.x
        guard let xValue: Double = proxy.value(atX: location.x - originX) else { return }
        let nearest = points.min { abs($0.x - xValue) < abs($1.x - xValue) }
        guard let nearest, nearest.id != selectedID else { return }
        selectedID = nearest.id
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Y-domain with breathing room so the line isn't glued to the edges (and the
    /// read-out pill has space). Bars keep a zero baseline.
    private func yDomain(_ points: [Point], style: String) -> ClosedRange<Double> {
        let ys = points.map(\.y)
        guard let lo = ys.min(), let hi = ys.max() else { return 0...1 }
        if style == "bar" { return 0...(hi * 1.28 + 0.0001) }
        let pad = (hi - lo) * 0.16 + 0.0001
        return (lo - pad)...(hi + pad)
    }

    /// Flip the pill below the point when the value sits high in the domain, so it
    /// never clips off the top of the plot.
    private func annotationPosition(for p: Point, in domain: ClosedRange<Double>) -> AnnotationPosition {
        let span = domain.upperBound - domain.lowerBound
        let ratio = span > 0 ? (p.y - domain.lowerBound) / span : 0.5
        return ratio > 0.72 ? .bottom : .top
    }

    private func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 100_000 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private func resolvedPoints() -> [Point] {
        if let raw = component.prop("points") {
            let array = arrayValue(raw)
            if !array.isEmpty {
                return array.enumerated().map { index, item in
                    Point(id: index, x: item["x"]?.doubleValue ?? Double(index), y: item["y"]?.doubleValue ?? 0)
                }
            }
        }
        if let raw = component.prop("values") {
            let array = arrayValue(raw)
            return array.enumerated().map { index, item in
                Point(id: index, x: Double(index), y: item.doubleValue ?? 0)
            }
        }
        return []
    }

    /// Resolves an array prop that may be inline or a `$…` binding to an array.
    private func arrayValue(_ raw: JSONValue) -> [JSONValue] {
        if case .string(let s) = raw {
            return BindingEngine.resolve(s, in: ctx.binding).arrayValue ?? []
        }
        return raw.arrayValue ?? []
    }
}
#endif

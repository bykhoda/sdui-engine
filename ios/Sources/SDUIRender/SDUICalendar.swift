#if canImport(SwiftUI)
import SwiftUI
import SDUICore

/// A custom month-grid calendar driven entirely from JSON. Unlike the native
/// `datepicker` (single date only), this supports three selection modes — the
/// same node renders a single-day picker, a contiguous date **range**, or a
/// **multi**-day selection — chosen by the bindable `mode` prop, so a row of
/// chips can flip the calendar live.
///
/// State contract (all ISO `yyyy-MM-dd` strings in `$state`):
///  - single: `bind`          → the chosen day
///  - range : `startBind`,`endBind` → range ends (either may be empty)
///  - multi : `bind`          → comma-separated days
///
/// Cross-platform note: the grid is plain layout + state maths, so Compose and
/// Aurora map it one-to-one; there is no platform-specific calendar widget to
/// diverge (which is exactly where native date pickers disagree).
struct CalendarGridView: View {
    let component: Component
    let ctx: RenderContext

    @State private var visibleMonth: Date = Date()

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = weekStartMonday ? 2 : 1
        return c
    }
    private var weekStartMonday: Bool {
        BindingEngine.resolveString(component.prop("weekStart")?.stringValue ?? "sunday", in: ctx.binding) == "monday"
    }
    private var tint: Color {
        Theme.color(component.prop("color")?.stringValue, ctx: ctx.binding)
            ?? Color(.sRGB, red: 0.357, green: 0.357, blue: 0.941, opacity: 1)
    }
    private var mode: String {
        BindingEngine.resolveString(component.prop("mode")?.stringValue ?? "single", in: ctx.binding)
    }

    var body: some View {
        let today = cal.startOfDay(for: Date())
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: visibleMonth)) ?? visibleMonth
        let range = cal.range(of: .day, in: .month, for: monthStart) ?? (1..<31)
        let firstWeekdayIndex = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let days: [Date?] = Array(repeating: nil, count: firstWeekdayIndex)
            + range.map { cal.date(byAdding: .day, value: $0 - 1, to: monthStart)! }

        VStack(spacing: 18) {
            summaryHeader()
            header(monthStart: monthStart)
            weekdayRow()
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days.indices, id: \.self) { i in
                    if let day = days[i] {
                        dayCell(day, today: today)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .onAppear { syncVisibleMonthToSelection() }
    }

    // MARK: header / weekday / footer

    @ViewBuilder private func header(monthStart: Date) -> some View {
        let title = monthStart.formatted(.dateTime.month(.wide).year())
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            Button { step(-1) } label: { chevron("chevron.left") }
            Button { step(1) } label: { chevron("chevron.right") }
        }
    }
    private func chevron(_ name: String) -> some View {
        Image(systemName: name).font(.body.weight(.semibold)).foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.10), in: Circle())
            .contentShape(Rectangle())
    }

    private func weekdayRow() -> some View {
        let symbols = orderedWeekdaySymbols()
        return HStack(spacing: 4) {
            ForEach(symbols.indices, id: \.self) { i in
                Text(symbols[i]).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    private func orderedWeekdaySymbols() -> [String] {
        let base = ["S", "M", "T", "W", "T", "F", "S"]
        return weekStartMonday ? Array(base[1...] + base[0...0]) : base
    }

    private func summaryHeader() -> some View {
        let caption: String
        let label: String
        var trailing = ""
        switch mode {
        case "range":
            caption = "SELECTED RANGE"
            let s = read(startKey), e = read(endKey)
            if s.isEmpty { label = "Select dates" }
            else if e.isEmpty { label = "\(pretty(s)) — select end" }
            else { label = "\(pretty(s)) – \(pretty(e))"; trailing = nights(s, e) }
        case "multi":
            caption = "SELECTED DAYS"
            let n = multiDates().count
            label = n == 0 ? "Pick any days" : "\(n) selected"
        default:
            caption = "SELECTED DATE"
            let v = read(singleKey)
            label = v.isEmpty ? "Select a date" : prettyFull(v)
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text(caption).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.title3.weight(.bold)).foregroundStyle(tint)
                Spacer()
                if !trailing.isEmpty {
                    Text(trailing).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: day cell

    private func dayCell(_ day: Date, today: Date) -> some View {
        let sel = selectionKind(for: day)
        let isToday = cal.isDate(day, inSameDayAs: today)
        let onFill = sel == .single || sel == .rangeStart || sel == .rangeEnd
        return ZStack {
            rangeBand(sel)
            if onFill {
                Circle().fill(tint).padding(3)
            } else if sel == .none && isToday {
                Circle().stroke(tint.opacity(0.45), lineWidth: 1.5).padding(3)
            }
            Text("\(cal.component(.day, from: day))")
                .font(.callout.weight(sel == .none ? .regular : .semibold))
                .foregroundStyle(onFill ? Color.white : (isToday && sel == .none ? tint : Color.primary))
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { select(day) }
    }

    /// The continuous range band (Material-style): endpoints fill only their inner
    /// half and middles fill full width, so with zero column spacing the halves
    /// join into one pill across the week row.
    @ViewBuilder private func rangeBand(_ sel: Kind) -> some View {
        let band = tint.opacity(0.15)
        let l: Color = (sel == .rangeEnd || sel == .rangeMiddle) ? band : .clear
        let r: Color = (sel == .rangeStart || sel == .rangeMiddle) ? band : .clear
        HStack(spacing: 0) {
            Rectangle().fill(l).frame(maxWidth: .infinity)
            Rectangle().fill(r).frame(maxWidth: .infinity)
        }
        .frame(height: 40)
    }

    private enum Kind: Equatable { case none, single, rangeStart, rangeEnd, rangeMiddle }

    private func selectionKind(for day: Date) -> Kind {
        switch mode {
        case "range":
            let s = date(read(startKey)), e = date(read(endKey))
            if let s, let e {
                if cal.isDate(s, inSameDayAs: e) { return cal.isDate(day, inSameDayAs: s) ? .single : .none }
                if cal.isDate(day, inSameDayAs: s) { return .rangeStart }
                if cal.isDate(day, inSameDayAs: e) { return .rangeEnd }
                if day > s, day < e { return .rangeMiddle }
                return .none
            }
            if let s, cal.isDate(day, inSameDayAs: s) { return .single }
            return .none
        case "multi":
            return multiDates().contains(where: { cal.isDate($0, inSameDayAs: day) }) ? .single : .none
        default:
            if let d = date(read(singleKey)), cal.isDate(day, inSameDayAs: d) { return .single }
            return .none
        }
    }

    // MARK: selection logic

    private func select(_ day: Date) {
        let iso = Self.iso.string(from: day)
        switch mode {
        case "range":
            let s = read(startKey), e = read(endKey)
            if s.isEmpty || !e.isEmpty {
                write(startKey, iso); write(endKey, "")           // start a new range
            } else if let start = date(s) {
                if day < start { write(startKey, iso) }           // moved before start → new start
                else { write(endKey, iso) }                        // complete the range
            }
        case "multi":
            var days = multiDates()
            if let idx = days.firstIndex(where: { cal.isDate($0, inSameDayAs: day) }) {
                days.remove(at: idx)
            } else {
                days.append(day)
            }
            write(multiKey, days.sorted().map { Self.iso.string(from: $0) }.joined(separator: ","))
        default:
            write(singleKey, iso)
        }
        #if os(iOS)
        Haptics.play("light")
        #endif
    }

    private func step(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            visibleMonth = cal.date(byAdding: .month, value: delta, to: visibleMonth) ?? visibleMonth
        }
    }
    private func syncVisibleMonthToSelection() {
        let anchor = date(read(startKey)) ?? date(read(singleKey)) ?? multiDates().first
        if let anchor { visibleMonth = anchor }
    }

    // MARK: state keys & helpers

    private var singleKey: String { component.prop("bind")?.stringValue ?? "" }
    private var startKey: String { component.prop("startBind")?.stringValue ?? "" }
    private var endKey: String { component.prop("endBind")?.stringValue ?? "" }
    private var multiKey: String { component.prop("multiBind")?.stringValue ?? singleKey }

    private func read(_ key: String) -> String {
        guard !key.isEmpty else { return "" }
        return ctx.stringBinding(key).wrappedValue
    }
    private func write(_ key: String, _ value: String) {
        guard !key.isEmpty else { return }
        ctx.stringBinding(key).wrappedValue = value
    }
    private func multiDates() -> [Date] {
        read(multiKey).split(separator: ",").compactMap { date(String($0)) }
    }
    private func date(_ s: String) -> Date? { s.isEmpty ? nil : Self.iso.date(from: s) }
    private func pretty(_ s: String) -> String {
        guard let d = date(s) else { return s }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
    private func prettyFull(_ s: String) -> String {
        guard let d = date(s) else { return s }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    private func nights(_ s: String, _ e: String) -> String {
        guard let a = date(s), let b = date(e) else { return "" }
        let n = cal.dateComponents([.day], from: a, to: b).day ?? 0
        return "\(n) night\(n == 1 ? "" : "s")"
    }
}
#endif

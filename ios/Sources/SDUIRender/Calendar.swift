#if canImport(SwiftUI)
import SwiftUI
import SDUICore

/// A native date picker driven from JSON — a graphical month calendar or a
/// compact field. Two-way bound to a `$state` key holding an ISO `yyyy-MM-dd`
/// string, so the selected date is server-driven like any other value.
///
/// Cross-platform note: each platform renders its own native picker (SwiftUI
/// here, a Material date picker on Compose) from the same contract — no custom
/// per-platform code, which is exactly where hand-rolled calendars go wrong.
struct DatePickerView: View {
    let component: Component
    let ctx: RenderContext

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        let key = component.prop("bind")?.stringValue ?? ""
        let tint = Theme.color(component.prop("color")?.stringValue, ctx: ctx.binding) ?? .accentColor
        let graphical = (component.prop("style")?.stringValue ?? "graphical") == "graphical"
        let raw = ctx.stringBinding(key)
        let dateBinding = Binding<Date>(
            get: { Self.formatter.date(from: raw.wrappedValue) ?? Date() },
            set: { raw.wrappedValue = Self.formatter.string(from: $0) }
        )

        Group {
            if graphical {
                DatePicker("", selection: dateBinding, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
            } else {
                DatePicker("", selection: dateBinding, displayedComponents: [.date])
                    .datePickerStyle(.compact)
            }
        }
        .labelsHidden()
        .tint(tint)
    }
}
#endif

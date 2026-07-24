#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import SDUICore
import SDUIRender

/// The in-app Figma pipeline: paste your Figma variables, convert them to
/// `tokens.json` on-device, watch a real screen re-theme from the result, then
/// copy or save the JSON. This is the whole pitch in one screen — a designer's
/// tokens become a themed product with no engineer in the loop.
struct FigmaConverterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var input = FigmaConverterView.sample
    @State private var output = ""
    @State private var count = 0
    @State private var tokens: JSONValue = .object([:])
    @State private var previewDoc: SDUIDocument?
    @State private var showExporter = false
    @State private var copied = false
    @StateObject private var host = PlaygroundHost()

    var body: some View {
        SDUINavContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    step("1", "Paste your Figma variables", "Variables export (W3C Design Tokens) or Tokens Studio JSON — colours, spacing, radii, type.")
                    editor(text: $input, height: 170, editable: true)
                    Button { convert() } label: {
                        Label("Convert to tokens.json", systemImage: "wand.and.stars")
                            .sduiFontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)

                    if previewDoc != nil {
                        step("2", "Live preview", "Rendered natively from the converted tokens — edit the input and convert to re-theme.")
                        preview
                    }

                    if !output.isEmpty {
                        HStack(alignment: .firstTextBaseline) {
                            step("3", "tokens.json", "\(count) tokens — drop this on your backend.")
                            Spacer()
                        }
                        editor(text: .constant(output), height: 190, editable: false)
                        HStack(spacing: 12) {
                            Button { copy() } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }.tint(copied ? .green : .accentColor)
                            Button { showExporter = true } label: { Label("Save to Files", systemImage: "square.and.arrow.down") }
                            Spacer()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Figma → tokens")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fileExporter(isPresented: $showExporter, document: JSONFileDocument(text: output),
                          contentType: .json, defaultFilename: "tokens.json") { _ in }
        }
        .task { convert() }
    }

    // MARK: Pieces

    private var preview: some View {
        Group {
            if let previewDoc {
                SDUIScreenView(document: previewDoc, tokens: tokens,
                               env: ["locale": .string("en"), "theme": .string(scheme == .dark ? "dark" : "light")],
                               loader: PlaygroundData.loader, delegate: host)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.sduiSecondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private func step(_ n: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.footnote.weight(.bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func editor(text: Binding<String>, height: CGFloat, editable: Bool) -> some View {
        TextEditor(text: text)
            .font(.system(.footnote, design: .monospaced))  // Font.monospaced: iOS 15+
            .autocorrectionDisabled()
            .sduiHiddenScrollBackground()
            .padding(10)
            .frame(height: height)
            .background(Color.sduiSecondaryGroupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }

    // MARK: Actions

    private func convert() {
        guard let result = FigmaTokens.convert(input) else { return }
        output = result.tokens
        count = result.count
        tokens = mergedTokens(from: result.tokens)
        previewDoc = try? SDUIParser.decode(Self.previewPayload)
    }

    /// Layer the converted colours/type over the app's base tokens so composite
    /// tokens (button styles, etc.) still resolve in the preview.
    private func mergedTokens(from convertedJSON: String) -> JSONValue {
        guard
            let baseData = try? JSONEncoder().encode(ScreenLibrary.tokens()),
            let baseObj = try? JSONSerialization.jsonObject(with: baseData),
            let convObj = try? JSONSerialization.jsonObject(with: Data(convertedJSON.utf8))
        else { return ScreenLibrary.tokens() }
        let merged = FigmaTokens.merge(base: baseObj, over: convObj)
        guard
            let mergedData = try? JSONSerialization.data(withJSONObject: merged),
            let value = try? JSONDecoder().decode(JSONValue.self, from: mergedData)
        else { return ScreenLibrary.tokens() }
        return value
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = output
        #endif
        withAnimation { copied = true }
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); withAnimation { copied = false } }
    }

    // MARK: Fixtures

    private static let sample = """
    {
      "color": {
        "primary":         { "$value": "#7C5CFF", "$type": "color" },
        "primarySoft":     { "$value": "#EEEAFF", "$type": "color" },
        "onPrimary":       { "$value": "#FFFFFF", "$type": "color" },
        "success":         { "$value": "#12B76A", "$type": "color" },
        "warning":         { "$value": "#F79009", "$type": "color" },
        "error":           { "$value": "#F04438", "$type": "color" },
        "surface":         { "$value": "#F2F4F7", "$type": "color" },
        "surfaceElevated": { "$value": "#FFFFFF", "$type": "color" },
        "textPrimary":     { "$value": "#101828", "$type": "color" },
        "textSecondary":   { "$value": "#667085", "$type": "color" }
      },
      "typography": {
        "largeTitle":  { "$value": { "fontSize": "32", "fontWeight": "700" }, "$type": "typography" },
        "subheadline": { "$value": { "fontSize": "15", "fontWeight": "400" }, "$type": "typography" },
        "caption":     { "$value": { "fontSize": "12", "fontWeight": "500" }, "$type": "typography" }
      }
    }
    """

    private static let previewPayload = """
    {
      "version": "0.1",
      "screen": { "id": "tokpreview", "content": {
        "type": "vstack", "alignment": "leading", "spacing": "$token.spacing.md",
        "modifiers": { "padding": "$token.spacing.lg", "size": { "width": { "mode": "fill" } } },
        "children": [
          { "type": "text", "value": "Your brand", "style": "$token.typography.largeTitle", "color": "$token.color.textPrimary" },
          { "type": "text", "value": "Colour and type, straight from your Figma variables.", "style": "$token.typography.subheadline", "color": "$token.color.textSecondary" },
          { "type": "hstack", "spacing": "$token.spacing.sm", "modifiers": { "size": { "width": { "mode": "fill" } }, "padding": { "top": "$token.spacing.xs" } }, "children": [
            { "type": "vstack", "children": [], "modifiers": { "size": { "width": { "mode": "weight", "value": 1 }, "height": { "mode": "fixed", "value": 44 } }, "background": "$token.color.primary", "cornerRadius": "$token.radius.md" } },
            { "type": "vstack", "children": [], "modifiers": { "size": { "width": { "mode": "weight", "value": 1 }, "height": { "mode": "fixed", "value": 44 } }, "background": "$token.color.success", "cornerRadius": "$token.radius.md" } },
            { "type": "vstack", "children": [], "modifiers": { "size": { "width": { "mode": "weight", "value": 1 }, "height": { "mode": "fixed", "value": 44 } }, "background": "$token.color.warning", "cornerRadius": "$token.radius.md" } },
            { "type": "vstack", "children": [], "modifiers": { "size": { "width": { "mode": "weight", "value": 1 }, "height": { "mode": "fixed", "value": 44 } }, "background": "$token.color.error", "cornerRadius": "$token.radius.md" } }
          ] },
          { "type": "button", "title": "Primary action", "style": "$token.button.large", "modifiers": { "size": { "width": { "mode": "fill" } }, "padding": { "top": "$token.spacing.xs" } }, "onTap": { "action": "showToast", "message": "Re-themed live" } }
        ]
      } }
    }
    """
}
#endif

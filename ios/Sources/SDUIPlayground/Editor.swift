#if canImport(SwiftUI)
import SwiftUI
import SDUICore
import SDUIRender
#if os(iOS)
import UIKit
#endif

/// A live editor: paste or type SDUI JSON and watch it render natively above the
/// editor. This is where anyone — including an AI generating screens — verifies
/// a payload on device before shipping it.
public struct LiveEditorView: View {
    private let tokens: JSONValue

    @Environment(\.colorScheme) private var systemScheme
    @State private var themeOverride: Bool?
    @State private var jsonText: String
    @State private var document: SDUIDocument?
    @State private var parseError: String?
    @StateObject private var host = PlaygroundHost()

    private var isDark: Bool { themeOverride ?? (systemScheme == .dark) }

    public init(tokens: JSONValue = ScreenLibrary.tokens(), starter: String? = nil) {
        self.tokens = tokens
        _jsonText = State(initialValue: starter ?? Self.starter)
    }

    public var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            editor
        }
        .navigationTitle("Try your own")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { withAnimation { themeOverride = !isDark } } label: {
                    Image(systemName: isDark ? "moon.stars.fill" : "sun.max")
                }
            }
        }
        .overlay(alignment: .top) { toast }
        .onAppear(perform: reparse)
        .onChange(of: jsonText) { _ in reparse() }
    }

    @ViewBuilder private var preview: some View {
        Group {
            if let document {
                SDUIScreenView(document: document, tokens: tokens,
                               env: ["locale": .string("en"), "theme": .string(isDark ? "dark" : "light")],
                               loader: PlaygroundData.loader,
                               delegate: host)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30)).foregroundStyle(.orange)
                    Text("Invalid payload").font(.headline)
                    Text(parseError ?? "").font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((isDark ? Color.black : Color.white))
        .environment(\.colorScheme, isDark ? .dark : .light)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(document != nil ? "Valid" : "Error",
                      systemImage: document != nil ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(document != nil ? .green : .red)
                Spacer()
                Button { paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    .font(.footnote.weight(.medium))
                Button("Format") { format() }.font(.footnote.weight(.medium)).disabled(document == nil)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            TextEditor(text: $jsonText)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .sduiHiddenScrollBackground()
                .padding(10)
                .background(Color.primary.opacity(0.04))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
        .frame(height: 300)
        .background(.regularMaterial)
    }

    @ViewBuilder private var toast: some View {
        if let event = host.lastEvent {
            Text(event)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    withAnimation { host.lastEvent = nil }
                }
        }
    }

    // MARK: Actions

    private func paste() {
        #if os(iOS)
        if let string = UIPasteboard.general.string, !string.isEmpty { jsonText = string }
        #endif
    }

    private func format() {
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

    private static let starter = """
    {
      "version": "0.1",
      "screen": {
        "id": "my_screen",
        "title": "My Screen",
        "content": {
          "type": "vstack",
          "spacing": "$token.spacing.md",
          "alignment": "leading",
          "modifiers": { "padding": "$token.spacing.lg" },
          "children": [
            { "type": "text", "value": "Hello 👋", "style": "$token.typography.largeTitle", "color": "$token.color.textPrimary" },
            { "type": "text", "value": "Paste your JSON or edit this. It renders live.", "style": "$token.typography.body", "color": "$token.color.textSecondary" },
            { "type": "button", "title": "Tap me", "style": "$token.button.primary",
              "modifiers": { "size": { "width": { "mode": "fill" } } },
              "onTap": { "action": "showToast", "message": "It works! 🎉", "style": "success" } }
          ]
        }
      }
    }
    """
}
#endif

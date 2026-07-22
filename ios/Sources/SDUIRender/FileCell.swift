#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import SDUICore

/// A rich document/upload cell with the full state set an uploader needs:
/// empty → picking → loading → success / too-large / failed. Tap an empty cell
/// to pick from the Files app; a picked file shows its format and size with a
/// "View" action that opens the native previewer (QuickLook), and a trash button
/// to remove it. Every state is HIG-plain: an SF Symbol status glyph, a filename
/// + size, a trailing trash control, and one coloured status/action line.
///
/// The contract can also pin a **fixed** `state` (`success` / `loading` /
/// `warning` / `error` / `empty`) with a `title` + `size`, so a screen can lay
/// out the whole state catalogue without touching the Files picker.
struct FileCellView: View {
    let component: Component
    let ctx: RenderContext

    enum Phase { case empty, loading, success, warning, error }
    private struct Picked { let name: String; let ext: String; let bytes: Int; let localURL: URL? }

    @State private var picked: Picked?
    @State private var phase: Phase = .empty
    @State private var message: String?
    @State private var showImporter = false

    // MARK: Contract inputs

    /// A fixed showcase state, if the contract pins one (otherwise interactive).
    private var fixedPhase: Phase? {
        switch component.prop("state")?.stringValue {
        case "loading":            return .loading
        case "success":            return .success
        case "warning", "tooLarge": return .warning
        case "error", "failed":    return .error
        case "empty":              return .empty
        default:                   return nil
        }
    }
    private var isShowcase: Bool { fixedPhase != nil }
    private var currentPhase: Phase { fixedPhase ?? phase }

    private var tint: Color { Theme.color(component.prop("color")?.stringValue, ctx: ctx.binding) ?? .accentColor }
    private var maxKB: Double? { component.prop("maxSizeKB")?.doubleValue }

    private var fileName: String { picked?.name ?? component.prop("title")?.stringValue ?? "File.pdf" }
    private var fileSize: String {
        if let picked { return Self.size(picked.bytes) }
        return component.prop("size")?.stringValue ?? ""
    }
    private var fileExt: String {
        picked?.ext ?? (component.prop("title")?.stringValue as NSString?)?.pathExtension.uppercased() ?? ""
    }
    private var viewLabel: String { component.prop("viewLabel")?.stringValue ?? "View" }
    private var warningText: String {
        message ?? component.prop("limitText")?.stringValue
            ?? maxKB.map { "Attach a file no larger than \(Int($0 / 1024)) MB" }
            ?? "File is too large"
    }
    private var errorText: String {
        message ?? component.prop("errorText")?.stringValue ?? "Upload failed"
    }

    // MARK: Body

    var body: some View {
        Group {
            switch currentPhase {
            case .empty:   emptyCell
            case .loading: loadingCell
            case .success: successCell
            case .warning: statusCell(icon: "exclamationmark.triangle", tone: .orange, status: warningText)
            case .error:   statusCell(icon: "xmark.circle", tone: .red, status: errorText)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            handle(result)
        }
    }

    // MARK: States

    private var emptyCell: some View {
        Button { showImporter = true } label: {
            HStack(spacing: 14) {
                leadingGlyph { Image(systemName: "arrow.up.doc").font(.system(size: 20, weight: .semibold)).foregroundStyle(tint) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.prop("title")?.stringValue ?? "Choose a file")
                        .font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(maxKB.map { "Max \(Int($0 / 1024)) MB" } ?? "From Files or iCloud Drive")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(Color.primary.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private var loadingCell: some View {
        HStack(spacing: 14) {
            ProgressView().progressViewStyle(.circular)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 9) {
                SkeletonView(cornerRadius: 6).frame(width: 190, height: 12)
                SkeletonView(cornerRadius: 6).frame(width: 120, height: 12)
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var successCell: some View {
        cardRow(
            leading: { Image(systemName: Self.icon(for: fileExt)).font(.system(size: 22, weight: .regular)).foregroundStyle(.secondary) },
            status: {
                Button {
                    if let url = picked?.localURL { SDUIQuickLook.shared.present(urls: [url.path], index: 0) }
                    else if let src = component.prop("previewURL")?.stringValue { SDUIQuickLook.shared.present(urls: [src], index: 0) }
                    else { Haptics.play("light") }
                } label: {
                    Text(viewLabel).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                }
                .buttonStyle(.plain)
            }
        )
    }

    private func statusCell(icon: String, tone: Color, status: String) -> some View {
        cardRow(
            leading: { Image(systemName: icon).font(.system(size: 22, weight: .regular)).foregroundStyle(tone) },
            status: { Text(status).font(.subheadline).foregroundStyle(tone) }
        )
    }

    // MARK: Row scaffold

    /// The shared success/warning/error row: leading glyph, filename + size, a
    /// trailing trash control, and a coloured status/action line beneath.
    private func cardRow<Leading: View, Status: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder status: () -> Status
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 14) {
                leadingGlyph(content: leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    if !fileSize.isEmpty {
                        Text(fileSize).font(.subheadline).foregroundStyle(.secondary)
                    }
                    status().padding(.top, 2)
                }
                Spacer(minLength: 8)
                Button { remove() } label: {
                    Image(systemName: "trash").font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func leadingGlyph<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(width: 28, height: 28, alignment: .center).padding(.top, 1)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05))
    }

    // MARK: Actions

    private func remove() {
        Haptics.play("light")
        guard !isShowcase else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            picked = nil; message = nil; phase = .empty
        }
    }

    private func handle(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let e) = result { message = e.localizedDescription; phase = .error }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if let maxKB, Double(bytes) > maxKB * 1024 {
            message = "Attach a file no larger than \(Int(maxKB / 1024)) MB"
            picked = Picked(name: url.lastPathComponent, ext: url.pathExtension.uppercased(), bytes: bytes, localURL: nil)
            withAnimation { phase = .warning }
            return
        }
        let localURL = copyToTemp(url)
        let file = Picked(name: url.lastPathComponent, ext: url.pathExtension.uppercased(), bytes: bytes, localURL: localURL)
        // Brief "uploading" phase, then success — so the loading state is real.
        picked = file
        message = nil
        withAnimation(.easeInOut(duration: 0.2)) { phase = .loading }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation(.easeInOut(duration: 0.25)) { phase = .success }
        }
    }

    private func copyToTemp(_ url: URL) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sdui-picked", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    private static func icon(for ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.text"
        case "png", "jpg", "jpeg", "heic", "gif", "webp": return "photo"
        case "mp4", "mov", "m4v": return "film"
        case "zip", "rar", "7z": return "doc.zipper"
        case "json", "txt", "md", "csv": return "doc.plaintext"
        default: return "doc"
        }
    }

    private static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
#endif

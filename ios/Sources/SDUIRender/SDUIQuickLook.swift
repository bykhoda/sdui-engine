#if os(iOS)
import UIKit
import QuickLook
import UniformTypeIdentifiers

/// Native `preview` action: hands one or more URLs to the system's
/// `QLPreviewController` — the exact full-screen viewer Files, Mail and Photos
/// use. Photos, PDFs, video, audio, text and iWork/Office docs all render for
/// free, with system share and swipe-between-items built in.
///
/// Remote URLs (an image on a CDN, a PDF link) are streamed to a temp cache
/// first, because QuickLook only reads local file URLs. The correct extension
/// is inferred from the response's MIME type so a bare URL still previews. A
/// single shared instance retains itself for the lifetime of the presentation
/// so the data source isn't deallocated mid-preview.
@MainActor
final class SDUIQuickLook: NSObject {
    static let shared = SDUIQuickLook()

    /// One item to preview: a resolved local file plus the title to show.
    private final class Item: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?
        init(url: URL, title: String?) { previewItemURL = url; previewItemTitle = title }
    }

    private var items: [Item] = []
    private var selfRetain: SDUIQuickLook?

    /// Resolve every URL to a local file (downloading remote ones), then present
    /// the system previewer starting on `index`. No-ops if nothing resolves.
    func present(urls: [String], index: Int) {
        let requested = urls.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !requested.isEmpty else { return }
        Haptics.play("light")
        Task { @MainActor in
            var resolved: [Item] = []
            for raw in requested {
                if let item = await Self.localItem(for: raw) { resolved.append(item) }
            }
            guard !resolved.isEmpty, let top = Self.topViewController() else { return }
            self.items = resolved
            let controller = QLPreviewController()
            controller.dataSource = self
            controller.delegate = self
            controller.currentPreviewItemIndex = min(max(0, index), resolved.count - 1)
            self.selfRetain = self
            top.present(controller, animated: true)
        }
    }

    /// Maps a URL string to a local file. Local/bundle files are used directly;
    /// remote files are downloaded once into a temp cache and reused thereafter.
    private static func localItem(for string: String) async -> Item? {
        // Already a local file path or file:// URL.
        if let fileURL = URL(string: string), fileURL.isFileURL,
           FileManager.default.fileExists(atPath: fileURL.path) {
            return Item(url: fileURL, title: fileURL.lastPathComponent)
        }
        if FileManager.default.fileExists(atPath: string) {
            let u = URL(fileURLWithPath: string)
            return Item(url: u, title: u.lastPathComponent)
        }
        // A resource bundled with the app, referenced by name.
        if let bundled = Bundle.main.url(forResource: (string as NSString).deletingPathExtension,
                                         withExtension: (string as NSString).pathExtension) {
            return Item(url: bundled, title: (string as NSString).lastPathComponent)
        }
        guard let remote = URL(string: string), remote.scheme?.hasPrefix("http") == true else { return nil }
        return await download(remote)
    }

    private static func download(_ remote: URL) async -> Item? {
        do {
            let (data, response) = try await URLSession.shared.data(from: remote)
            let title = niceTitle(remote: remote, response: response)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sdui-preview", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(cacheName(remote: remote, response: response))
            if !FileManager.default.fileExists(atPath: dest.path) { try data.write(to: dest) }
            return Item(url: dest, title: title)
        } catch {
            return nil
        }
    }

    /// A human title: the URL's filename when it has one, else a type-based label.
    private static func niceTitle(remote: URL, response: URLResponse) -> String {
        if let suggested = response.suggestedFilename, !suggested.isEmpty,
           !(suggested as NSString).pathExtension.isEmpty {
            return suggested
        }
        let last = remote.lastPathComponent
        if !last.isEmpty, last != "/" { return last }
        return "Preview"
    }

    /// A stable temp filename with the *correct* extension so QuickLook can pick a
    /// renderer even when the URL itself is extensionless (e.g. a CDN image route).
    private static func cacheName(remote: URL, response: URLResponse) -> String {
        var ext = remote.pathExtension
        if ext.isEmpty, let mime = response.mimeType,
           let type = UTType(mimeType: mime), let preferred = type.preferredFilenameExtension {
            ext = preferred
        }
        let key = String(UInt(bitPattern: remote.absoluteString.hashValue))
        return ext.isEmpty ? key : "\(key).\(ext)"
    }

    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        let key = windows.first(where: { $0.isKeyWindow }) ?? windows.first
        var top = key?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension SDUIQuickLook: QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { items.count }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        items[index]
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        items = []
        selfRetain = nil
    }
}
#endif

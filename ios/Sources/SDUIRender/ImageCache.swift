#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// A shared memory + disk image cache. AsyncImage re-fetches and re-decodes every
/// time a cell scrolls back into view — the number-one cause of janky image lists.
/// This keeps decoded images in an NSCache (instant, synchronous hits) and lets
/// URLSession persist responses to a generous disk cache across launches.
/// Thread-safe: NSCache and URLSession are both safe to touch from any thread.
final class SDUIImageCache: @unchecked Sendable {
    static let shared = SDUIImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        memory.countLimit = 250
        memory.totalCostLimit = 80 * 1024 * 1024   // ~80 MB of decoded images
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024, directory: nil)
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    /// Synchronous memory hit — lets a scrolling cell show its image with zero
    /// flicker instead of dropping back to a placeholder.
    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        guard let (data, _) = try? await session.data(from: url),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: url as NSURL, cost: data.count)
        return image
    }
}

/// Drop-in remote image backed by `SDUIImageCache`: a cached hit renders on the
/// first frame (no placeholder flash), a miss loads off-main and fades in.
struct RemoteImage<Loading: View, Failure: View>: View {
    let url: URL
    let fill: Bool
    @ViewBuilder let loading: () -> Loading
    @ViewBuilder let failure: () -> Failure

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else if failed {
                failure()
            } else {
                loading()
            }
        }
        .task(id: url) {
            if let hit = SDUIImageCache.shared.cached(url) { image = hit; return }
            if let loaded = await SDUIImageCache.shared.load(url) {
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            } else {
                failed = true
            }
        }
    }
}
#endif

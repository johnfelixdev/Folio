import CoreGraphics
import Foundation

/// Renders and remembers page thumbnails.
///
/// Keyed by page UUID rather than page index, which is the whole point: moving
/// pages around never invalidates the thumbnails of the pages that did not
/// change, so dragging in the light table stays smooth on long documents.
///
/// Rendering happens on the main actor. That is affordable because only visible
/// pages are ever asked for, and a 200pt render costs a few milliseconds. If
/// profiling ever shows stutter, the known escape hatch is to give the cache its
/// own engine instance on a background actor.
@MainActor
public final class ThumbnailCache {

    private struct Key: Hashable {
        let id: UUID
        let width: Int
        let height: Int
    }

    private var images: [Key: CGImage] = [:]
    private var order: [Key] = []
    private let limit: Int

    /// Number of actual renders performed. Tests assert on this; nothing else uses it.
    public private(set) var renderCount: Int = 0

    public init(limit: Int = 300) {
        self.limit = max(limit, 1)
    }

    /// The thumbnail for a page, rendering it if it is not already cached.
    public func image(
        for id: UUID,
        page index: Int,
        in document: FolioDocument,
        size: CGSize
    ) -> CGImage? {
        let key = Key(
            id: id,
            width: Int(size.width.rounded()),
            height: Int(size.height.rounded())
        )
        if let cached = images[key] { return cached }

        guard let rendered = try? document.render(page: index, fitting: size) else { return nil }
        renderCount += 1
        store(rendered, for: key)
        return rendered
    }

    /// Drops every cached size of one page. Call after rotating it.
    public func invalidate(_ id: UUID) {
        let doomed = order.filter { $0.id == id }
        for key in doomed { images[key] = nil }
        order.removeAll { $0.id == id }
    }

    public func evictAll() {
        images.removeAll()
        order.removeAll()
    }

    private func store(_ image: CGImage, for key: Key) {
        images[key] = image
        order.append(key)
        while order.count > limit {
            let oldest = order.removeFirst()
            images[oldest] = nil
        }
    }
}

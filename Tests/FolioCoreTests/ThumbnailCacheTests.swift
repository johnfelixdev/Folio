import Testing
import Foundation
import CoreGraphics
@testable import FolioCore

@MainActor
@Suite("ThumbnailCache")
struct ThumbnailCacheTests {

    private let size = CGSize(width: 120, height: 160)

    private func document(pages: Int) throws -> FolioDocument {
        try FolioDocument(data: PDFFactory.makeDocument(pageCount: pages), password: nil)
    }

    @Test("Rendering a page returns an image")
    func rendersAnImage() throws {
        let doc = try document(pages: 2)
        let cache = ThumbnailCache(limit: 50)
        let image = cache.image(for: doc.pageID(at: 0), page: 0, in: doc, size: size)
        #expect(image != nil)
        #expect(image!.width > 0)
    }

    @Test("Asking twice for the same page renders once")
    func cachesByIdentity() throws {
        let doc = try document(pages: 2)
        let cache = ThumbnailCache(limit: 50)
        _ = cache.image(for: doc.pageID(at: 0), page: 0, in: doc, size: size)
        _ = cache.image(for: doc.pageID(at: 0), page: 0, in: doc, size: size)
        #expect(cache.renderCount == 1)
    }

    @Test("Reordering does not re-render anything")
    func reorderDoesNotInvalidate() throws {
        let doc = try document(pages: 3)
        let cache = ThumbnailCache(limit: 50)
        for index in 0..<3 {
            _ = cache.image(for: doc.pageID(at: index), page: index, in: doc, size: size)
        }
        #expect(cache.renderCount == 3)

        try doc.perform(ReorderPages(order: [2, 0, 1]))
        for index in 0..<3 {
            _ = cache.image(for: doc.pageID(at: index), page: index, in: doc, size: size)
        }
        #expect(cache.renderCount == 3, "Reordering must not invalidate thumbnails")
    }

    @Test("A page's cached thumbnail follows it to its new index, rather than a stale one being returned for its old index")
    func reorderReturnsImageForCorrectIdentity() throws {
        let doc = try document(pages: 3)
        let cache = ThumbnailCache(limit: 50)
        let idOfPage2 = doc.pageID(at: 2)
        let originalImages = (0..<3).map {
            cache.image(for: doc.pageID(at: $0), page: $0, in: doc, size: size)
        }

        try doc.perform(ReorderPages(order: [2, 0, 1]))
        #expect(doc.pageID(at: 0) == idOfPage2)
        let imageAfterReorder = cache.image(for: idOfPage2, page: 0, in: doc, size: size)

        #expect(imageAfterReorder === originalImages[2])
    }

    @Test("Rotating invalidates only the rotated page")
    func rotationInvalidatesOnePage() throws {
        let doc = try document(pages: 3)
        let cache = ThumbnailCache(limit: 50)
        for index in 0..<3 {
            _ = cache.image(for: doc.pageID(at: index), page: index, in: doc, size: size)
        }
        try doc.perform(RotatePages(indices: IndexSet([1]), quarterTurns: 1))
        cache.invalidate(doc.pageID(at: 1))
        for index in 0..<3 {
            _ = cache.image(for: doc.pageID(at: index), page: index, in: doc, size: size)
        }
        #expect(cache.renderCount == 4)
    }

    @Test("Different sizes are cached separately")
    func sizeIsPartOfTheKey() throws {
        let doc = try document(pages: 1)
        let cache = ThumbnailCache(limit: 50)
        _ = cache.image(for: doc.pageID(at: 0), page: 0, in: doc, size: size)
        _ = cache.image(for: doc.pageID(at: 0), page: 0, in: doc,
                        size: CGSize(width: 400, height: 500))
        #expect(cache.renderCount == 2)
    }

    @Test("Evicting everything forces a re-render")
    func evictAll() throws {
        let doc = try document(pages: 1)
        let cache = ThumbnailCache(limit: 50)
        _ = cache.image(for: doc.pageID(at: 0), page: 0, in: doc, size: size)
        cache.evictAll()
        _ = cache.image(for: doc.pageID(at: 0), page: 0, in: doc, size: size)
        #expect(cache.renderCount == 2)
    }

    @Test("The limit actually bounds the cache: the oldest entry is evicted, not just tracked")
    func limitEvictsOldestEntry() throws {
        let doc = try document(pages: 3)
        let cache = ThumbnailCache(limit: 2)
        _ = cache.image(for: doc.pageID(at: 0), page: 0, in: doc, size: size)
        _ = cache.image(for: doc.pageID(at: 1), page: 1, in: doc, size: size)
        _ = cache.image(for: doc.pageID(at: 2), page: 2, in: doc, size: size)
        #expect(cache.renderCount == 3)

        // Page 0 was the oldest of 3 entries under a limit of 2, so it must have
        // been dropped: asking for it again has to render it once more.
        _ = cache.image(for: doc.pageID(at: 0), page: 0, in: doc, size: size)
        #expect(cache.renderCount == 4, "A limit that never evicts is a limit in name only")

        // Page 2 was still within the limit and must still be cached.
        _ = cache.image(for: doc.pageID(at: 2), page: 2, in: doc, size: size)
        #expect(cache.renderCount == 4, "Page 2 was within the limit and should not have been evicted")
    }
}

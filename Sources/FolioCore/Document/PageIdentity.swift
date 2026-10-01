import Foundation

/// Gives every page a UUID that survives reordering.
///
/// PDFKit's `PDFPage` has no stable identifier, and SwiftUI needs one to animate
/// a reorder instead of redrawing the whole strip. The thumbnail cache is keyed
/// by these UUIDs too, so moving or rotating pages never invalidates the
/// thumbnails of the pages that did not change.
@MainActor
final class PageIdentity {

    private var ids: [UUID]

    init(pageCount: Int) {
        ids = (0..<pageCount).map { _ in UUID() }
    }

    var count: Int { ids.count }

    func id(forPageAt index: Int) -> UUID {
        guard ids.indices.contains(index) else { return UUID() }
        return ids[index]
    }

    /// Mirrors `PDFEngine.reorderPages(to:)`.
    func reorder(to order: [Int]) {
        guard order.count == ids.count else { return }
        ids = order.map { ids[$0] }
    }

    /// Mirrors `PDFEngine.removePages(_:)`.
    func remove(_ indices: IndexSet) {
        for index in indices.sorted(by: >) where ids.indices.contains(index) {
            ids.remove(at: index)
        }
    }

    /// Mirrors `PDFEngine.insertPages(_:)`.
    func insert(at indices: [Int]) {
        for index in indices.sorted() where index >= 0 && index <= ids.count {
            ids.insert(UUID(), at: index)
        }
    }
}

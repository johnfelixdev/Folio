import Foundation

/// An engine-neutral carrier for one page pulled out of a document.
///
/// The bytes are opaque to everything above the engine layer: only the engine
/// that produced a snapshot knows how to put it back. This is what lets
/// `DeletePages` hand its removed pages to its own inverse without any layer
/// above the engine learning what a PDF page is.
public struct PageSnapshot: Sendable, Equatable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }
}

/// A snapshot together with the index it should occupy.
///
/// Insertions are always applied in ascending index order, which makes a single
/// operation cover both merging a document (contiguous indices) and undoing a
/// scattered deletion (gapped indices).
public struct PagePlacement: Sendable, Equatable {
    public let index: Int
    public let snapshot: PageSnapshot

    public init(index: Int, snapshot: PageSnapshot) {
        self.index = index
        self.snapshot = snapshot
    }
}

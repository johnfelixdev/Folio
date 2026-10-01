import Foundation

/// Removes pages. Its inverse carries the removed pages inside it, which is why
/// undoing a deletion returns them intact, in place, with their rotation.
public struct DeletePages: PageCommand {

    public let indices: IndexSet

    public var name: String { "Borrar páginas" }

    public init(indices: IndexSet) {
        self.indices = indices
    }

    @discardableResult
    public func apply(to engine: any PDFEngine) throws -> any PageCommand {
        let removed = try engine.removePages(indices)
        let placements = zip(indices.sorted(), removed).map {
            PagePlacement(index: $0, snapshot: $1)
        }
        return InsertPages(placements: placements)
    }
}

/// Puts pages into the document at given positions, in ascending index order.
///
/// One command covers both merging another PDF (contiguous indices) and undoing
/// a scattered deletion (gapped indices).
public struct InsertPages: PageCommand {

    public let placements: [PagePlacement]

    public var name: String { "Insertar páginas" }

    public init(placements: [PagePlacement]) {
        self.placements = placements
    }

    @discardableResult
    public func apply(to engine: any PDFEngine) throws -> any PageCommand {
        try engine.insertPages(placements)
        return DeletePages(indices: IndexSet(placements.map(\.index)))
    }

    /// Builds a command that merges every page of `documentData` starting at `index`.
    ///
    /// Reading happens here, before anything is applied, so an unreadable or
    /// locked file is refused while the target document is still untouched.
    public static func merging(
        documentData: Data,
        at index: Int,
        password: String?
    ) throws -> InsertPages {
        let source = try PDFKitEngine(data: documentData, password: password)
        let all = IndexSet(integersIn: 0..<source.pageCount)
        let snapshots = try source.removePagesForCopying(all)
        let placements = snapshots.enumerated().map {
            PagePlacement(index: index + $0.offset, snapshot: $0.element)
        }
        return InsertPages(placements: placements)
    }

    /// One command for dropping several PDFs at once.
    ///
    /// Each file starts where the previous one ended, so they land in the
    /// order given. Every file is read before the command exists, so one
    /// unreadable or locked file refuses the whole drop while the target is
    /// still untouched; and being a single command, it applies all or nothing
    /// and undoes in one step.
    public static func merging(
        documents: [Data],
        at index: Int,
        password: String?
    ) throws -> InsertPages {
        var next = index
        var placements: [PagePlacement] = []
        for data in documents {
            let file = try merging(documentData: data, at: next, password: password)
            placements += file.placements
            next += file.placements.count
        }
        return InsertPages(placements: placements)
    }
}

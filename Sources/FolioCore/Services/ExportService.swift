import Foundation

/// Produces new documents from an existing one.
///
/// Nothing here mutates anything: splitting and extracting read the source and
/// write new files. That is why they are a service and not commands, and why
/// they never appear in the undo stack.
@MainActor
public enum ExportService {

    /// A new document containing only `pages`, in ascending order.
    public static func extract(pages: IndexSet, from data: Data) throws -> Data {
        guard !pages.isEmpty else { throw EngineError.emptyDocument }
        let source = try PDFKitEngine(data: data, password: nil)
        guard pages.allSatisfy({ $0 >= 0 && $0 < source.pageCount }) else {
            throw EngineError.indexOutOfRange
        }

        let keep = IndexSet(0..<source.pageCount).subtracting(pages)
        guard !keep.isEmpty else { return try source.serialize() }
        _ = try source.removePages(keep)
        return try source.serialize()
    }

    /// Cuts the document before each boundary index.
    ///
    /// `split(fivePages, at: [2, 4])` yields pages `0-1`, `2-3` and `4`.
    /// Boundaries may arrive unsorted or duplicated; both are tolerated.
    public static func split(_ data: Data, at boundaries: [Int]) throws -> [Data] {
        let probe = try PDFKitEngine(data: data, password: nil)
        let pageCount = probe.pageCount

        let cuts = Set(boundaries).sorted()
        guard cuts.allSatisfy({ $0 > 0 && $0 < pageCount }) else {
            throw EngineError.indexOutOfRange
        }

        var ranges: [Range<Int>] = []
        var start = 0
        for cut in cuts {
            ranges.append(start..<cut)
            start = cut
        }
        ranges.append(start..<pageCount)

        return try ranges.map { try extract(pages: IndexSet(integersIn: $0), from: data) }
    }
}

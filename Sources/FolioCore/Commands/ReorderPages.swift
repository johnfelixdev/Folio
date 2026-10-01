import Foundation

/// Rearranges the whole document: the new page at position `i` is the old page
/// at `order[i]`.
public struct ReorderPages: PageCommand {

    public let order: [Int]

    public var name: String { "Reordenar páginas" }

    public init(order: [Int]) {
        self.order = order
    }

    @discardableResult
    public func apply(to engine: any PDFEngine) throws -> any PageCommand {
        try engine.reorderPages(to: order)
        return ReorderPages(order: Self.invert(order))
    }

    /// The permutation that puts everything back.
    static func invert(_ order: [Int]) -> [Int] {
        var inverted = [Int](repeating: 0, count: order.count)
        for (newPosition, oldPosition) in order.enumerated() {
            inverted[oldPosition] = newPosition
        }
        return inverted
    }
}

/// Lifts a set of pages out and drops them in at `destination`, keeping their
/// relative order. `destination` is an index in the *original* numbering, so
/// dropping after the last page means `destination == pageCount`.
public struct MovePages: PageCommand {

    public let indices: IndexSet
    public let destination: Int

    public var name: String { "Mover páginas" }

    public init(indices: IndexSet, destination: Int) {
        self.indices = indices
        self.destination = destination
    }

    @discardableResult
    public func apply(to engine: any PDFEngine) throws -> any PageCommand {
        let order = try permutation(pageCount: engine.pageCount)
        return try ReorderPages(order: order).apply(to: engine)
    }

    /// Turns "move these pages there" into a full permutation.
    func permutation(pageCount: Int) throws -> [Int] {
        guard indices.allSatisfy({ $0 >= 0 && $0 < pageCount }),
              destination >= 0, destination <= pageCount
        else { throw EngineError.indexOutOfRange }

        let moving = indices.sorted()
        let staying = (0..<pageCount).filter { !indices.contains($0) }
        // How many of the moved pages started before the drop point: the drop
        // point shifts left by that many once they are lifted out.
        let insertionPoint = destination - moving.filter { $0 < destination }.count

        var result = Array(staying[0..<insertionPoint])
        result.append(contentsOf: moving)
        result.append(contentsOf: staying[insertionPoint...])
        return result
    }
}

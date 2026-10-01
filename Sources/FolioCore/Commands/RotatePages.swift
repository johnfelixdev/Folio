import Foundation

/// Turns pages in 90° steps. Positive turns clockwise.
public struct RotatePages: PageCommand {

    public let indices: IndexSet
    public let quarterTurns: Int

    public var name: String { "Rotar páginas" }

    public init(indices: IndexSet, quarterTurns: Int) {
        self.indices = indices
        self.quarterTurns = quarterTurns
    }

    @discardableResult
    public func apply(to engine: any PDFEngine) throws -> any PageCommand {
        try engine.rotatePages(indices, quarterTurns: quarterTurns)
        return RotatePages(indices: indices, quarterTurns: -quarterTurns)
    }
}

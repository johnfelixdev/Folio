import Foundation

/// One undoable mutation of a document.
///
/// `apply` returns the command that undoes it, rather than there being a
/// separate `inverse()`. The reason is concrete: the inverse of a deletion
/// needs the deleted pages, and the inverse of a reorder needs the previous
/// order. Both only exist *during* application. A separate `inverse()` would
/// have to guess or duplicate that bookkeeping, which is where undo bugs live.
@MainActor
public protocol PageCommand: Sendable {
    /// Shown in the system undo menu, e.g. "Deshacer Rotar páginas".
    var name: String { get }

    @discardableResult
    func apply(to engine: any PDFEngine) throws -> any PageCommand
}

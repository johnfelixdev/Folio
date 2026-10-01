import Foundation

/// Rebuilds the document without encryption, so it can be printed and copied.
///
/// This is a real change, not a flag: PDFKit preserves a document's encryption
/// when it rewrites it (see `EngineProtectionTests.savingPreservesRestrictions`),
/// so the only way to produce an unrestricted file is to copy the pages into a
/// fresh document. Afterwards `protection` reports `.open` on its own.
public struct RemoveRestrictions: PageCommand {

    public var name: String { "Quitar restricciones" }

    public init() {}

    @discardableResult
    public func apply(to engine: any PDFEngine) throws -> any PageCommand {
        RestoreDocument(data: try engine.stripProtection())
    }
}

/// Puts the document back to a state captured before it was rebuilt.
///
/// Carries the whole previous document inside it. That is the cost of undoing
/// decryption: the owner password is not ours, so nothing can be recomputed and
/// the bytes have to be kept.
public struct RestoreDocument: PageCommand {

    public let data: Data

    public var name: String { "Restaurar restricciones" }

    public init(data: Data) {
        self.data = data
    }

    @discardableResult
    public func apply(to engine: any PDFEngine) throws -> any PageCommand {
        let current = try engine.serialize()
        try engine.restore(from: data)
        return RestoreDocument(data: current)
    }
}

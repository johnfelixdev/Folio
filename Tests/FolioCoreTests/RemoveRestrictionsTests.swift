import Testing
import CoreGraphics
import Foundation
@testable import FolioCore

@MainActor
@Suite("Commands · restrictions")
struct RemoveRestrictionsTests {

    private func restricted(pages: Int = 2) throws -> PDFKitEngine {
        try PDFKitEngine(data: EncryptedPDFFactory.makeRestricted(pageCount: pages), password: nil)
    }

    @Test("Removing restrictions actually unprotects the document")
    func removes() throws {
        let engine = try restricted()
        _ = try RemoveRestrictions().apply(to: engine)
        #expect(engine.protection == .open)
    }

    @Test("The unprotected state survives a save")
    func survivesSave() throws {
        let engine = try restricted()
        _ = try RemoveRestrictions().apply(to: engine)
        let reopened = try PDFKitEngine(data: try engine.serialize(), password: nil)
        #expect(reopened.protection == .open)
    }

    @Test("Undoing puts the restrictions back")
    func undo() throws {
        let engine = try restricted()
        let undo = try RemoveRestrictions().apply(to: engine)
        #expect(engine.protection == .open)

        _ = try undo.apply(to: engine)
        guard case .restricted = engine.protection else {
            Issue.record("Undo did not restore the restrictions: got \(engine.protection)")
            return
        }
    }

    @Test("Removing restrictions leaves page order and rotation alone")
    func leavesPagesAlone() throws {
        let engine = try restricted(pages: 3)
        try engine.rotatePages(IndexSet(integer: 1), quarterTurns: 1)
        _ = try RemoveRestrictions().apply(to: engine)

        let written = try engine.serialize()
        #expect(PDFFactory.pageWidths(of: written) == [600, 601, 602])
        #expect(PDFFactory.pageRotations(of: written) == [0, 90, 0])
    }

    @Test("Removing restrictions keeps the title, the author and the bookmarks")
    func keepsDocumentInformation() throws {
        let source = EncryptedPDFFactory.makeRestricted(
            pageCount: 3,
            info: [
                kCGPDFContextTitle as String: "Informe anual",
                kCGPDFContextAuthor as String: "Ana Pérez",
            ],
            outline: [("Introducción", 0), ("Resultados", 2)]
        )
        // The fixture itself must carry what we are about to check for,
        // or the assertions below would pass on an empty document.
        #expect(PDFFactory.infoString("Title", of: source) == "Informe anual")
        #expect(PDFFactory.outline(of: source).map { $0.title } == ["Introducción", "Resultados"])

        let engine = try PDFKitEngine(data: source, password: nil)
        _ = try RemoveRestrictions().apply(to: engine)
        let written = try engine.serialize()

        #expect(PDFFactory.infoString("Title", of: written) == "Informe anual")
        #expect(PDFFactory.infoString("Author", of: written) == "Ana Pérez")
        let outline = PDFFactory.outline(of: written)
        #expect(outline.map { $0.title } == ["Introducción", "Resultados"])
        #expect(outline.map { $0.page } == [0, 2])
    }

    @Test("Undo then redo lands back on unprotected")
    func redo() throws {
        let engine = try restricted()
        let undo = try RemoveRestrictions().apply(to: engine)
        let redo = try undo.apply(to: engine)
        _ = try redo.apply(to: engine)
        #expect(engine.protection == .open)
    }

    @Test("Commands carry a name for the undo menu")
    func names() {
        #expect(RemoveRestrictions().name == "Quitar restricciones")
        #expect(RestoreDocument(data: Data()).name == "Restaurar restricciones")
    }
}

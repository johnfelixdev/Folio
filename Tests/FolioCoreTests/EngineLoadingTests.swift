import Testing
import Foundation
@testable import FolioCore

@MainActor
@Suite("Engine · loading and serialising")
struct EngineLoadingTests {

    @Test("Loading reports the page count")
    func pageCount() throws {
        let engine = try PDFKitEngine(data: PDFFactory.makeDocument(pageCount: 5), password: nil)
        #expect(engine.pageCount == 5)
    }

    @Test("Serialising round-trips page order")
    func roundTrip() throws {
        let engine = try PDFKitEngine(data: PDFFactory.makeDocument(pageCount: 3), password: nil)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [600, 601, 602])
    }

    /// The round-trip test above passes even if `serialize()` hands back its own
    /// input untouched, so on its own it proves nothing about the engine.
    ///
    /// This one closes that hole, and asserts something the project actually
    /// depends on: PDFKit *rewrites* the document rather than echoing the
    /// original bytes. That rewrite is exactly why saving a restricted PDF
    /// cannot preserve its encryption — see `EngineProtectionTests`.
    @Test("Serialising rewrites the document rather than echoing the input")
    func serialisationRewrites() throws {
        let original = PDFFactory.makeDocument(pageCount: 3)
        let engine = try PDFKitEngine(data: original, password: nil)
        let written = try engine.serialize()

        #expect(written != original, "A passthrough serialize() would return the input unchanged")
        #expect(PDFFactory.pageWidths(of: written) == [600, 601, 602], "…while still being a valid PDF")
    }

    @Test("Garbage input is rejected instead of loading a broken document")
    func rejectsGarbage() {
        let junk = Data("this is definitely not a pdf".utf8)
        #expect(throws: EngineError.unreadable) {
            _ = try PDFKitEngine(data: junk, password: nil)
        }
    }

    @Test("A freshly generated document reports no protection")
    func unprotectedByDefault() throws {
        let engine = try PDFKitEngine(data: PDFFactory.makeDocument(pageCount: 1), password: nil)
        #expect(engine.protection == .open)
    }

    @Test("Rotation of every page starts at zero")
    func rotationsStartAtZero() throws {
        let engine = try PDFKitEngine(data: PDFFactory.makeDocument(pageCount: 2), password: nil)
        #expect(engine.rotation(ofPage: 0) == 0)
        #expect(engine.rotation(ofPage: 1) == 0)
    }
}

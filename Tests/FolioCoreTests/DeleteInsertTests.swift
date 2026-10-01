import Testing
import Foundation
@testable import FolioCore

@MainActor
@Suite("Commands · delete and insert")
struct DeleteInsertTests {

    private func engine(pages: Int) throws -> PDFKitEngine {
        try PDFKitEngine(data: PDFFactory.makeDocument(pageCount: pages), password: nil)
    }

    @Test("Deleting removes the selected pages")
    func deleteApplies() throws {
        let engine = try engine(pages: 4)
        _ = try DeletePages(indices: IndexSet([1, 2])).apply(to: engine)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [600, 603])
    }

    @Test("Undoing a deletion puts the pages back where they were")
    func deleteInvariant() throws {
        try CommandInvariant.check(DeletePages(indices: IndexSet([1, 2])), on: try engine(pages: 4))
        try CommandInvariant.check(DeletePages(indices: IndexSet([0])), on: try engine(pages: 4))
        try CommandInvariant.check(DeletePages(indices: IndexSet([0, 3])), on: try engine(pages: 4))
        try CommandInvariant.check(DeletePages(indices: IndexSet([3])), on: try engine(pages: 4))
    }

    @Test("Undoing a deletion restores rotation too")
    func deleteRestoresRotation() throws {
        let engine = try engine(pages: 3)
        _ = try RotatePages(indices: IndexSet([1]), quarterTurns: 1).apply(to: engine)
        try CommandInvariant.check(DeletePages(indices: IndexSet([1])), on: engine)
    }

    @Test("Deleting every page is refused")
    func deleteAllRefused() throws {
        let engine = try engine(pages: 2)
        #expect(throws: EngineError.emptyDocument) {
            _ = try DeletePages(indices: IndexSet([0, 1])).apply(to: engine)
        }
        #expect(engine.pageCount == 2)
    }

    /// `merge` below only counts pages, and `mergeInvariant` only proves the
    /// operation cancels out — both pass even if `at:` is ignored entirely and
    /// every merge lands at position 0. This pins down where the pages go.
    @Test("Merging puts the incoming pages at the requested index")
    func mergeLandsWhereAsked() throws {
        let engine = try engine(pages: 3)                  // 600, 601, 602
        let incoming = PDFFactory.makeDocument(pageCount: 2)  // 600, 601
        _ = try InsertPages.merging(documentData: incoming, at: 1, password: nil)
            .apply(to: engine)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [600, 600, 601, 601, 602])
    }

    /// `InsertPages` documents that placements apply in ascending index order,
    /// but every caller so far happens to build them pre-sorted, so nothing
    /// forces the sort to exist. Hand it deliberately unsorted input.
    @Test("Placements apply in ascending order however they arrive")
    func placementsAreSorted() throws {
        let engine = try engine(pages: 4)
        let removed = try engine.removePages(IndexSet([0, 2]))   // leaves 601, 603
        let descending = [
            PagePlacement(index: 2, snapshot: removed[1]),
            PagePlacement(index: 0, snapshot: removed[0]),
        ]
        _ = try InsertPages(placements: descending).apply(to: engine)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [600, 601, 602, 603])
    }

    @Test("Merging another document inserts all of its pages")
    func merge() throws {
        let engine = try engine(pages: 2)
        let incoming = PDFFactory.makeDocument(pageCount: 2)
        let command = try InsertPages.merging(documentData: incoming, at: 1, password: nil)
        _ = try command.apply(to: engine)
        #expect(PDFFactory.pageCount(of: try engine.serialize()) == 4)
    }

    @Test("Undoing a merge leaves the original untouched")
    func mergeInvariant() throws {
        let engine = try engine(pages: 3)
        let incoming = PDFFactory.makeDocument(pageCount: 2)
        let command = try InsertPages.merging(documentData: incoming, at: 1, password: nil)
        try CommandInvariant.check(command, on: engine)
    }

    @Test("Merging an unreadable file is refused before anything changes")
    func mergeRejectsGarbage() throws {
        let engine = try engine(pages: 2)
        #expect(throws: EngineError.unreadable) {
            _ = try InsertPages.merging(
                documentData: Data("not a pdf".utf8), at: 0, password: nil)
        }
        #expect(engine.pageCount == 2)
    }

    @Test("Merging a locked file without its password is refused")
    func mergeRejectsLocked() throws {
        let locked = EncryptedPDFFactory.makeLocked(pageCount: 1)
        #expect(throws: EngineError.stillLocked) {
            _ = try InsertPages.merging(documentData: locked, at: 0, password: nil)
        }
    }

    @Test("Merging several files keeps them in the order they were dropped")
    func mergeSeveralKeepsOrder() throws {
        let engine = try engine(pages: 1)
        let command = try InsertPages.merging(
            documents: [PDFFactory.makeDocument(pageCount: 2), PDFFactory.makeDocument(pageCount: 3)],
            at: 1,
            password: nil
        )
        _ = try command.apply(to: engine)
        // Both incoming files start at width 600, so their lengths tell them apart:
        // the two-page file must come first, the three-page file after it.
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [600, 600, 601, 600, 601, 602])
    }

    @Test("One unreadable file refuses the whole drop before anything is built")
    func mergeSeveralRefusesAsAWhole() throws {
        #expect(throws: EngineError.unreadable) {
            _ = try InsertPages.merging(
                documents: [PDFFactory.makeDocument(pageCount: 2), Data("not a pdf".utf8)],
                at: 0,
                password: nil
            )
        }
    }

    @Test("An insert that fails partway leaves the document untouched")
    func insertIsAllOrNothing() throws {
        let engine = try engine(pages: 2)
        let good = try engine.removePagesForCopying(IndexSet(integer: 0))[0]
        let placements = [
            PagePlacement(index: 0, snapshot: good),
            PagePlacement(index: 1, snapshot: PageSnapshot(data: Data("not a pdf".utf8))),
        ]
        #expect(throws: EngineError.unreadable) {
            try engine.insertPages(placements)
        }
        // The first, valid page must not have gone in on its own.
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [600, 601])
    }

    @Test("Dropping several files is a single step to undo")
    func mergeSeveralUndoesAtOnce() throws {
        let engine = try engine(pages: 1)
        let command = try InsertPages.merging(
            documents: [PDFFactory.makeDocument(pageCount: 2), PDFFactory.makeDocument(pageCount: 1)],
            at: 1,
            password: nil
        )
        let undo = try command.apply(to: engine)
        _ = try undo.apply(to: engine)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [600])
    }

    @Test("Commands carry a name for the undo menu")
    func names() {
        #expect(DeletePages(indices: IndexSet([0])).name == "Borrar páginas")
        #expect(InsertPages(placements: []).name == "Insertar páginas")
    }
}

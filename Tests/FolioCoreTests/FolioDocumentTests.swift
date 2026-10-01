import Testing
import Foundation
@testable import FolioCore

@MainActor
@Suite("FolioDocument")
struct FolioDocumentTests {

    private func document(pages: Int) throws -> FolioDocument {
        try FolioDocument(data: PDFFactory.makeDocument(pageCount: pages), password: nil)
    }

    @Test("A new document is not modified")
    func startsClean() throws {
        #expect(try document(pages: 3).isModified == false)
    }

    @Test("Performing a command marks the document modified")
    func performMarksModified() throws {
        let doc = try document(pages: 3)
        try doc.perform(RotatePages(indices: IndexSet([0]), quarterTurns: 1))
        #expect(doc.isModified)
    }

    @Test("Page identities are stable across a reorder")
    func identityFollowsReorder() throws {
        let doc = try document(pages: 3)
        let idsBefore = (0..<3).map { doc.pageID(at: $0) }
        try doc.perform(ReorderPages(order: [2, 0, 1]))
        let idsAfter = (0..<3).map { doc.pageID(at: $0) }
        #expect(idsAfter == [idsBefore[2], idsBefore[0], idsBefore[1]])
    }

    /// The `MovePages` branch of `syncIdentity` is the one the light table
    /// exercises constantly, and a no-op there passes every other test in the
    /// suite. Moving pages 0 and 1 to the end permutes to `[2, 3, 0, 1, 4]`.
    @Test("Page identities follow a move")
    func identityFollowsMove() throws {
        let doc = try document(pages: 5)
        let before = (0..<5).map { doc.pageID(at: $0) }
        try doc.perform(MovePages(indices: IndexSet([0, 1]), destination: 4))
        #expect((0..<5).map { doc.pageID(at: $0) }
            == [before[2], before[3], before[0], before[1], before[4]])
    }

    @Test("Page identities are stable across a rotation")
    func identitySurvivesRotation() throws {
        let doc = try document(pages: 2)
        let before = (0..<2).map { doc.pageID(at: $0) }
        try doc.perform(RotatePages(indices: IndexSet([0]), quarterTurns: 1))
        #expect((0..<2).map { doc.pageID(at: $0) } == before)
    }

    @Test("Deleting drops the identity and undo brings a fresh one")
    func identityAcrossDelete() throws {
        let doc = try document(pages: 3)
        let before = (0..<3).map { doc.pageID(at: $0) }
        try doc.perform(DeletePages(indices: IndexSet([1])))
        #expect((0..<2).map { doc.pageID(at: $0) } == [before[0], before[2]])
        #expect(doc.pageCount == 2)
    }

    @Test("Undo restores order through the document")
    func undoThroughDocument() throws {
        let doc = try document(pages: 4)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        try doc.perform(ReorderPages(order: [3, 2, 1, 0]))
        #expect(PDFFactory.pageWidths(of: try doc.serialize()) == [603, 602, 601, 600])

        undoManager.undo()
        #expect(PDFFactory.pageWidths(of: try doc.serialize()) == [600, 601, 602, 603])
    }

    @Test("Redo reapplies the command")
    func redo() throws {
        let doc = try document(pages: 3)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        try doc.perform(DeletePages(indices: IndexSet([0])))
        undoManager.undo()
        #expect(doc.pageCount == 3)
        undoManager.redo()
        #expect(doc.pageCount == 2)
    }

    @Test("A failed command leaves the document untouched and unmodified")
    func failedCommandIsInert() throws {
        let doc = try document(pages: 2)
        #expect(throws: EngineError.emptyDocument) {
            try doc.perform(DeletePages(indices: IndexSet([0, 1])))
        }
        #expect(doc.pageCount == 2)
        #expect(doc.isModified == false)
    }

    @Test("Only rotation reports a stale thumbnail")
    func invalidationIsPrecise() throws {
        let doc = try document(pages: 3)
        let rotatedID = doc.pageID(at: 1)

        // new[i] = old[order[i]] (see ReorderPages), so order[0] == 1 puts the
        // old page 1 at the new page 0 — matching the assertion below.
        try doc.perform(ReorderPages(order: [1, 2, 0]))
        #expect(doc.invalidatedPageIDs.isEmpty, "Reordering does not change how any page looks")

        try doc.perform(RotatePages(indices: IndexSet([0]), quarterTurns: 1))
        #expect(doc.invalidatedPageIDs == [rotatedID],
                "After the reorder, page 0 is the one that used to be page 1")
    }

    @Test("Saving clears the modified flag")
    func savingClearsModified() throws {
        let doc = try document(pages: 2)
        try doc.perform(RotatePages(indices: IndexSet([0]), quarterTurns: 1))
        _ = try doc.serialize()
        doc.markSaved()
        #expect(doc.isModified == false)
    }
}

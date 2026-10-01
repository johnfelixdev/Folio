import Testing
import Foundation
@testable import FolioCore

/// Applying a command and then applying what it returned must leave the
/// document equivalent in page order and rotation.
///
/// **What this does NOT prove.** It only shows a command is *invertible*, never
/// that it does the right thing. A command that computes the wrong permutation
/// and then correctly inverts that wrong permutation passes cleanly. Forward
/// correctness needs exact-value assertions, so every command needs both.
///
/// It also leans on `PDFFactory` giving each page a unique width: that is the
/// fingerprint used to tell pages apart. A fixture with two same-width pages
/// would silently weaken it.
@MainActor
enum CommandInvariant {

    /// Applies `command`, then its inverse, and asserts the document came back.
    static func check(
        _ command: any PageCommand,
        on engine: PDFKitEngine,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let before = try engine.serialize()
        let widthsBefore = PDFFactory.pageWidths(of: before)
        let rotationsBefore = PDFFactory.pageRotations(of: before)

        let undo = try command.apply(to: engine)
        _ = try undo.apply(to: engine)

        let after = try engine.serialize()
        #expect(
            PDFFactory.pageWidths(of: after) == widthsBefore,
            "Page order was not restored by the inverse of \(command.name)",
            sourceLocation: sourceLocation
        )
        #expect(
            PDFFactory.pageRotations(of: after) == rotationsBefore,
            "Rotations were not restored by the inverse of \(command.name)",
            sourceLocation: sourceLocation
        )
    }
}

@MainActor
@Suite("Commands · reorder and rotate")
struct ReorderAndRotateTests {

    private func engine(pages: Int) throws -> PDFKitEngine {
        try PDFKitEngine(data: PDFFactory.makeDocument(pageCount: pages), password: nil)
    }

    @Test("Reordering applies the permutation")
    func reorderApplies() throws {
        let engine = try engine(pages: 4)
        _ = try ReorderPages(order: [3, 2, 1, 0]).apply(to: engine)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [603, 602, 601, 600])
    }

    @Test("Reordering is undone exactly")
    func reorderInvariant() throws {
        try CommandInvariant.check(ReorderPages(order: [3, 0, 2, 1]), on: try engine(pages: 4))
    }

    @Test("Moving a contiguous block forward lands where expected")
    func moveForward() throws {
        let engine = try engine(pages: 5)
        _ = try MovePages(indices: IndexSet([0, 1]), destination: 4).apply(to: engine)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [602, 603, 600, 601, 604])
    }

    @Test("Moving a block backward lands where expected")
    func moveBackward() throws {
        let engine = try engine(pages: 5)
        _ = try MovePages(indices: IndexSet([3, 4]), destination: 1).apply(to: engine)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [600, 603, 604, 601, 602])
    }

    @Test("Moving scattered pages keeps their relative order")
    func moveScattered() throws {
        let engine = try engine(pages: 5)
        _ = try MovePages(indices: IndexSet([0, 3]), destination: 5).apply(to: engine)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [601, 602, 604, 600, 603])
    }

    /// `CommandInvariant.check` cannot catch a wrong permutation, only a wrong
    /// inverse — so the boundary where `destination` lands inside the moved
    /// selection needs an exact-value assertion of its own. Moving pages 1 and 2
    /// to position 2 should change nothing; an off-by-one in the insertion
    /// offset turns it into `[601, 602, 600, 603, 604]`.
    @Test("Moving a block onto its own position changes nothing")
    func moveOntoItself() throws {
        let engine = try engine(pages: 5)
        _ = try MovePages(indices: IndexSet([1, 2]), destination: 2).apply(to: engine)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [600, 601, 602, 603, 604])
    }

    @Test("Every move is undone exactly")
    func moveInvariant() throws {
        try CommandInvariant.check(
            MovePages(indices: IndexSet([0, 3]), destination: 5), on: try engine(pages: 5))
        try CommandInvariant.check(
            MovePages(indices: IndexSet([4]), destination: 0), on: try engine(pages: 5))
        try CommandInvariant.check(
            MovePages(indices: IndexSet([1, 2]), destination: 2), on: try engine(pages: 5))
    }

    @Test("Rotating turns the selected pages")
    func rotateApplies() throws {
        let engine = try engine(pages: 3)
        _ = try RotatePages(indices: IndexSet([1]), quarterTurns: 1).apply(to: engine)
        #expect(PDFFactory.pageRotations(of: try engine.serialize()) == [0, 90, 0])
    }

    @Test("Every rotation is undone exactly")
    func rotateInvariant() throws {
        try CommandInvariant.check(
            RotatePages(indices: IndexSet([0, 2]), quarterTurns: 1), on: try engine(pages: 3))
        try CommandInvariant.check(
            RotatePages(indices: IndexSet([1]), quarterTurns: -1), on: try engine(pages: 3))
        try CommandInvariant.check(
            RotatePages(indices: IndexSet([0]), quarterTurns: 2), on: try engine(pages: 3))
    }

    @Test("Commands carry a name for the undo menu")
    func names() {
        #expect(ReorderPages(order: [0]).name == "Reordenar páginas")
        #expect(MovePages(indices: IndexSet([0]), destination: 0).name == "Mover páginas")
        #expect(RotatePages(indices: IndexSet([0]), quarterTurns: 1).name == "Rotar páginas")
    }
}

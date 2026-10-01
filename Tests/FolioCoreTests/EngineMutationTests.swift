import Testing
import Foundation
@testable import FolioCore

@MainActor
@Suite("Engine · mutation")
struct EngineMutationTests {

    private func engine(pages: Int) throws -> PDFKitEngine {
        try PDFKitEngine(data: PDFFactory.makeDocument(pageCount: pages), password: nil)
    }

    // MARK: reorder

    @Test("Reordering applies the permutation")
    func reorder() throws {
        let engine = try engine(pages: 4)
        try engine.reorderPages(to: [3, 0, 1, 2])
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [603, 600, 601, 602])
    }

    @Test("Reordering rejects anything that is not a permutation")
    func reorderRejectsNonPermutation() throws {
        let engine = try engine(pages: 3)
        #expect(throws: EngineError.invalidPermutation) { try engine.reorderPages(to: [0, 1]) }
        #expect(throws: EngineError.invalidPermutation) { try engine.reorderPages(to: [0, 1, 1]) }
        #expect(throws: EngineError.invalidPermutation) { try engine.reorderPages(to: [0, 1, 9]) }
    }

    @Test("Reordering preserves rotation")
    func reorderPreservesRotation() throws {
        let engine = try engine(pages: 3)
        try engine.rotatePages(IndexSet(integer: 0), quarterTurns: 1)
        try engine.reorderPages(to: [2, 1, 0])
        #expect(PDFFactory.pageRotations(of: try engine.serialize()) == [0, 0, 90])
    }

    // MARK: rotate

    @Test("Rotating turns only the selected pages")
    func rotate() throws {
        let engine = try engine(pages: 3)
        try engine.rotatePages(IndexSet([0, 2]), quarterTurns: 1)
        #expect(PDFFactory.pageRotations(of: try engine.serialize()) == [90, 0, 90])
    }

    @Test("Rotation wraps around instead of growing without bound")
    func rotateWraps() throws {
        let engine = try engine(pages: 1)
        try engine.rotatePages(IndexSet(integer: 0), quarterTurns: 5)
        #expect(engine.rotation(ofPage: 0) == 90)
    }

    @Test("Negative rotation turns the other way")
    func rotateNegative() throws {
        let engine = try engine(pages: 1)
        try engine.rotatePages(IndexSet(integer: 0), quarterTurns: -1)
        #expect(engine.rotation(ofPage: 0) == 270)
    }

    @Test("Rotating an out-of-range page is refused")
    func rotateOutOfRange() throws {
        let engine = try engine(pages: 2)
        #expect(throws: EngineError.indexOutOfRange) {
            try engine.rotatePages(IndexSet(integer: 7), quarterTurns: 1)
        }
    }

    // MARK: remove

    @Test("Removing takes out the selected pages and returns them in order")
    func remove() throws {
        let engine = try engine(pages: 4)
        let removed = try engine.removePages(IndexSet([0, 2]))
        #expect(removed.count == 2)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [601, 603])
        #expect(PDFFactory.pageWidths(of: removed[0].data) == [600])
        #expect(PDFFactory.pageWidths(of: removed[1].data) == [602])
    }

    @Test("Removing every page is refused: a PDF needs at least one")
    func removeAllRefused() throws {
        let engine = try engine(pages: 2)
        #expect(throws: EngineError.emptyDocument) {
            _ = try engine.removePages(IndexSet([0, 1]))
        }
        #expect(engine.pageCount == 2)
    }

    @Test("A removed page keeps its rotation")
    func removeKeepsRotation() throws {
        let engine = try engine(pages: 2)
        try engine.rotatePages(IndexSet(integer: 1), quarterTurns: 1)
        let removed = try engine.removePages(IndexSet(integer: 1))
        #expect(PDFFactory.pageRotations(of: removed[0].data) == [90])
    }

    // MARK: insert

    @Test("Inserting places pages at the requested indices")
    func insert() throws {
        let engine = try engine(pages: 2)
        let removed = try engine.removePages(IndexSet(integer: 0))
        try engine.insertPages([PagePlacement(index: 1, snapshot: removed[0])])
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [601, 600])
    }

    @Test("Scattered placements land where they were taken from")
    func insertScattered() throws {
        let engine = try engine(pages: 4)
        let removed = try engine.removePages(IndexSet([0, 2]))
        try engine.insertPages([
            PagePlacement(index: 0, snapshot: removed[0]),
            PagePlacement(index: 2, snapshot: removed[1]),
        ])
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [600, 601, 602, 603])
    }

    @Test("Inserting past the end is refused")
    func insertOutOfRange() throws {
        let engine = try engine(pages: 2)
        let removed = try engine.removePages(IndexSet(integer: 0))
        #expect(throws: EngineError.indexOutOfRange) {
            try engine.insertPages([PagePlacement(index: 9, snapshot: removed[0])])
        }
    }
}

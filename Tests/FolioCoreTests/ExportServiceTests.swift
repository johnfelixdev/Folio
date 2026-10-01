import Testing
import Foundation
@testable import FolioCore

@MainActor
@Suite("ExportService")
struct ExportServiceTests {

    private func data(pages: Int) -> Data { PDFFactory.makeDocument(pageCount: pages) }

    @Test("Extracting produces a document with only the chosen pages, in order")
    func extract() throws {
        let out = try ExportService.extract(pages: IndexSet([0, 2]), from: data(pages: 4))
        #expect(PDFFactory.pageWidths(of: out) == [600, 602])
    }

    @Test("Extracting does not modify the source")
    func extractLeavesSourceAlone() throws {
        let source = data(pages: 3)
        _ = try ExportService.extract(pages: IndexSet([1]), from: source)
        #expect(PDFFactory.pageWidths(of: source) == [600, 601, 602])
    }

    @Test("Extracting nothing is refused")
    func extractEmpty() {
        #expect(throws: EngineError.emptyDocument) {
            _ = try ExportService.extract(pages: IndexSet(), from: PDFFactory.makeDocument(pageCount: 2))
        }
    }

    @Test("Extracting an out-of-range page is refused")
    func extractOutOfRange() {
        #expect(throws: EngineError.indexOutOfRange) {
            _ = try ExportService.extract(pages: IndexSet([9]), from: PDFFactory.makeDocument(pageCount: 2))
        }
    }

    @Test("Splitting cuts at the given boundaries")
    func split() throws {
        let parts = try ExportService.split(data(pages: 5), at: [2, 4])
        #expect(parts.count == 3)
        #expect(PDFFactory.pageWidths(of: parts[0]) == [600, 601])
        #expect(PDFFactory.pageWidths(of: parts[1]) == [602, 603])
        #expect(PDFFactory.pageWidths(of: parts[2]) == [604])
    }

    @Test("Splitting with no boundaries returns the whole document")
    func splitNoBoundaries() throws {
        let parts = try ExportService.split(data(pages: 3), at: [])
        #expect(parts.count == 1)
        #expect(PDFFactory.pageWidths(of: parts[0]) == [600, 601, 602])
    }

    @Test("Duplicate and unsorted boundaries are tolerated")
    func splitMessyBoundaries() throws {
        let parts = try ExportService.split(data(pages: 4), at: [3, 1, 1])
        #expect(parts.count == 3)
        #expect(PDFFactory.pageWidths(of: parts[0]) == [600])
        #expect(PDFFactory.pageWidths(of: parts[1]) == [601, 602])
        #expect(PDFFactory.pageWidths(of: parts[2]) == [603])
    }

    /// The out-of-range tests use wildly out-of-range values, so an accidental
    /// `<=` at the edge ships silently. These probe the adjacent boundary, which
    /// is the only value that distinguishes a correct guard from a loose one.
    @Test("A boundary of zero is refused")
    func splitRejectsZeroBoundary() {
        #expect(throws: EngineError.indexOutOfRange) {
            _ = try ExportService.split(PDFFactory.makeDocument(pageCount: 3), at: [0])
        }
    }

    @Test("A boundary at the page count is refused")
    func splitRejectsBoundaryAtEnd() {
        #expect(throws: EngineError.indexOutOfRange) {
            _ = try ExportService.split(PDFFactory.makeDocument(pageCount: 3), at: [3])
        }
    }

    @Test("Extracting the index just past the last page is refused")
    func extractRejectsIndexAtEnd() {
        #expect(throws: EngineError.indexOutOfRange) {
            _ = try ExportService.extract(
                pages: IndexSet([2]), from: PDFFactory.makeDocument(pageCount: 2))
        }
    }

    /// The reason these are a service and not commands is that they never mutate
    /// anything — asserted for `extract` above, and here for `split`.
    @Test("Splitting does not modify the source")
    func splitLeavesSourceAlone() throws {
        let source = data(pages: 4)
        _ = try ExportService.split(source, at: [2])
        #expect(PDFFactory.pageWidths(of: source) == [600, 601, 602, 603])
    }

    @Test("Extracted pages keep their rotation")
    func extractPreservesRotation() throws {
        let engine = try PDFKitEngine(data: data(pages: 3), password: nil)
        try engine.rotatePages(IndexSet(integer: 1), quarterTurns: 1)
        let out = try ExportService.extract(pages: IndexSet([1, 2]), from: try engine.serialize())
        #expect(PDFFactory.pageWidths(of: out) == [601, 602])
        #expect(PDFFactory.pageRotations(of: out) == [90, 0])
    }

    @Test("Boundaries outside the document are refused")
    func splitOutOfRange() {
        #expect(throws: EngineError.indexOutOfRange) {
            _ = try ExportService.split(PDFFactory.makeDocument(pageCount: 3), at: [7])
        }
    }
}

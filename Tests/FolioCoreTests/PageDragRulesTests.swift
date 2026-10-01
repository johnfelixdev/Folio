import Testing
import Foundation
@testable import FolioCore

@MainActor
@Suite("Page drag rules")
struct PageDragRulesTests {

    @Test("A drag that starts on a selected page carries the whole selection")
    func carriesSelection() {
        #expect(PageDragRules.pages(startingAt: 2, selection: [1, 2]) == [1, 2])
    }

    @Test("A drag that starts outside the selection carries only that page")
    func ignoresUnrelatedSelection() {
        #expect(PageDragRules.pages(startingAt: 3, selection: [1, 2]) == [3])
    }

    @Test("With nothing selected, a drag carries the page it started on")
    func emptySelection() {
        #expect(PageDragRules.pages(startingAt: 0, selection: []) == [0])
    }

    @Test("Two open documents never share an identity")
    func documentsAreDistinct() {
        #expect(FolioDocument.blank().id != FolioDocument.blank().id)
    }

    @Test("A drop only moves pages that came from the same document")
    func rejectsForeignDrags() {
        let here = FolioDocument.blank()
        let elsewhere = FolioDocument.blank()
        #expect(PageDragRules.accepts(dragFrom: here.id, into: here.id))
        #expect(!PageDragRules.accepts(dragFrom: elsewhere.id, into: here.id))
    }
}

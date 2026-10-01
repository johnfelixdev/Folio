import Testing
import Foundation
@testable import FolioCore

@Suite("PDFFactory")
struct PDFFactoryTests {

    @Test("Each generated page carries a unique width that encodes its index")
    func widthsEncodeOrder() {
        let data = PDFFactory.makeDocument(pageCount: 4)
        #expect(PDFFactory.pageWidths(of: data) == [600, 601, 602, 603])
    }

    @Test("A generated document reports no rotation")
    func rotationsStartAtZero() {
        let data = PDFFactory.makeDocument(pageCount: 3)
        #expect(PDFFactory.pageRotations(of: data) == [0, 0, 0])
    }

    @Test("A single-page document is valid")
    func singlePage() {
        let data = PDFFactory.makeDocument(pageCount: 1)
        #expect(PDFFactory.pageWidths(of: data) == [600])
    }
}

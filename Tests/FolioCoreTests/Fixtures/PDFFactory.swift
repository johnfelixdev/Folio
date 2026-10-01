import AppKit
import CoreGraphics
import CoreText
import Foundation

/// Builds deterministic PDFs for tests and reads them back with CoreGraphics.
///
/// Page `i` is `600 + i` points wide. Order assertions therefore reduce to
/// comparing integers, with no text extraction and no PDFKit in the test target.
enum PDFFactory {

    static let baseWidth = 600
    static let pageHeight: CGFloat = 792

    /// Creates a PDF whose page widths are `600, 601, 602, ...`.
    ///
    /// `encryption` goes straight into the PDF context's auxiliary info, which
    /// is how encrypted fixtures get built without PDFKit. See
    /// `EncryptedPDFFactory`.
    ///
    /// `outline` becomes the document's bookmarks: one top-level entry per
    /// pair, pointing at a zero-based page index.
    static func makeDocument(
        pageCount: Int,
        encryption: [String: Any]? = nil,
        outline: [(title: String, page: Int)] = []
    ) -> Data {
        precondition(pageCount > 0, "A PDF needs at least one page")
        let buffer = NSMutableData()
        guard let consumer = CGDataConsumer(data: buffer) else {
            fatalError("CGDataConsumer could not wrap the output buffer")
        }
        var fullBox = CGRect(x: 0, y: 0, width: CGFloat(baseWidth), height: pageHeight)
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &fullBox,
            encryption as CFDictionary?
        ) else {
            fatalError("CGContext could not open a PDF context")
        }

        for index in 0..<pageCount {
            var box = CGRect(
                x: 0, y: 0,
                width: CGFloat(baseWidth + index),
                height: pageHeight
            )
            let pageInfo = [kCGPDFContextMediaBox as String: CFDataCreate(
                nil,
                withUnsafeBytes(of: &box) { Array($0) },
                MemoryLayout<CGRect>.size
            )!] as CFDictionary
            context.beginPDFPage(pageInfo)
            draw(marker: index, in: context, width: CGFloat(baseWidth + index))
            context.endPDFPage()
        }
        if !outline.isEmpty {
            let children = outline.map { entry in
                [
                    kCGPDFOutlineTitle as String: entry.title,
                    kCGPDFOutlineDestination as String: entry.page + 1,
                ] as [String: Any]
            }
            CGPDFContextSetOutline(context, [kCGPDFOutlineChildren as String: children] as CFDictionary)
        }
        context.closePDF()
        return buffer as Data
    }

    /// Reads back the media-box width of every page, rounded to an integer.
    static func pageWidths(of data: Data) -> [Int] {
        guard let document = openDocument(data) else { return [] }
        return (1...document.numberOfPages).compactMap { number in
            document.page(at: number).map { Int($0.getBoxRect(.mediaBox).width.rounded()) }
        }
    }

    /// Reads back the rotation of every page, normalised to 0/90/180/270.
    static func pageRotations(of data: Data) -> [Int] {
        guard let document = openDocument(data) else { return [] }
        return (1...document.numberOfPages).compactMap { number in
            document.page(at: number).map { (Int($0.rotationAngle) % 360 + 360) % 360 }
        }
    }

    static func pageCount(of data: Data) -> Int {
        openDocument(data)?.numberOfPages ?? 0
    }

    /// Reads a string from the document's Info dictionary, e.g. "Title".
    ///
    /// The document is held in a local on purpose: `info` is a borrowed
    /// pointer into it, and reading it after the document is released returns
    /// garbage or nothing.
    static func infoString(_ key: String, of data: Data) -> String? {
        guard let document = openDocument(data) else { return nil }
        return withExtendedLifetime(document) {
            guard let info = document.info else { return nil }
            var value: CGPDFStringRef?
            guard CGPDFDictionaryGetString(info, key, &value), let value else { return nil }
            return CGPDFStringCopyTextString(value) as String?
        }
    }

    /// Reads back the top-level bookmarks as (title, zero-based page index).
    static func outline(of data: Data) -> [(title: String, page: Int)] {
        guard let root = openDocument(data)?.outline as? [String: Any],
              let children = root[kCGPDFOutlineChildren as String] as? [[String: Any]]
        else { return [] }
        return children.compactMap { child in
            guard let title = child[kCGPDFOutlineTitle as String] as? String,
                  let page = child[kCGPDFOutlineDestination as String] as? Int
            else { return nil }
            return (title, page - 1)
        }
    }

    private static func openDocument(_ data: Data) -> CGPDFDocument? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              document.numberOfPages > 0
        else { return nil }
        return document
    }

    private static func draw(marker index: Int, in context: CGContext, width: CGFloat) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 96, nil)
        let attributed = NSAttributedString(
            string: "P\(index)",
            attributes: [
                .font: font,
                .foregroundColor: CGColor(gray: 0.1, alpha: 1),
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: width / 2 - 60, y: pageHeight / 2)
        CTLineDraw(line, context)
    }
}

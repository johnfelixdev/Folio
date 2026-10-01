import CoreGraphics
import Foundation
import PDFKit

/// The PDFKit-backed engine. Together with `Views/PageCanvas.swift` this is one
/// of exactly two files in the project allowed to import PDFKit.
@MainActor
public final class PDFKitEngine: PDFEngine {

    private var document: PDFDocument

    /// Loads a document, optionally supplying a user password for a locked file.
    public init(data: Data, password: String?) throws {
        guard let document = PDFDocument(data: data) else {
            throw EngineError.unreadable
        }
        if document.isLocked, let password {
            _ = document.unlock(withPassword: password)
        }
        guard !document.isLocked else { throw EngineError.stillLocked }
        guard document.pageCount > 0 else { throw EngineError.unreadable }
        self.document = document
    }

    // MARK: Lifecycle

    public func serialize() throws -> Data {
        guard let data = document.dataRepresentation() else {
            throw EngineError.pageUnavailable
        }
        return data
    }

    // MARK: Inspection

    public var pageCount: Int { document.pageCount }

    public func rotation(ofPage index: Int) -> Int {
        guard let page = document.page(at: index) else { return 0 }
        return normalise(page.rotation)
    }

    public func render(page index: Int, fitting size: CGSize) throws -> CGImage {
        guard let page = document.page(at: index) else { throw EngineError.indexOutOfRange }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { throw EngineError.pageUnavailable }

        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let pixelWidth = max(Int((bounds.width * scale).rounded()), 1)
        let pixelHeight = max(Int((bounds.height * scale).rounded()), 1)

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw EngineError.pageUnavailable }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .cropBox, to: context)

        guard let image = context.makeImage() else { throw EngineError.pageUnavailable }
        return image
    }

    // MARK: Protection

    public var protection: ProtectionState {
        if document.isLocked { return .locked }
        guard document.isEncrypted else { return .open }
        let permissions = Permissions(
            printing: document.allowsPrinting,
            copying: document.allowsCopying,
            documentChanges: document.allowsDocumentChanges,
            assembly: document.allowsDocumentAssembly
        )
        return permissions.hasRestrictions ? .restricted(permissions) : .open
    }

    public func unlock(password: String) -> Bool {
        document.unlock(withPassword: password)
    }

    public func stripProtection() throws -> Data {
        let previous = try serialize()

        // PDFKit keeps a document's encryption dictionary when it rewrites it,
        // so there is no write option that drops it. Copying the pages into a
        // brand-new document is what actually produces an unencrypted file.
        let rebuilt = PDFDocument()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index)?.copy() as? PDFPage else {
                throw EngineError.pageUnavailable
            }
            rebuilt.insert(page, at: rebuilt.pageCount)
        }
        guard rebuilt.pageCount == document.pageCount else { throw EngineError.pageUnavailable }

        // Copying pages leaves the rest of the document behind. Title, author
        // and bookmarks are the user's, not part of the restriction, so they
        // travel too; bookmarks are re-pointed at the copied pages.
        rebuilt.documentAttributes = document.documentAttributes
        if let outline = document.outlineRoot {
            rebuilt.outlineRoot = copyOutline(outline, into: rebuilt)
        }

        document = rebuilt
        return previous
    }

    /// Rebuilds a bookmark tree so every destination points into `target`.
    ///
    /// A destination holds a page object, and the pages of `target` are copies,
    /// so each one is looked up again by index. Actions that are not page jumps
    /// (a link to a web page, say) are carried over unchanged.
    private func copyOutline(_ source: PDFOutline, into target: PDFDocument) -> PDFOutline {
        let copy = PDFOutline()
        copy.label = source.label
        copy.isOpen = source.isOpen

        let jump = source.destination ?? (source.action as? PDFActionGoTo)?.destination
        if let jump, let page = jump.page,
           let mapped = target.page(at: document.index(for: page)) {
            let destination = PDFDestination(page: mapped, at: jump.point)
            destination.zoom = jump.zoom
            copy.destination = destination
        } else if let action = source.action, !(action is PDFActionGoTo) {
            copy.action = action
        }

        for index in 0..<source.numberOfChildren {
            guard let child = source.child(at: index) else { continue }
            copy.insertChild(copyOutline(child, into: target), at: copy.numberOfChildren)
        }
        return copy
    }

    public func restore(from data: Data) throws {
        guard let restored = PDFDocument(data: data), restored.pageCount > 0 else {
            throw EngineError.unreadable
        }
        guard !restored.isLocked else { throw EngineError.stillLocked }
        document = restored
    }

    // MARK: Helpers

    private func normalise(_ degrees: Int) -> Int {
        ((degrees % 360) + 360) % 360
    }

    // MARK: Mutation

    public func reorderPages(to order: [Int]) throws {
        guard order.count == document.pageCount,
              Set(order) == Set(0..<document.pageCount)
        else { throw EngineError.invalidPermutation }

        // Take strong references before touching the document: removing a page
        // from a PDFDocument can drop the last reference to it.
        let pages = try (0..<document.pageCount).map { index -> PDFPage in
            guard let page = document.page(at: index) else { throw EngineError.pageUnavailable }
            return page
        }
        let rearranged = order.map { pages[$0] }

        for index in stride(from: document.pageCount - 1, through: 0, by: -1) {
            document.removePage(at: index)
        }
        for (index, page) in rearranged.enumerated() {
            document.insert(page, at: index)
        }
    }

    public func rotatePages(_ indices: IndexSet, quarterTurns: Int) throws {
        guard indices.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
            throw EngineError.indexOutOfRange
        }
        for index in indices {
            guard let page = document.page(at: index) else { throw EngineError.pageUnavailable }
            page.rotation = normalise(page.rotation + quarterTurns * 90)
        }
    }

    public func removePages(_ indices: IndexSet) throws -> [PageSnapshot] {
        guard indices.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
            throw EngineError.indexOutOfRange
        }
        guard !indices.isEmpty else { return [] }
        guard indices.count < document.pageCount else { throw EngineError.emptyDocument }

        let snapshots = try indices.sorted().map { index -> PageSnapshot in
            guard let page = document.page(at: index),
                  let data = page.dataRepresentation
            else { throw EngineError.pageUnavailable }
            return PageSnapshot(data: data)
        }
        for index in indices.sorted(by: >) {
            document.removePage(at: index)
        }
        return snapshots
    }

    /// Snapshots pages without removing them. Used when merging a whole
    /// document, where `removePages` would refuse to empty the source.
    func removePagesForCopying(_ indices: IndexSet) throws -> [PageSnapshot] {
        guard indices.allSatisfy({ $0 >= 0 && $0 < document.pageCount }) else {
            throw EngineError.indexOutOfRange
        }
        return try indices.sorted().map { index in
            guard let page = document.page(at: index),
                  let data = page.dataRepresentation
            else { throw EngineError.pageUnavailable }
            return PageSnapshot(data: data)
        }
    }

    /// All or nothing: every placement is checked and every page parsed
    /// before the first one goes in. A failure halfway would otherwise leave
    /// the document changed with no undo registered for it, and the copy kept
    /// for saving would no longer match what is on screen.
    public func insertPages(_ placements: [PagePlacement]) throws {
        var runningCount = document.pageCount
        var prepared: [(index: Int, page: PDFPage)] = []
        for placement in placements.sorted(by: { $0.index < $1.index }) {
            guard placement.index >= 0, placement.index <= runningCount else {
                throw EngineError.indexOutOfRange
            }
            guard let carrier = PDFDocument(data: placement.snapshot.data),
                  let page = carrier.page(at: 0)
            else { throw EngineError.unreadable }
            prepared.append((placement.index, page))
            runningCount += 1
        }
        for (index, page) in prepared {
            document.insert(page, at: index)
        }
    }
}

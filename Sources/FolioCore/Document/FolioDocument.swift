import CoreGraphics
import Combine
import Foundation

/// The editable state of one open PDF: the engine, the undo stack and the
/// page identities, kept in step with each other.
@MainActor
public final class FolioDocument: ObservableObject {

    private let engine: any PDFEngine
    private let identity: PageIdentity

    /// Tells one open document from another, e.g. to refuse a page drag that
    /// started in a different window. Page indices alone mean nothing outside
    /// the document they were taken from.
    public nonisolated let id = UUID()

    /// Injected by the view layer so undo lands in the window's own stack.
    public weak var undoManager: UndoManager?

    /// Bumped on every change so SwiftUI redraws.
    @Published public private(set) var revision: Int = 0
    @Published public private(set) var isModified: Bool = false

    /// Page identities whose *appearance* changed in the last command, and whose
    /// thumbnails are therefore stale.
    ///
    /// Almost always empty: moving, deleting and inserting pages rearrange them
    /// without changing how any of them looks. Only rotation makes a cached
    /// thumbnail wrong. Publishing precisely this is what lets the cache survive
    /// a reorder, which is the whole reason it is keyed by identity.
    @Published public private(set) var invalidatedPageIDs: Set<UUID> = []

    public init(data: Data, password: String?) throws {
        let engine = try PDFKitEngine(data: data, password: password)
        self.engine = engine
        self.identity = PageIdentity(pageCount: engine.pageCount)
    }

    /// A one-page blank document, for File ▸ New.
    ///
    /// Built with CoreGraphics rather than by asking the engine for an empty
    /// document, because a PDF with zero pages is not a valid PDF and the whole
    /// codebase refuses to produce one.
    public static func blank() -> FolioDocument {
        let buffer = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: buffer),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { fatalError("Could not open a PDF context for a blank page") }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()

        guard let document = try? FolioDocument(data: buffer as Data, password: nil) else {
            fatalError("A blank page we generated ourselves failed to load")
        }
        return document
    }

    // MARK: Inspection

    public var pageCount: Int { engine.pageCount }
    public var protection: ProtectionState { engine.protection }

    public func pageID(at index: Int) -> UUID {
        identity.id(forPageAt: index)
    }

    public func rotation(ofPage index: Int) -> Int {
        engine.rotation(ofPage: index)
    }

    public func render(page index: Int, fitting size: CGSize) throws -> CGImage {
        try engine.render(page: index, fitting: size)
    }

    /// Current bytes, for the view layer to hand to the platform viewer.
    ///
    /// The canvas needs a document object of its own; it does not share the
    /// engine's, which stays confined to the main actor behind `PDFEngine`.
    public func currentData() throws -> Data {
        try engine.serialize()
    }

    // MARK: Mutation

    /// Applies a command, keeps page identities in step, and registers the undo.
    ///
    /// If the command throws, nothing is registered and nothing is marked dirty:
    /// a refused operation leaves the document exactly as it was.
    public func perform(_ command: any PageCommand) throws {
        // Identities of rotated pages must be read *before* the reorder bookkeeping,
        // while indices still mean what the command meant by them.
        let staleIDs = appearanceChanges(for: command)

        let undoCommand = try command.apply(to: engine)
        syncIdentity(for: command)
        invalidatedPageIDs = staleIDs
        isModified = true
        revision += 1

        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                try? document.perform(undoCommand)
            }
        }
        undoManager?.setActionName(command.name)
    }

    /// Which pages will *look* different afterwards, as opposed to merely moving.
    ///
    /// Rotation is the only phase-1 command that changes a page's appearance.
    /// Everything else rearranges pages that still look exactly as they did, so
    /// their cached thumbnails stay valid.
    private func appearanceChanges(for command: any PageCommand) -> Set<UUID> {
        guard let rotate = command as? RotatePages else { return [] }
        return Set(rotate.indices.map { identity.id(forPageAt: $0) })
    }

    /// Keeps `PageIdentity` aligned with what the command did to the engine.
    private func syncIdentity(for command: any PageCommand) {
        switch command {
        case let reorder as ReorderPages:
            identity.reorder(to: reorder.order)
        case let move as MovePages:
            if let order = try? move.permutation(pageCount: identity.count) {
                identity.reorder(to: order)
            }
        case let delete as DeletePages:
            identity.remove(delete.indices)
        case let insert as InsertPages:
            identity.insert(at: insert.placements.map(\.index))
        default:
            break  // RotatePages and the restriction commands do not move pages.
        }
    }

    // MARK: Saving

    public func serialize() throws -> Data {
        try engine.serialize()
    }

    /// Called by the document layer once the system has written the file.
    public func markSaved() {
        isModified = false
    }
}

import CoreGraphics
import Foundation

public enum EngineError: Error, Equatable {
    /// A page index fell outside `0..<pageCount`.
    case indexOutOfRange
    /// The operation would leave the document with zero pages, which is not a valid PDF.
    case emptyDocument
    /// The bytes could not be parsed as a PDF.
    case unreadable
    /// The document needs a user password that was not supplied or was wrong.
    case stillLocked
    /// A reorder was given something that is not a permutation of `0..<pageCount`.
    case invalidPermutation
    /// A page could not be rendered or serialised.
    case pageUnavailable
}

/// Everything the rest of the app is allowed to know about a PDF.
///
/// No layer above this protocol mentions PDFKit. When phase 3 needs an engine
/// that can rewrite existing text, a second conformance is added beside
/// `PDFKitEngine` and the commands, document and services are untouched.
@MainActor
public protocol PDFEngine: AnyObject {

    // MARK: Lifecycle

    /// Writes the current state back out as PDF bytes.
    func serialize() throws -> Data

    // MARK: Inspection

    var pageCount: Int { get }
    /// Rotation of a page in degrees, normalised to 0/90/180/270.
    func rotation(ofPage index: Int) -> Int
    /// Renders a page scaled to fit `size`, preserving aspect ratio.
    func render(page index: Int, fitting size: CGSize) throws -> CGImage

    // MARK: Mutation

    /// Rearranges pages so that the new page at position `i` is the old page at `order[i]`.
    /// `order` must be a permutation of `0..<pageCount`.
    func reorderPages(to order: [Int]) throws
    func rotatePages(_ indices: IndexSet, quarterTurns: Int) throws
    /// Removes pages and returns them, in ascending index order, so the caller can put them back.
    func removePages(_ indices: IndexSet) throws -> [PageSnapshot]
    /// Inserts placements in ascending index order.
    func insertPages(_ placements: [PagePlacement]) throws

    // MARK: Protection

    var protection: ProtectionState { get }
    /// Supplies a user password for a `.locked` document. Returns whether it worked.
    func unlock(password: String) -> Bool

    /// Rebuilds the document without encryption, and returns the bytes it replaced.
    ///
    /// Removing encryption cannot be undone by computing anything — the owner
    /// password is not ours to have — so the caller keeps the returned bytes and
    /// hands them to `restore(from:)` to undo.
    func stripProtection() throws -> Data

    /// Returns the document to a state captured earlier by `stripProtection`.
    func restore(from data: Data) throws
}

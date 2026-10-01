import Combine
import FolioCore
import SwiftUI
import UniformTypeIdentifiers

/// Bridges `FolioDocument` to the system's document machinery.
///
/// Being a `ReferenceFileDocument` is what buys atomic writes, autosave,
/// versions and the window's own undo stack, none of which we want to rewrite.
///
/// `ReferenceFileDocument` is declared `nonisolated` in the SDK. Marking this
/// whole class `@MainActor` — the natural choice, since every method here
/// touches `FolioDocument` (and `PageIdentity` beneath it), itself
/// `@MainActor` — is a hard compile error under Swift 6: the conformance
/// would cross main-actor isolation (`error: conformance of
/// 'FolioFileDocument' to protocol 'ReferenceFileDocument' crosses into main
/// actor-isolated code and can cause data races [#ConformanceIsolation]`).
/// This class is therefore deliberately *not* `@MainActor`; it is
/// `@unchecked Sendable` and hops to the main actor explicitly, via
/// `onMain`, at every point where it touches `model`. Whether AppKit
/// actually calls these members off the main thread was not verified in
/// this environment — the hops are defensive, driven by the compiler error
/// above, not by an observed runtime crash.
final class FolioFileDocument: ReferenceFileDocument, @unchecked Sendable {

    typealias Snapshot = Data

    static var readableContentTypes: [UTType] { [.pdf] }

    let model: FolioDocument

    /// The document's current bytes, ready for saving.
    ///
    /// Saving cannot ask the model for them. The system calls `snapshot` on a
    /// background queue *while the main thread waits for the save to finish*,
    /// so hopping to the main thread there deadlocks — measured on macOS 27:
    /// `snapshot` → `DispatchQueue.main.sync` → `__ulock_wait`, with the main
    /// thread parked in `NSDocumentController`. Instead the bytes are refreshed
    /// on the main thread after every change, and `snapshot` only reads them.
    private let lock = NSLock()
    private var latest: Result<Data, Error>
    private var revisionWatch: AnyCancellable?

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        model = try Self.onMain {
            try FolioDocument(data: data, password: nil)
        }
        latest = .success(data)
        watchRevisions()
    }

    /// Backs File ▸ New with a blank page.
    ///
    /// `DocumentGroup(newDocument:)` takes a non-throwing closure, and a blank
    /// page built from bytes we control cannot fail for any reason the user
    /// could act on. If it does, the app is broken, not the document.
    init() {
        let blank = Self.onMain { FolioDocument.blank() }
        model = blank
        latest = Result { try Self.onMain { try blank.serialize() } }
        watchRevisions()
    }

    func snapshot(contentType: UTType) throws -> Data {
        try lock.withLock { latest }.get()
    }

    /// Only wraps the bytes: the system writes them afterwards, and may fail.
    /// Whether there are unsaved changes is therefore left to the system,
    /// which shows it in the window's title bar.
    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }

    /// Re-serialises the model each time it changes.
    ///
    /// `@Published` delivers synchronously on the thread that changed it, the
    /// main thread, after the command has already been applied to the engine;
    /// so the bytes are current before any save can start. A failure is kept
    /// rather than swallowed, so the next save fails instead of quietly
    /// writing the previous version.
    private func watchRevisions() {
        Self.onMain {
            self.revisionWatch = self.model.$revision.dropFirst().sink { [weak self] _ in
                guard let self else { return }
                let fresh = MainActor.assumeIsolated { Result { try self.model.serialize() } }
                self.lock.withLock { self.latest = fresh }
            }
        }
    }

    /// Runs `body` on the main thread and asserts main-actor isolation there.
    ///
    /// `MainActor.assumeIsolated` only ever *checks* isolation, it never hops;
    /// calling it from a background queue would crash exactly like the bug
    /// this method exists to avoid. Dispatching to `DispatchQueue.main` first
    /// makes the assumption true by the time it is checked. The `isMainThread`
    /// guard matters too: `DispatchQueue.main.sync` from the main thread
    /// itself deadlocks, and nothing here guarantees we are always called from
    /// the background.
    ///
    /// `assumeIsolated`'s closure result must be `Sendable`. `Data` and `Void`
    /// are trivially so, and `FolioDocument` qualifies too: it is a
    /// `@MainActor` class, and `@MainActor` classes are implicitly `Sendable`.
    /// One generic helper therefore covers every call site here.
    private static func onMain<T: Sendable>(_ body: @MainActor () throws -> T) rethrows -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated(body)
        }
        return try DispatchQueue.main.sync {
            try MainActor.assumeIsolated(body)
        }
    }
}

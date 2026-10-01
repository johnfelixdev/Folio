import Testing
import Foundation
@testable import FolioCore

@MainActor
@Suite("Engine · protection")
struct EngineProtectionTests {

    @Test("A restricted document opens without a password and reports its restrictions")
    func restrictedOpensAndReports() throws {
        let engine = try PDFKitEngine(
            data: EncryptedPDFFactory.makeRestricted(pageCount: 2), password: nil)
        guard case .restricted(let permissions) = engine.protection else {
            Issue.record("Expected .restricted, got \(engine.protection)")
            return
        }
        #expect(permissions.printing == false)
        #expect(permissions.copying == false)
        #expect(permissions.hasRestrictions)
        #expect(engine.pageCount == 2)
    }

    @Test("A locked document refuses to load without its password")
    func lockedRefusesWithoutPassword() {
        #expect(throws: EngineError.stillLocked) {
            _ = try PDFKitEngine(data: EncryptedPDFFactory.makeLocked(pageCount: 1), password: nil)
        }
    }

    @Test("A locked document loads with the right password")
    func lockedLoadsWithPassword() throws {
        let data = EncryptedPDFFactory.makeLocked(pageCount: 3, userPassword: "open-me")
        #expect(try PDFKitEngine(data: data, password: "open-me").pageCount == 3)
    }

    @Test("A wrong password does not open a locked document")
    func wrongPasswordFails() {
        let data = EncryptedPDFFactory.makeLocked(pageCount: 1, userPassword: "open-me")
        #expect(throws: EngineError.stillLocked) {
            _ = try PDFKitEngine(data: data, password: "not-it")
        }
    }

    /// CHARACTERISATION TEST — records what PDFKit actually does.
    ///
    /// This is the observed behaviour on macOS 26.5, verified rather than
    /// assumed: saving a restricted document **keeps** its restrictions. The
    /// whole permissions design rests on it, so if this ever fails, the design
    /// changes — do not "fix" the test.
    @Test("Saving a restricted document keeps its restrictions")
    func savingPreservesRestrictions() throws {
        let engine = try PDFKitEngine(
            data: EncryptedPDFFactory.makeRestricted(pageCount: 1), password: nil)
        let reopened = try PDFKitEngine(data: try engine.serialize(), password: nil)
        guard case .restricted = reopened.protection else {
            Issue.record("PDFKit dropped the encryption on save: got \(reopened.protection)")
            return
        }
    }

    @Test("Stripping protection produces a genuinely unrestricted document")
    func stripProduces() throws {
        let engine = try PDFKitEngine(
            data: EncryptedPDFFactory.makeRestricted(pageCount: 3), password: nil)
        _ = try engine.stripProtection()
        #expect(engine.protection == .open)

        let reopened = try PDFKitEngine(data: try engine.serialize(), password: nil)
        #expect(reopened.protection == .open, "The saved file must be unrestricted too")
    }

    @Test("Stripping protection preserves page order and rotation")
    func stripPreservesContent() throws {
        let engine = try PDFKitEngine(
            data: EncryptedPDFFactory.makeRestricted(pageCount: 3), password: nil)
        try engine.rotatePages(IndexSet(integer: 1), quarterTurns: 1)
        _ = try engine.stripProtection()

        let written = try engine.serialize()
        #expect(PDFFactory.pageWidths(of: written) == [600, 601, 602])
        #expect(PDFFactory.pageRotations(of: written) == [0, 90, 0])
    }

    @Test("Restoring puts the restrictions back")
    func restoreUndoesStrip() throws {
        let engine = try PDFKitEngine(
            data: EncryptedPDFFactory.makeRestricted(pageCount: 2), password: nil)
        let previous = try engine.stripProtection()
        #expect(engine.protection == .open)

        try engine.restore(from: previous)
        guard case .restricted = engine.protection else {
            Issue.record("Restoring did not bring the restrictions back")
            return
        }
        #expect(engine.pageCount == 2)
    }

    @Test("Stripping an already-open document is harmless")
    func stripOnOpenDocument() throws {
        let engine = try PDFKitEngine(data: PDFFactory.makeDocument(pageCount: 2), password: nil)
        _ = try engine.stripProtection()
        #expect(engine.protection == .open)
        #expect(PDFFactory.pageWidths(of: try engine.serialize()) == [600, 601])
    }
}

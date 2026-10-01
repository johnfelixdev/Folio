import Testing
import Foundation

/// Guards the two boundary rules from the spec.
///
/// These rules are what keep the phase-3 engine swap bounded and the tests fast.
/// They erode the moment someone adds an import "just this once", so they are
/// enforced rather than documented.
@Suite("Architecture")
struct ArchitectureTests {

    /// The only files allowed to import PDFKit.
    private let pdfKitAllowlist: Set<String> = [
        "PDFKitEngine.swift",   // the engine itself
        "PageCanvas.swift",     // wraps PDFView; feeding it needs a PDFDocument
    ]

    /// This file is the scanner, not production code: its own diagnostic
    /// strings and the literals above contain the exact substrings ("import
    /// PDFKit", "PDFDocument", "PDFPage", "PDFView", ...) the checks below
    /// search for, so it must be excluded from every scan by filename rather
    /// than relying on comment-stripping or prefix tricks to hide it.
    private static let scannerFileName = "ArchitectureTests.swift"

    private var packageRoot: URL {
        // .../Tests/FolioCoreTests/ArchitectureTests.swift -> package root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftFiles(under relativePath: String) throws -> [URL] {
        let root = packageRoot.appendingPathComponent(relativePath)
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .filter { $0.lastPathComponent != Self.scannerFileName }
    }

    /// Lines whose *trimmed* form does not begin with `//`.
    ///
    /// This deliberately does not try to strip a trailing "// comment" off an
    /// otherwise-code line: doing that correctly requires a real Swift lexer,
    /// because `//` can appear inside string literals, interpolations, and
    /// URLs without starting a comment at all. A naive textual strip (finding
    /// the first `//` anywhere in the line) is exactly what let a line like
    /// `"https://example.com" + "PDFDocument"` sail through undetected — the
    /// scan thought the leaked type name was "commented out" when it was live
    /// code. Dropping only whole-line comments still clears the original
    /// false positive this test cared about (a `///` doc comment that merely
    /// *names* a PDFKit type in prose, see `PageIdentity`), while leaving
    /// every line of real code fully intact for scanning.
    private func codeLines(_ source: String) -> [Substring] {
        source.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
    }

    /// True if a non-comment line imports `module`, in any of Swift's import
    /// forms.
    ///
    /// A plain `line.hasPrefix("import PDFKit")` check misses the SE-0409
    /// access-level import forms — `internal import PDFKit`, `public import
    /// PDFKit`, `package import PDFKit` — which compile identically to a bare
    /// `import PDFKit` but don't start with the literal word "import". It
    /// also has no word boundary after the module name, so a module named
    /// e.g. `PDFKitUI` would false-positive as `PDFKit`. This regex allows
    /// optional attributes (`@testable`, ...) and an optional access-level
    /// modifier before `import`, and requires a word boundary right after the
    /// module name so a longer module name sharing the same prefix can't
    /// match.
    private func hasImport(_ module: String, in source: String) -> Bool {
        let pattern = #"^\s*(?:@\w+\s+)*(?:(?:public|internal|private|fileprivate|package)\s+)?import\s+"#
            + NSRegularExpression.escapedPattern(for: module)
            + #"\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            Issue.record("Failed to compile import-detection regex: \(pattern)")
            return false
        }
        return codeLines(source).contains { line in
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }

    @Test("PDFKit is imported in exactly the allowed files")
    func pdfKitStaysPut() throws {
        var filesScanned = 0
        var offenders: [String] = []
        for directory in ["Sources", "Tests"] {
            let files = try swiftFiles(under: directory)
            filesScanned += files.count
            for file in files {
                let source = try String(contentsOf: file, encoding: .utf8)
                guard hasImport("PDFKit", in: source) else { continue }
                let name = file.lastPathComponent
                if !pdfKitAllowlist.contains(name) {
                    offenders.append(name)
                }
            }
        }
        // A walk that silently finds nothing would make the check below pass
        // vacuously, so confirm it actually saw the source tree first.
        #expect(filesScanned > 10, "Expected many .swift files under Sources and Tests, found \(filesScanned) — the directory walk may be broken")
        #expect(
            offenders.isEmpty,
            "These files import PDFKit but are not on the allowlist: \(offenders.sorted())"
        )
    }

    @Test("FolioCore never imports SwiftUI")
    func coreStaysHeadless() throws {
        let files = try swiftFiles(under: "Sources/FolioCore")
        var offenders: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            if hasImport("SwiftUI", in: source) {
                offenders.append(file.lastPathComponent)
            }
        }
        #expect(files.count > 5, "Expected several .swift files under Sources/FolioCore, found \(files.count) — the directory walk may be broken")
        #expect(
            offenders.isEmpty,
            "FolioCore must stay free of SwiftUI, but these import it: \(offenders.sorted())"
        )
    }

    /// True if `word` appears in `code` as a whole identifier, not merely as a
    /// substring.
    ///
    /// A plain `code.contains(word)` false-positives on `CGContext`'s own
    /// `beginPDFPage`/`endPDFPage` — legitimate CoreGraphics API that has
    /// nothing to do with PDFKit's `PDFPage` type, but contains it as a
    /// substring. Swift identifier characters have no word boundary between
    /// them, so `\bPDFPage\b` does not match inside `beginPDFPage` (no
    /// boundary between "n" and "P"), while still matching a standalone
    /// `PDFPage` reference.
    private func containsWholeWord(_ word: String, in code: String) -> Bool {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            Issue.record("Failed to compile leaked-type regex: \(pattern)")
            return false
        }
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        return regex.firstMatch(in: code, options: [], range: range) != nil
    }

    @Test("No layer above the engine names PDFKit types")
    func noLeakedTypes() throws {
        let leaked = ["PDFDocument", "PDFPage", "PDFView"]
        let files = try swiftFiles(under: "Sources")
        var offenders: [String] = []
        for file in files {
            let name = file.lastPathComponent
            guard !pdfKitAllowlist.contains(name) else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            let code = codeLines(source).joined(separator: "\n")
            if leaked.contains(where: { containsWholeWord($0, in: code) }) {
                offenders.append(name)
            }
        }
        #expect(files.count > 5, "Expected several .swift files under Sources, found \(files.count) — the directory walk may be broken")
        #expect(
            offenders.isEmpty,
            "PDFKit types leaked outside the engine and canvas: \(offenders.sorted())"
        )
    }
}

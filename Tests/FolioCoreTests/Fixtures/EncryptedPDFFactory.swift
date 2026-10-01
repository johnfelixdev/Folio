import CoreGraphics
import Foundation

/// Builds encrypted PDFs for tests, using CoreGraphics only.
///
/// CGPDFContext takes passwords and permission flags in its auxiliary info
/// dictionary, so encrypted fixtures need no PDFKit. That keeps the test target
/// free of the framework under test: these fixtures are built by one writer and
/// read back by another, so a bug in PDFKit cannot hide behind itself.
enum EncryptedPDFFactory {

    /// A PDF that opens with no password but forbids printing and copying.
    ///
    /// `info` adds entries such as `kCGPDFContextTitle` to the same auxiliary
    /// dictionary, so they land in the document's Info dictionary.
    static func makeRestricted(
        pageCount: Int,
        ownerPassword: String = "owner",
        info: [String: Any] = [:],
        outline: [(title: String, page: Int)] = []
    ) -> Data {
        let encryption: [String: Any] = [
            kCGPDFContextOwnerPassword as String: ownerPassword,
            kCGPDFContextAllowsPrinting as String: false,
            kCGPDFContextAllowsCopying as String: false,
        ]
        return PDFFactory.makeDocument(
            pageCount: pageCount,
            encryption: encryption.merging(info) { current, _ in current },
            outline: outline
        )
    }

    /// A PDF that refuses to open without the user password.
    static func makeLocked(
        pageCount: Int,
        userPassword: String = "open-me",
        ownerPassword: String = "owner"
    ) -> Data {
        PDFFactory.makeDocument(pageCount: pageCount, encryption: [
            kCGPDFContextUserPassword as String: userPassword,
            kCGPDFContextOwnerPassword as String: ownerPassword,
            kCGPDFContextAllowsPrinting as String: false,
            kCGPDFContextAllowsCopying as String: false,
        ])
    }
}

import FolioCore
import SwiftUI

@main
struct FolioApp: App {
    var body: some Scene {
        // `newDocument`, not `viewing`: the `viewing` variant opens every PDF
        // read-only, so nothing the user did to it could ever be saved.
        DocumentGroup(newDocument: { FolioFileDocument() }) { file in
            DocumentWindow(document: file.document.model)
        }
    }
}

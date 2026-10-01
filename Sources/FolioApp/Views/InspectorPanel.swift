import FolioCore
import SwiftUI

/// Document facts worth knowing, including the ones that matter for phase 3.
struct InspectorPanel: View {

    @ObservedObject var document: FolioDocument

    var body: some View {
        Form {
            Section("Documento") {
                LabeledContent("Páginas", value: "\(document.pageCount)")
                LabeledContent("Estado", value: protectionDescription)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 220)
    }

    private var protectionDescription: String {
        switch document.protection {
        case .open: "Sin protección"
        case .locked: "Protegido con contraseña"
        case .restricted: "Restringido"
        }
    }
}

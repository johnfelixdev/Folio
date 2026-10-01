import FolioCore
import SwiftUI

/// Tells the user about a document's protection, without interrupting them.
///
/// A sheet would block the document behind it for something that is not urgent
/// and often not actionable. This sits above the page and can be ignored.
struct PermissionsBanner: View {

    @ObservedObject var document: FolioDocument
    var onError: (String) -> Void

    private var content: BannerContent? {
        PermissionsService.banner(for: document.protection)
    }

    var body: some View {
        if let content {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "lock")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(.headline)
                    Text(content.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if let label = content.actionLabel {
                    Button(label) { acknowledge() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.separator)
            }
            .padding(12)
            .frame(maxWidth: 640)
            .accessibilityElement(children: .combine)
        }
    }

    private func acknowledge() {
        do {
            try document.perform(RemoveRestrictions())
        } catch {
            onError("No se pudo cambiar el estado de restricciones del documento.")
        }
    }
}

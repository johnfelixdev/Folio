import FolioCore
import SwiftUI

/// One page thumbnail. Shared by the sidebar and the light table so both stay
/// visually identical and both benefit from the same cache.
struct ThumbnailView: View {

    @ObservedObject var document: FolioDocument
    let cache: ThumbnailCache
    let index: Int
    let width: CGFloat
    let isSelected: Bool
    /// Adds or removes this page from the selection, for the accessibility action.
    let onToggleSelection: () -> Void

    private var height: CGFloat { width * 1.294 }  // US Letter

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.background)
                    .shadow(radius: isSelected ? 0 : 1, y: 1)

                if let image = cache.image(
                    for: document.pageID(at: index),
                    page: index,
                    in: document,
                    size: CGSize(width: width * 2, height: height * 2)
                ) {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    // `ThumbnailCache.image` is synchronous: it either returns an
                    // image or fails. There is nothing to wait for, so a spinner
                    // here would spin forever and read as "loading" when it means
                    // "broken".
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }
            .frame(width: width, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 3
                    )
            }

            Text("\(index + 1)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Página \(index + 1) de \(document.pageCount)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // Selection multiple relies on ⌘-click, which VoiceOver's synthesised
        // activation cannot produce — without this action a VoiceOver user can
        // only ever select one page at a time.
        .accessibilityAction(named: isSelected ? "Quitar de la selección" : "Añadir a la selección") {
            onToggleSelection()
        }
    }
}

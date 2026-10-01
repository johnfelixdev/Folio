import FolioCore
import SwiftUI

/// The narrow strip of page thumbnails.
///
/// Deliberately does less than the light table: selecting, scrolling and
/// jumping. Rearranging many pages is what ⌘2 is for.
struct ThumbnailSidebar: View {

    @ObservedObject var document: FolioDocument
    @Binding var selection: Set<Int>
    @Binding var currentPage: Int

    @StateObject private var cacheHolder = CacheHolder()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        ThumbnailView(
                            document: document,
                            cache: cacheHolder.cache,
                            index: index,
                            width: 120,
                            isSelected: selection.contains(index),
                            onToggleSelection: { toggleSelection(index) }
                        )
                        .id(index)
                        .onTapGesture { select(index) }
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: currentPage) { _, page in
                withAnimation { proxy.scrollTo(page, anchor: .center) }
            }
        }
        // Drop only the thumbnails that actually went stale. Evicting everything
        // here would undo the point of keying the cache by page identity.
        //
        // Observing `revision` and *then* reading `invalidatedPageIDs`, rather than
        // observing the set directly: rotating the same page twice, or rotating and
        // then undoing, produces an identical set, so `onChange` on the set never
        // fires and the thumbnail stays frozen at its first state. `revision`
        // always increments, so it always fires.
        .onChange(of: document.revision) { _, _ in
            for id in document.invalidatedPageIDs { cacheHolder.cache.invalidate(id) }
        }
    }

    private func select(_ index: Int) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
        } else {
            selection = [index]
            currentPage = index
        }
    }

    /// Same effect as ⌘-click: toggles this page's membership in the selection
    /// without touching `currentPage`. Exposed as an accessibility action since
    /// VoiceOver's synthesised activation cannot carry the ⌘ modifier.
    private func toggleSelection(_ index: Int) {
        if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
    }
}

/// Keeps one cache alive for the lifetime of the view.
@MainActor
final class CacheHolder: ObservableObject {
    let cache = ThumbnailCache(limit: 300)
}

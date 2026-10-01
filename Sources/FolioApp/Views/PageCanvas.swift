import FolioCore
import PDFKit
import SwiftUI

/// Wraps PDFKit's viewer.
///
/// One of exactly two files allowed to import PDFKit (see ArchitectureTests).
/// It is here because there is no way to use PDFView without a PDFDocument to
/// feed it. Phase 3 replaces this file alongside the engine.
struct PageCanvas: NSViewRepresentable {

    let document: FolioDocument
    /// Changing this forces a reload; `FolioDocument.revision` drives it.
    let revision: Int
    @Binding var currentPage: Int
    /// Surfaces a redraw failure, which the window shows to the user.
    let onError: (String) -> Void

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.delegate = context.coordinator
        reload(view)
        // Without this, `lastRevision` is still -1 when SwiftUI calls
        // `updateNSView` right after `makeNSView`, so the guard passes and the
        // whole document is serialised and re-parsed a second time on every open.
        context.coordinator.lastRevision = revision

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if context.coordinator.lastRevision != revision {
            context.coordinator.lastRevision = revision
            reload(view)
        }
        // Picking a thumbnail changes `currentPage`; follow it. Scrolling the
        // canvas sets `currentPage` to the page already shown, so this is a
        // no-op then and cannot feed back into itself.
        if let shown = view.document, let page = view.currentPage,
           shown.index(for: page) != currentPage,
           let target = shown.page(at: currentPage) {
            view.go(to: target)
        }
    }

    private func reload(_ view: PDFView) {
        // A failure here means the canvas silently diverges from the document
        // the user just edited — the command already succeeded and registered
        // its undo. Staying quiet would show them a document that is not theirs.
        guard let data = try? document.currentData(),
              let loaded = PDFDocument(data: data)
        else {
            // `reload` runs from `makeNSView`/`updateNSView`, i.e. from inside
            // SwiftUI's view-update pass. Calling `onError` synchronously here
            // would mutate the parent's `@State errorMessage` mid-update and
            // trigger "Modifying state during view update, this will cause
            // undefined behavior." Defer it to the next run loop turn instead.
            DispatchQueue.main.async {
                onError("La página no se pudo volver a dibujar. Cierra y vuelve a abrir el documento para verlo actualizado.")
            }
            return
        }
        let previousPage = view.document.flatMap { doc in
            view.currentPage.map { doc.index(for: $0) }
        }
        view.document = loaded
        if let previousPage, let page = loaded.page(at: min(previousPage, loaded.pageCount - 1)) {
            view.go(to: page)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage)
    }

    @MainActor
    final class Coordinator: NSObject, PDFViewDelegate {
        private let currentPage: Binding<Int>
        var lastRevision: Int = -1

        init(currentPage: Binding<Int>) {
            self.currentPage = currentPage
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let document = view.document,
                  let page = view.currentPage
            else { return }
            currentPage.wrappedValue = document.index(for: page)
        }
    }
}

import FolioCore
import SwiftUI
import UniformTypeIdentifiers

/// The full-window page grid.
///
/// Organising pages inside a narrow sidebar is the reason this task feels
/// tedious in other apps. Giving it a view of its own is what the product is
/// for, so everything else in the window stays quiet while this is open.
struct LightTableView: View {

    @ObservedObject var document: FolioDocument
    @Binding var selection: Set<Int>

    @StateObject private var cacheHolder = CacheHolder()
    @State private var dropTarget: Int?
    @State private var errorMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 24)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(0..<document.pageCount, id: \.self) { index in
                    ThumbnailView(
                        document: document,
                        cache: cacheHolder.cache,
                        index: index,
                        width: 160,
                        isSelected: selection.contains(index),
                        onToggleSelection: { toggleSelection(index) }
                    )
                    .overlay(alignment: .leading) { dropIndicator(at: index) }
                    .onTapGesture { select(index) }
                    .draggable(dragPayload(startingAt: index)) {
                        Text("^[\(dragPayload(startingAt: index).indices.count) página](inflect: true)")
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .dropDestination(for: PageDrag.self) { payload, _ in
                        // Indices from another window would rearrange this one.
                        guard let drag = payload.first,
                              PageDragRules.accepts(dragFrom: drag.documentID, into: document.id)
                        else { return false }
                        move(drag.indices, to: index)
                        return true
                    } isTargeted: { targeted in
                        dropTarget = targeted ? index : nil
                    }
                }
            }
            .padding(32)
            .animation(reduceMotion ? nil : .snappy, value: document.revision)
        }
        .dropDestination(for: URL.self) { urls, _ in
            merge(urls)
            return true
        }
        // A real two-way binding, not `.constant`: with `.constant` the setter is
        // a no-op, so the framework's own dismissal is discarded and the alert
        // only closes because the single button happens to clear the message.
        // Adding a second button, or any system dismissal, would silently break it.
        .alert(
            "No se pudo completar la operación",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("Entendido") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        // Observa `revision`, no el conjunto: ver la nota en ThumbnailSidebar.
        .onChange(of: document.revision) { _, _ in
            for id in document.invalidatedPageIDs { cacheHolder.cache.invalidate(id) }
        }
    }

    @ViewBuilder
    private func dropIndicator(at index: Int) -> some View {
        if dropTarget == index {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3)
                .offset(x: -12)
        }
    }

    private func select(_ index: Int) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
        } else {
            selection = [index]
        }
    }

    /// Same effect as ⌘-click: toggles this page's membership in the selection.
    /// Exposed as an accessibility action since VoiceOver's synthesised
    /// activation cannot carry the ⌘ modifier.
    private func toggleSelection(_ index: Int) {
        if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
    }

    private func dragPayload(startingAt index: Int) -> PageDrag {
        PageDrag(
            documentID: document.id,
            indices: PageDragRules.pages(startingAt: index, selection: selection)
        )
    }

    private func move(_ indices: Set<Int>, to destination: Int) {
        guard !indices.isEmpty else { return }
        do {
            try document.perform(
                MovePages(indices: IndexSet(indices), destination: destination))
            selection = []
        } catch {
            errorMessage = "Esas páginas no se pudieron mover. El documento no ha cambiado."
        }
    }

    private func merge(_ urls: [URL]) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else {
            errorMessage = "Folio solo abre archivos PDF. Suelta un .pdf para añadir sus páginas."
            return
        }
        let insertionPoint = dropTarget ?? document.pageCount
        do {
            // Every file is read and checked before the first one goes in, so
            // a bad file refuses the whole drop and the messages below are true.
            let files = try pdfs.map { try Data(contentsOf: $0) }
            try document.perform(
                InsertPages.merging(documents: files, at: insertionPoint, password: nil))
        } catch EngineError.stillLocked {
            errorMessage = "Ese PDF pide una contraseña para abrirse. Ábrelo primero en su propia ventana."
        } catch EngineError.unreadable {
            errorMessage = "Ese archivo no se pudo leer como PDF. Puede estar dañado."
        } catch {
            errorMessage = "No se pudieron añadir esas páginas. El documento no ha cambiado."
        }
    }
}

/// What a page drag carries.
///
/// The document's identity travels with the indices because indices alone
/// mean nothing in another window. See `PageDragRules`.
struct PageDrag: Codable, Transferable {
    let documentID: UUID
    let indices: Set<Int>

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .folioPageDrag)
    }
}

extension UTType {
    static let folioPageDrag = UTType(exportedAs: "com.folio.editor.page-drag")
}

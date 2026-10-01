import FolioCore
import SwiftUI

/// The window for one open PDF: thumbnails on the left, canvas on the right.
struct DocumentWindow: View {

    @ObservedObject var document: FolioDocument
    @Environment(\.undoManager) private var undoManager

    @State private var selection: Set<Int> = []
    @State private var currentPage: Int = 0
    @State private var showsLightTable = false
    @State private var showsInspector = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            ThumbnailSidebar(
                document: document,
                selection: $selection,
                currentPage: $currentPage
            )
            .navigationSplitViewColumnWidth(min: 140, ideal: 180, max: 260)
        } detail: {
            Group {
                if showsLightTable {
                    LightTableView(document: document, selection: $selection)
                } else {
                    PageCanvas(
                        document: document,
                        revision: document.revision,
                        currentPage: $currentPage,
                        onError: show(_:)
                    )
                }
            }
            .overlay(alignment: .top) {
                PermissionsBanner(document: document, onError: show(_:))
            }
        }
        .inspector(isPresented: $showsInspector) {
            InspectorPanel(document: document)
        }
        .toolbar { toolbarContent }
        .onAppear { document.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in document.undoManager = new }
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Vista", selection: $showsLightTable) {
                Image(systemName: "doc.text").tag(false)
                Image(systemName: "square.grid.2x2").tag(true)
            }
            .pickerStyle(.segmented)
            .help("Vista de lectura o mesa de luz")

            Button {
                perform(RotatePages(indices: IndexSet(selection), quarterTurns: -1))
            } label: {
                Image(systemName: "rotate.left")
            }
            .disabled(selection.isEmpty)
            .help("Rotar a la izquierda")

            Button {
                perform(RotatePages(indices: IndexSet(selection), quarterTurns: 1))
            } label: {
                Image(systemName: "rotate.right")
            }
            .disabled(selection.isEmpty)
            .help("Rotar a la derecha")

            Button(role: .destructive) {
                perform(DeletePages(indices: IndexSet(selection)))
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selection.isEmpty)
            .help("Borrar las páginas seleccionadas")

            Button {
                showsInspector.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Mostrar información del documento")
        }
    }

    private func perform(_ command: any PageCommand) {
        do {
            try document.perform(command)
            selection = []
        } catch EngineError.emptyDocument {
            show("Un PDF necesita al menos una página. Deja al menos una sin borrar.")
        } catch {
            show("La operación no se pudo aplicar. El documento no ha cambiado.")
        }
    }

    private func show(_ message: String) {
        errorMessage = message
    }
}

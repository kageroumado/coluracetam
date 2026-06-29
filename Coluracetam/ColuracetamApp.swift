import SwiftUI

@main
struct ColuracetamApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: ColuracetamDocument()) { file in
            ContentView(document: file.$document)
        }
        .defaultSize(width: 720, height: 900)
        .commands {
            DocumentCommands()
        }
    }
}

/// Menu commands that act on the focused document window's ``DocumentWorkspace``.
private struct DocumentCommands: Commands {
    @FocusedValue(\.documentWorkspace) private var workspace

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find…") { workspace?.toggleFind() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(workspace == nil)
        }

        // Zoom lives in the system-provided View menu. A `CommandMenu("View")`
        // would collide with that menu and drop its items, so anchor to a
        // View-menu placement instead.
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In") { workspace?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!(workspace?.canZoomIn ?? false))
            Button("Zoom Out") { workspace?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!(workspace?.canZoomOut ?? false))
            Button("Actual Size") { workspace?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(workspace == nil)
        }

        CommandGroup(after: .importExport) {
            Button("Export as PDF…") { workspace?.exportPDF() }
                .disabled(workspace == nil)
            Button("Export as HTML…") { workspace?.exportHTML() }
                .disabled(workspace == nil)
        }
    }
}

import ColuracetamKit
import SwiftUI
import UniformTypeIdentifiers

/// Per-window view state for an open document.
///
/// Each `ContentView` owns one instance and publishes it as a focused scene
/// value so menu commands (zoom, find, export) act on the active window only.
@MainActor
@Observable
final class DocumentWorkspace {
    /// Reading-comfort font multiplier for this window. `1` is natural size.
    var scale: CGFloat = 1
    /// Whether the find UI is showing for this window.
    var isFindPresented = false
    /// The current find query.
    var searchText = ""

    /// The live document text, kept in sync by `ContentView` for export and
    /// match counting. Bookkeeping for commands, not view state — nothing reads
    /// it in a `body`, so it must not register observation dependencies.
    @ObservationIgnored var source = ""
    /// The document's file URL, when saved to disk. Bookkeeping for export.
    @ObservationIgnored var fileURL: URL?

    // MARK: Zoom

    static let minScale: CGFloat = 0.5
    static let maxScale: CGFloat = 3
    private static let step: CGFloat = 0.1

    var canZoomIn: Bool {
        scale < Self.maxScale - 0.001
    }
    var canZoomOut: Bool {
        scale > Self.minScale + 0.001
    }

    func zoomIn() {
        scale = min(Self.maxScale, (scale + Self.step).rounded(toMultipleOf: Self.step))
    }
    func zoomOut() {
        scale = max(Self.minScale, (scale - Self.step).rounded(toMultipleOf: Self.step))
    }
    func resetZoom() {
        scale = 1
    }

    // MARK: Find

    func toggleFind() {
        isFindPresented.toggle()
    }

    // MARK: Export

    func exportPDF() {
        guard let data = MarkdownExport.pdf(source: source) else { return }
        save(data, name: "\(baseName).pdf", type: .pdf)
    }

    func exportHTML() {
        let html = MarkdownExport.html(source: source, title: baseName)
        save(Data(html.utf8), name: "\(baseName).html", type: .html)
    }

    private var baseName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    private func save(_ data: Data, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
}

private extension CGFloat {
    func rounded(toMultipleOf m: CGFloat) -> CGFloat {
        (self / m).rounded() * m
    }
}

// MARK: - Focused scene value

extension FocusedValues {
    @Entry var documentWorkspace: DocumentWorkspace?
}

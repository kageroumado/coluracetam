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

    /// The live document text, kept in sync by `ContentView` for export and
    /// match counting. Bookkeeping for commands, not view state — nothing reads
    /// it in a `body`, so it must not register observation dependencies.
    @ObservationIgnored var source = ""
    /// Writes replacement text back into the document (set by `ContentView`,
    /// which owns the document binding). Used by whole-buffer transforms like
    /// line-ending conversion.
    @ObservationIgnored var replaceText: ((String) -> Void)?
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

    // MARK: Line endings

    /// The buffer's dominant line ending. Mixed endings read as CRLF if any
    /// CRLF is present (conversion normalizes the stragglers either way).
    var lineEnding: LineEnding {
        source.contains("\r\n") ? .crlf : .lf
    }

    /// Rewrites every line ending in the document to `ending`.
    func setLineEnding(_ ending: LineEnding) {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let converted = ending == .lf
            ? normalized
            : normalized.replacingOccurrences(of: "\n", with: "\r\n")
        guard converted != source else { return }
        replaceText?(converted)
    }

    // MARK: Go to line

    /// Whether the go-to-line prompt is showing.
    var isGoToLinePresented = false
    /// The line-number field's text while the prompt is up.
    var goToLineText = ""
    /// A pending jump for the editor to perform; each request is unique so
    /// jumping to the same line twice still re-scrolls.
    var lineJump: LineJump?

    func promptGoToLine() {
        goToLineText = ""
        isGoToLinePresented = true
    }

    func performGoToLine() {
        guard let line = Int(goToLineText.trimmingCharacters(in: .whitespaces)), line > 0 else { return }
        lineJump = LineJump(line: line)
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

    /// Prints the rendered document via the standard print panel.
    func printDocument() {
        let operation = MarkdownExport.printOperation(source: source, jobTitle: baseName)
        if let window = NSApp.keyWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
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

/// A document's line-ending convention.
enum LineEnding: Hashable {
    /// Unix / macOS (`\n`).
    case lf
    /// Windows (`\r\n`).
    case crlf
}

/// One go-to-line request. Identity makes repeated jumps to the same line
/// distinct, so each request scrolls even if the line number didn't change.
struct LineJump: Equatable {
    let id = UUID()
    let line: Int
}

// MARK: - Focused scene value

extension FocusedValues {
    @Entry var documentWorkspace: DocumentWorkspace?
}

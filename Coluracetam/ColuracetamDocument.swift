import ColuracetamKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The Daring Fireball Markdown type that `.md`/`.markdown` resolve to.
    /// Declared as an imported type in the app's Info.plist.
    nonisolated static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

/// A plain-text Markdown document, edited and saved as UTF-8.
nonisolated struct ColuracetamDocument: FileDocument {
    var text: String

    init(text: String = "") {
        self.text = text
    }

    static let readableContentTypes: [UTType] = [.markdown]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = Self.decode(data)
    }

    /// Converts PDF bytes to Markdown, refusing documents with no usable
    /// text layer instead of opening an empty or garbled window.
    static func importPDF(_ data: Data) throws -> String {
        let result = try PDFImporter.convert(data)
        guard let markdown = result.markdown, !result.needsOCR else {
            throw PDFImportUnsupportedError(result: result)
        }
        return markdown
    }

    /// Decodes file bytes with graceful fallbacks so an unusual encoding opens
    /// (possibly imperfectly) instead of failing: UTF-8 first, UTF-16 when a
    /// byte-order mark says so, Latin-1 (which accepts any byte) last.
    /// Documents are always *saved* as UTF-8.
    ///
    /// Shared with the external-change reload so a file that needed a fallback
    /// to open keeps live-reloading through the same fallbacks.
    static func decode(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        let hasUTF16BOM = data.count >= 2 &&
            ((data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF))
        if hasUTF16BOM, let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        // Latin-1 maps every byte, so this cannot fail.
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Read-only shell document that owns the `.pdf` type: an *editor*
/// DocumentGroup silently refuses types outside its writable set (the Open
/// panel greys them out), so PDFs enter through a `DocumentGroup(viewing:)`
/// scene instead. It converts on read; the scene's view then immediately
/// re-opens the Markdown as a new untitled ``ColuracetamDocument``, so the
/// source PDF is never a save target.
nonisolated struct PDFImportDocument: FileDocument {
    let markdown: String

    static let readableContentTypes: [UTType] = [.pdf]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        markdown = try ColuracetamDocument.importPDF(data)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        // Viewer scenes never save; refuse defensively.
        throw CocoaError(.fileWriteNoPermission)
    }
}

/// Thrown when a PDF has no extractable text layer (scanned or image-only).
nonisolated struct PDFImportUnsupportedError: LocalizedError {
    let result: PDFImportResult

    var errorDescription: String? {
        String(
            localized: "This PDF has no extractable text layer.",
            comment: "Error shown when importing a scanned or image-only PDF",
        )
    }

    var recoverySuggestion: String? {
        String(
            localized: "It looks like a scanned or image-only document. Run it through an OCR tool first, then import the result.",
            comment: "Recovery suggestion for scanned PDF import failure",
        )
    }
}

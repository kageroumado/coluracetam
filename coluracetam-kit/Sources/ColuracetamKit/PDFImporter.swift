import Foundation
import ColuracetamPDFCore

/// Result of converting a PDF into Markdown via the bundled pdf-inspector core.
nonisolated public struct PDFImportResult: Sendable {
    /// Classification of the source PDF.
    public enum DocumentType: String, Decodable, Sendable {
        case textBased, scanned, imageBased, mixed
    }

    /// Converted Markdown, `nil` when the document has no extractable text.
    public let markdown: String?
    public let documentType: DocumentType
    public let pageCount: Int
    /// 1-indexed pages with no usable text layer.
    public let pagesNeedingOCR: [Int]
    /// Title from PDF metadata, if present.
    public let title: String?
    /// Detection confidence, 0–1.
    public let confidence: Double
    /// Broken font encodings were detected; extracted text may be garbled.
    public let hasEncodingIssues: Bool

    /// The import would produce empty or garbled Markdown; the UI should
    /// warn instead of opening a document.
    public var needsOCR: Bool {
        markdown?.isEmpty != false || documentType == .scanned || hasEncodingIssues
    }
}

nonisolated public enum PDFImportError: Error, Sendable {
    /// The converter could not allocate its result string.
    case allocationFailure
    /// pdf-inspector rejected the input (not a PDF, corrupt, bad password…).
    case conversion(String)
    /// The core returned JSON the wrapper does not understand.
    case malformedResponse
}

/// Bytes-in → Markdown-out wrapper over the static Rust core.
nonisolated public enum PDFImporter {
    /// One-time wiring of the bundled CMap data (CID/CJK fonts) into the
    /// Rust core. `static let` gives thread-safe exactly-once semantics.
    private static let bcmapsBootstrap: Void = {
        if let dir = Bundle.module.url(forResource: "bcmaps", withExtension: nil) {
            dir.withUnsafeFileSystemRepresentation { clr_pdf_set_bcmaps_dir($0) }
        }
    }()

    /// Convert PDF bytes to Markdown plus classification metadata.
    ///
    /// CPU-bound — around 20 ms for a ten-page text PDF; call off the main
    /// actor for large documents.
    public static func convert(_ data: Data) throws -> PDFImportResult {
        _ = Self.bcmapsBootstrap
        let json = try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let base = buffer.bindMemory(to: UInt8.self).baseAddress
            guard let raw = clr_pdf_convert(base, buffer.count) else {
                throw PDFImportError.allocationFailure
            }
            defer { clr_string_free(raw) }
            return String(cString: raw)
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(json.utf8)) else {
            throw PDFImportError.malformedResponse
        }
        guard envelope.ok else {
            throw PDFImportError.conversion(envelope.error ?? "unknown error")
        }
        guard let documentType = envelope.pdfType, let pageCount = envelope.pageCount else {
            throw PDFImportError.malformedResponse
        }
        return PDFImportResult(
            markdown: envelope.markdown,
            documentType: documentType,
            pageCount: pageCount,
            pagesNeedingOCR: envelope.pagesNeedingOCR ?? [],
            title: envelope.title,
            confidence: envelope.confidence ?? 0,
            hasEncodingIssues: envelope.hasEncodingIssues ?? false,
        )
    }

    private struct Envelope: Decodable {
        let ok: Bool
        let error: String?
        let markdown: String?
        let pdfType: PDFImportResult.DocumentType?
        let pageCount: Int?
        let pagesNeedingOCR: [Int]?
        let title: String?
        let confidence: Double?
        let hasEncodingIssues: Bool?
    }
}

import Foundation
import Testing
@testable import ColuracetamKit

@Suite("PDFImporter")
struct PDFImporterTests {
    @Test func convertsTextPDFToMarkdown() throws {
        let url = try #require(
            Bundle.module.url(forResource: "sample", withExtension: "pdf", subdirectory: "Fixtures")
        )
        let result = try PDFImporter.convert(Data(contentsOf: url))

        #expect(result.documentType == .textBased)
        #expect(result.pageCount == 1)
        #expect(!result.needsOCR)
        let markdown = try #require(result.markdown)
        #expect(markdown.contains("# Hello from Coluracetam"))
        #expect(markdown.contains("PDF import fixture with a real text layer."))
    }

    @Test func rejectsNonPDFBytes() {
        #expect(throws: PDFImportError.self) {
            _ = try PDFImporter.convert(Data("definitely not a pdf".utf8))
        }
    }

    @Test func rejectsEmptyData() {
        #expect(throws: PDFImportError.self) {
            _ = try PDFImporter.convert(Data())
        }
    }
}

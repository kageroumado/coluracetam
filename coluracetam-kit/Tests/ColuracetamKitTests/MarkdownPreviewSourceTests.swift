import Foundation
import Testing
@testable import ColuracetamKit

@Suite("MarkdownPreviewSource")
struct MarkdownPreviewSourceTests {
    private func tempFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("colu-preview-\(UUID().uuidString).md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test
    func `Short documents are returned whole and untruncated`() throws {
        let body = "# Title\n\nA short paragraph.\n"
        let url = try tempFile(body)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try MarkdownPreviewSource.read(contentsOf: url)
        #expect(result == body)
        #expect(!result.contains("Preview truncated"))
    }

    @Test
    func `Oversized documents are byte-capped with a truncation note`() throws {
        let line = "This is a line of filler text used to exceed the byte budget.\n"
        let huge = String(repeating: line, count: 20_000) // ~1.2 MB
        let url = try tempFile(huge)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try MarkdownPreviewSource.read(contentsOf: url)
        #expect(result.utf8.count < huge.utf8.count)
        #expect(result.utf8.count <= MarkdownPreviewSource.maxBytes + 200)
        #expect(result.contains("Preview truncated"))
    }

    @Test
    func `Many short lines are line-capped`() throws {
        let body = String(repeating: "x\n", count: MarkdownPreviewSource.maxLines + 500)
        let url = try tempFile(body)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try MarkdownPreviewSource.read(contentsOf: url)
        #expect(result.contains("Preview truncated"))
        let contentLines = result.split(separator: "\n").count(where: { $0 == "x" })
        #expect(contentLines <= MarkdownPreviewSource.maxLines)
    }
}

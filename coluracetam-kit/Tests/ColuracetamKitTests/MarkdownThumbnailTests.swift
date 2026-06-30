import AppKit
import Testing
@testable import ColuracetamKit

@Suite("MarkdownThumbnail")
struct MarkdownThumbnailTests {
    private let sample = """
    # Big Heading
    
    This is a **markdown** paragraph with some text.
    
    - item one
    - item two
    
    ```swift
    let clarity = true
    ```
    
    ## Second section
    
    More body text.
    """

    @Test(arguments: [64, 128, 256, 512] as [CGFloat])
    func `Produces a non-empty image across thumbnail sizes`(side: CGFloat) {
        let image = MarkdownThumbnail.image(
            source: sample, size: CGSize(width: side, height: side), displayScale: 2,
        )
        #expect(image != nil)
        #expect(image.map { $0.size.width > 0 && $0.size.height > 0 } == true)
    }

    @Test
    func `Returns nil for an empty document`() {
        let image = MarkdownThumbnail.image(
            source: "   \n\n  ", size: CGSize(width: 128, height: 128), displayScale: 2,
        )
        #expect(image == nil)
    }

    @Test
    func `Renders from a URL reading only a bounded prefix of a huge file`() throws {
        let line = "Line of filler text far exceeding the thumbnail byte budget.\n"
        let huge = "# Title\n\n" + String(repeating: line, count: 50_000) // ~3 MB
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("colu-thumb-\(UUID().uuidString).md")
        try huge.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        // The prefix reader must never pull more than the thumbnail byte budget.
        let (prefix, truncated) = try MarkdownPreviewSource.boundedPrefix(
            contentsOf: url, maxBytes: MarkdownThumbnail.maxBytes, maxLines: 60,
        )
        #expect(truncated)
        #expect(prefix.utf8.count <= MarkdownThumbnail.maxBytes)

        let image = MarkdownThumbnail.image(
            contentsOf: url, size: CGSize(width: 256, height: 256), displayScale: 2,
        )
        #expect(image != nil)
    }
}

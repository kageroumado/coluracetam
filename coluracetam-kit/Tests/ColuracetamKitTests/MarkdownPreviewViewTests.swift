import Testing
@testable import ColuracetamKit

@Suite("MarkdownPreviewView")
struct MarkdownPreviewViewTests {
    @Test
    func `Renders without throwing on a source string`() {
        _ = MarkdownPreviewView(source: "# Hello\n\nworld")
    }
}

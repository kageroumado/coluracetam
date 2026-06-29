import Testing
@testable import ColuracetamKit

@Suite("MarkdownRenderView")
struct MarkdownRenderViewTests {
    @Test
    func `Renders without throwing on a source string`() {
        _ = MarkdownRenderView(source: "# Hello\n\nworld")
    }
}

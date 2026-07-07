import AppKit
import Testing
@testable import ColuracetamKit

@Suite("MarkdownTextStyler")
nonisolated struct MarkdownTextStylerTests {
    private func styled(_ markdown: String, scale: CGFloat = 1) -> NSAttributedString {
        MarkdownTextStyler.attributedString(markdown: markdown, scale: scale)
    }

    private func attribute(
        _ key: NSAttributedString.Key, at substring: String, in text: NSAttributedString,
    ) -> Any? {
        let range = (text.string as NSString).range(of: substring)
        guard range.location != NSNotFound else { return nil }
        return text.attribute(key, at: range.location, effectiveRange: nil)
    }

    @Test
    func `headings scale and embolden, and h1 gets a divider marker`() throws {
        let text = styled("# Title\n\nBody paragraph")
        let headingFont = try #require(attribute(.font, at: "Title", in: text) as? NSFont)
        let bodyFont = try #require(attribute(.font, at: "Body", in: text) as? NSFont)
        #expect(headingFont.pointSize == bodyFont.pointSize * 2)
        #expect(attribute(.markdownHeadingDivider, at: "Title", in: text) != nil)
        #expect(attribute(.markdownHeadingDivider, at: "Body", in: text) == nil)
    }

    @Test
    func `blocks are separated by newlines in document order`() {
        let text = styled("# One\n\nTwo\n\nThree").string
        #expect(text == "One\nTwo\nThree\n")
    }

    @Test
    func `inline code gets a monospaced font and chip background`() throws {
        let text = styled("normal `mono` normal")
        let font = try #require(attribute(.font, at: "mono", in: text) as? NSFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(attribute(.backgroundColor, at: "mono", in: text) != nil)
        #expect(attribute(.backgroundColor, at: "normal", in: text) == nil)
    }

    @Test
    func `bold and italic map to font traits`() throws {
        let text = styled("**bold** and _italic_")
        let bold = try #require(attribute(.font, at: "bold", in: text) as? NSFont)
        let italic = try #require(attribute(.font, at: "italic", in: text) as? NSFont)
        #expect(bold.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(italic.fontDescriptor.symbolicTraits.contains(.italic))
    }

    @Test
    func `code blocks are marked for chip drawing and keep interior newlines`() throws {
        let text = styled("```swift\nlet a = 1\nlet b = 2\n```\n\nAfter")
        #expect(attribute(.markdownCodeBlock, at: "let a", in: text) != nil)
        #expect(attribute(.markdownCodeBlock, at: "After", in: text) == nil)
        #expect(text.string.contains("let a = 1\nlet b = 2"))
        let font = try #require(attribute(.font, at: "let a", in: text) as? NSFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        // Chip padding: no inline chip background inside a block.
        #expect(attribute(.backgroundColor, at: "let a", in: text) == nil)
    }

    @Test
    func `block quotes carry depth and secondary color`() throws {
        let text = styled("> quoted words\n\nplain")
        #expect(attribute(.markdownQuoteDepth, at: "quoted", in: text) as? Int == 1)
        #expect(attribute(.markdownQuoteDepth, at: "plain", in: text) == nil)
        let style = try #require(
            attribute(.paragraphStyle, at: "quoted", in: text) as? NSParagraphStyle)
        #expect(style.headIndent > 0)
    }

    @Test
    func `list items get markers and hanging indents`() throws {
        let text = styled("- first\n- second\n\n1. uno\n2. dos")
        #expect(text.string.contains("•\tfirst"))
        #expect(text.string.contains("•\tsecond"))
        #expect(text.string.contains("1.\tuno"))
        #expect(text.string.contains("2.\tdos"))
        let style = try #require(
            attribute(.paragraphStyle, at: "first", in: text) as? NSParagraphStyle)
        #expect(style.headIndent > style.firstLineHeadIndent)
    }

    @Test
    func `nested unordered lists use hollow bullets`() {
        let text = styled("- outer\n  - inner")
        #expect(text.string.contains("•\touter"))
        #expect(text.string.contains("◦\tinner"))
    }

    @Test
    func `links carry the URL and link color`() throws {
        let text = styled("see [docs](https://example.com/docs)")
        let url = try #require(attribute(.link, at: "docs", in: text) as? URL)
        #expect(url.absoluteString == "https://example.com/docs")
    }

    @Test
    func `tables attach cells to a shared NSTextTable with header emphasis`() throws {
        let text = styled("| A | B |\n|---|---|\n| a1 | b1 |\n| a2 | b2 |")
        let headerStyle = try #require(
            attribute(.paragraphStyle, at: "A", in: text) as? NSParagraphStyle)
        let cellStyle = try #require(
            attribute(.paragraphStyle, at: "a1", in: text) as? NSParagraphStyle)
        let headerBlock = try #require(headerStyle.textBlocks.first as? NSTextTableBlock)
        let cellBlock = try #require(cellStyle.textBlocks.first as? NSTextTableBlock)
        #expect(headerBlock.table === cellBlock.table)
        #expect(headerBlock.table.numberOfColumns == 2)
        #expect(headerBlock.startingRow == 0)
        #expect(cellBlock.startingRow == 1)
        #expect(cellBlock.startingColumn == 0)
        let headerFont = try #require(attribute(.font, at: "A", in: text) as? NSFont)
        #expect(headerFont.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test
    func `thematic breaks produce a decorated placeholder line`() {
        let text = styled("above\n\n---\n\nbelow")
        let range = (text.string as NSString).range(of: "\u{00A0}")
        #expect(range.location != NSNotFound)
        #expect(text.attribute(.markdownThematicBreak, at: range.location, effectiveRange: nil) != nil)
    }

    @Test
    func `scale multiplies font sizes`() throws {
        let normal = styled("plain text")
        let zoomed = styled("plain text", scale: 2)
        let normalFont = try #require(attribute(.font, at: "plain", in: normal) as? NSFont)
        let zoomedFont = try #require(attribute(.font, at: "plain", in: zoomed) as? NSFont)
        #expect(zoomedFont.pointSize == normalFont.pointSize * 2)
    }

    @Test
    func `soft breaks render as spaces, hard breaks as line separators`() {
        let soft = styled("line one\nline two")
        #expect(soft.string.contains("line one line two"))
        let hard = styled("line one  \nline two")
        #expect(hard.string.contains("line one\u{2028}line two"))
    }

    @Test
    func `plain text that is not markdown still renders`() {
        let text = styled("just words, no syntax")
        #expect(text.string.contains("just words, no syntax"))
    }

    @Test
    func `empty input produces empty output`() {
        #expect(styled("").length == 0)
    }
}

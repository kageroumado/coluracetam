import SwiftUI
import Textual

/// Exports a Markdown document to a shareable file format.
@MainActor
public enum MarkdownExport {
    /// US Letter at 72 dpi.
    public static let letter = CGSize(width: 612, height: 792)

    // MARK: PDF

    /// Renders `source` to a multi-page PDF that matches the on-screen render.
    ///
    /// Text is drawn as vector (selectable, sharp at any zoom) by letting
    /// `ImageRenderer` draw the SwiftUI content straight into a PDF `CGContext`,
    /// then slicing the full-height content into pages.
    ///
    /// - Returns: PDF data, or `nil` if the document is empty or rendering fails.
    public static func pdf(
        source: String,
        pageSize: CGSize = letter,
        margin: CGFloat = 48,
    ) -> Data? {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let contentWidth = pageSize.width - margin * 2
        let pageContentHeight = pageSize.height - margin * 2

        // Note: code-block *bodies* render empty here — Textual lays them out in
        // a horizontal scroll container that ImageRenderer snapshots blank.
        // (`.overflowMode(.wrap)` fixes code but blanks all other text under
        // ImageRenderer, a worse trade for prose.) The box/styling still shows.
        let page = StructuredText(markdown: source)
            .textual.structuredTextStyle(.gitHub)
            .frame(width: contentWidth, alignment: .topLeading)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        renderer.render { contentSize, draw in
            // `ImageRenderer` already maps its top-left content space into the
            // context's coordinate system, so no manual y-flip is needed. To
            // paginate, clip each page to the printable area and translate the
            // (full-height) content so this page's slice lands inside it.
            let pageCount = max(1, Int(ceil(contentSize.height / pageContentHeight)))
            for pageIndex in 0 ..< pageCount {
                pdf.beginPDFPage(nil)
                pdf.saveGState()
                pdf.clip(to: CGRect(x: margin, y: margin, width: contentWidth, height: pageContentHeight))
                let ty = pageSize.height - margin - contentSize.height
                    + CGFloat(pageIndex) * pageContentHeight
                pdf.translateBy(x: margin, y: ty)
                draw(pdf)
                pdf.restoreGState()
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return data as Data
    }

    // MARK: HTML

    /// Serializes `source` to a standalone, semantic HTML document.
    ///
    /// Walks the parsed `AttributedString`'s presentation intents to emit real
    /// `<h1>`/`<ul>`/`<pre>`/`<blockquote>` structure (not styled spans), with a
    /// small embedded stylesheet. Nested lists are flattened to a single level.
    public static func html(source: String, title: String) -> String {
        let attributed = (try? AttributedStringMarkdownParser(baseURL: nil).attributedString(for: source))
            ?? AttributedString(source)
        let body = HTMLSerializer.body(from: attributed)
        return HTMLSerializer.document(title: title, body: body)
    }
}

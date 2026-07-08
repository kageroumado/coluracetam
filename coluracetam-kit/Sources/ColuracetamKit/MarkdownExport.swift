import AppKit

/// Exports a Markdown document to a shareable file format.
@MainActor
public enum MarkdownExport {
    /// US Letter at 72 dpi.
    public static let letter = CGSize(width: 612, height: 792)

    // MARK: PDF

    /// Renders `source` to a multi-page PDF that matches the on-screen render.
    ///
    /// Implemented as a panel-less print-to-file through the same TextKit
    /// pipeline as the reader and ``printOperation(source:jobTitle:)``, so
    /// text stays vector (selectable, sharp at any zoom) and AppKit handles
    /// pagination — including code chips and quote bars.
    ///
    /// - Returns: PDF data, or `nil` if the document is empty or rendering fails.
    public static func pdf(
        source: String,
        pageSize: CGSize = letter,
        margin: CGFloat = 48,
    ) -> Data? {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let info = NSPrintInfo()
        info.paperSize = pageSize
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        configurePagination(of: info)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        defer { try? FileManager.default.removeItem(at: url) }

        let operation = NSPrintOperation(view: pageView(source: source, printInfo: info), printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: Print

    /// Builds a print operation for the rendered document.
    ///
    /// The page is a fresh TextKit stack using the same styler and decoration
    /// drawing as the on-screen reader, laid out at the printable width and
    /// paginated by AppKit. Printing always uses natural size (scale 1).
    public static func printOperation(source: String, jobTitle: String? = nil) -> NSPrintOperation {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        configurePagination(of: info)
        let operation = NSPrintOperation(view: pageView(source: source, printInfo: info), printInfo: info)
        if let jobTitle { operation.jobTitle = jobTitle }
        return operation
    }

    private static func configurePagination(of info: NSPrintInfo) {
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
    }

    /// A fully laid-out text view of the rendered document at the printable
    /// width — the shared page source for printing and PDF export.
    private static func pageView(source: String, printInfo info: NSPrintInfo) -> NSTextView {
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let layoutManager = MarkdownLayoutManager()
        let storage = NSTextStorage(
            attributedString: MarkdownTextStyler.attributedString(markdown: source))
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = NSTextView(
            frame: NSRect(origin: .zero, size: NSSize(width: width, height: 0)),
            textContainer: container,
        )
        layoutManager.ensureLayout(for: container)
        textView.setFrameSize(NSSize(
            width: width,
            height: ceil(layoutManager.usedRect(for: container).height),
        ))
        return textView
    }

    // MARK: HTML

    /// Serializes `source` to a standalone, semantic HTML document.
    ///
    /// Walks the parsed `AttributedString`'s presentation intents to emit real
    /// `<h1>`/`<ul>`/`<pre>`/`<blockquote>` structure (not styled spans), with a
    /// small embedded stylesheet. Nested lists are flattened to a single level.
    public static func html(source: String, title: String) -> String {
        let body = HTMLSerializer.body(from: MarkdownTextStyler.parse(markdown: source))
        return HTMLSerializer.document(title: title, body: body)
    }
}

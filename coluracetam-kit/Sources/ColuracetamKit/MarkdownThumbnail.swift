import SwiftUI
import Textual

/// Renders a Finder-thumbnail image of a Markdown document.
///
/// Used by the Quick Look thumbnail extension, which runs under a tight
/// time/memory budget — so only the top of the document is rendered.
@MainActor
public enum MarkdownThumbnail {
    /// Renders the top of `source` as a page-like image sized for `size`.
    ///
    /// - Parameters:
    ///   - source: The Markdown source.
    ///   - size: The thumbnail size in points (`request.maximumSize`).
    ///   - displayScale: The backing pixel scale (`request.scale`).
    ///   - maxLines: How many leading lines to render. Bounds the work so a huge
    ///     document never loads fully.
    /// - Returns: An image, or `nil` if the document is empty or rendering fails.
    public static func image(
        source: String,
        size: CGSize,
        displayScale: CGFloat,
        maxLines: Int = 60,
    ) -> NSImage? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, size.width > 0, size.height > 0 else { return nil }

        let head = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(maxLines)
            .joined(separator: "\n")

        let renderer = ImageRenderer(content: ThumbnailPage(source: head, size: size))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = displayScale
        return renderer.nsImage
    }
}

/// A single, clipped page that shows the top of a document on a paper-like
/// background — the same GitHub styling as the live render, scaled down to fit
/// more content into the icon.
private struct ThumbnailPage: View {
    let source: String
    let size: CGSize

    var body: some View {
        StructuredText(markdown: source)
            .textual.structuredTextStyle(.gitHub)
            .textual.fontScale(scale)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .padding(insetForWidth)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipped()
            .environment(\.colorScheme, .light)
    }

    /// Smaller icons get a smaller font so a useful amount of text still shows.
    private var scale: CGFloat {
        size.width < 128 ? 0.55 : 0.8
    }
    private var insetForWidth: CGFloat {
        max(4, size.width * 0.06)
    }
}

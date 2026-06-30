import SwiftUI
import Textual

/// Renders a Finder-thumbnail image of a Markdown document.
///
/// Used by the Quick Look thumbnail extension, which runs under a tight
/// time/memory budget — so only the top of the document is parsed and rendered.
///
/// The document is parsed *synchronously* to an `AttributedString` and drawn as
/// a single page at a fixed reference size, then handed back for the system to
/// scale down to the requested icon size. This avoids the live ``StructuredText``
/// path, whose styled output only materializes after a run-loop turn (its parse
/// commits via `onChange`): `ImageRenderer` snapshots before that happens, so it
/// would otherwise capture raw, unscaled Markdown syntax.
@MainActor
public enum MarkdownThumbnail {
    /// The reference width, in points, at which the page is laid out before the
    /// system scales it down. Rendering large and shrinking yields the familiar
    /// "miniature page" look instead of a few oversized glyphs in a corner.
    private static let referenceWidth: CGFloat = 480

    /// Renders the top of `source` as a page-like image sized for `size`.
    ///
    /// - Parameters:
    ///   - source: The Markdown source.
    ///   - size: The thumbnail size in points (`request.maximumSize`). Its aspect
    ///     ratio is matched so the scaled-down result fills the icon without
    ///     letterboxing.
    ///   - displayScale: The backing pixel scale (`request.scale`).
    ///   - maxLines: How many leading lines to parse. Bounds the work so a huge
    ///     document never loads fully — only the first page is ever visible.
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

        // Synchronous parse — strips syntax and applies inline styling (bold,
        // italic, inline code) without the `StructuredText` @State indirection.
        guard let parsed = try? AttributedStringMarkdownParser(baseURL: nil)
            .attributedString(for: head)
        else { return nil }
        let attributed = blockStyled(parsed)

        // Lay the page out at a fixed reference size whose aspect matches the
        // request, then let the caller scale the bitmap down to the icon size.
        let referenceSize = CGSize(
            width: referenceWidth,
            height: referenceWidth * size.height / size.width,
        )
        let renderer = ImageRenderer(content: ThumbnailPage(text: attributed, size: referenceSize))
        renderer.proposedSize = ProposedViewSize(referenceSize)
        renderer.scale = displayScale
        return renderer.nsImage
    }
}

/// Reintroduces block structure that `Text(AttributedString)` would otherwise
/// flatten. The parser marks blocks with `presentationIntent` runs but inserts
/// no separators, so headings, paragraphs, and list items render as one run-on
/// line. This walks the runs and inserts breaks between blocks, prefixes list
/// items with a bullet, and bumps heading fonts so the miniature reads like a
/// document rather than a wall of text.
@MainActor
private func blockStyled(_ parsed: AttributedString) -> AttributedString {
    var out = AttributedString()
    var previousBlockID: Int?
    var previousWasListItem = false

    for run in parsed.runs {
        let components = run.presentationIntent?.components ?? []
        let blockID = components.first?.identity

        var isListItem = false
        var headerLevel: Int?
        var isCodeBlock = false
        for component in components {
            switch component.kind {
            case .listItem: isListItem = true
            case let .header(level): headerLevel = level
            case .codeBlock: isCodeBlock = true
            default: break
            }
        }

        let startingNewBlock = blockID != previousBlockID
        if startingNewBlock, !out.characters.isEmpty {
            out.append(AttributedString(isListItem && previousWasListItem ? "\n" : "\n\n"))
        }

        var piece = AttributedString(parsed[run.range])
        if startingNewBlock, isListItem {
            piece = AttributedString("•  ") + piece
        }
        if let headerLevel {
            let sizes: [CGFloat] = [26, 21, 18, 16, 15, 15]
            let size = sizes[min(max(headerLevel, 1), sizes.count) - 1]
            piece.font = .system(size: size, weight: .bold)
        } else if isCodeBlock {
            piece.font = .system(size: 13, design: .monospaced)
            piece.foregroundColor = .secondary
        }
        out.append(piece)

        previousBlockID = blockID
        previousWasListItem = isListItem
    }
    return out
}

/// A single, clipped page that shows the top of a document on a paper-like
/// background — a faithful miniature of the rendered document, laid out at a
/// generous reference size so the downscaled icon reads as a page of text.
private struct ThumbnailPage: View {
    let text: AttributedString
    let size: CGSize

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipped()
            .environment(\.colorScheme, .light)
    }
}

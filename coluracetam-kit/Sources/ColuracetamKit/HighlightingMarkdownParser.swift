import SwiftUI
import Textual

/// A ``MarkupParser`` that wraps Textual's Markdown parser and paints a
/// background highlight onto every occurrence of a search term.
///
/// Textual builds its `Text` per run with `Text(AttributedString(slice))`, which
/// honors the SwiftUI `backgroundColor` run attribute — so setting that attribute
/// on matched ranges is enough to highlight them in the rendered output without
/// any library support for find.
///
/// Matching runs against the *rendered* plain text (markdown syntax already
/// stripped by the underlying parser), which is what the reader actually sees.
struct HighlightingMarkdownParser: MarkupParser {
    private let base: AttributedStringMarkdownParser
    private let term: String
    private let highlight: Color

    init(term: String, baseURL: URL? = nil, highlight: Color = Color.yellow.opacity(0.45)) {
        self.base = AttributedStringMarkdownParser(baseURL: baseURL)
        self.term = term
        self.highlight = highlight
    }

    func attributedString(for input: String) throws -> AttributedString {
        var attributed = try base.attributedString(for: input)
        guard !term.isEmpty else { return attributed }

        let plain = String(attributed.characters)
        var searchRange = plain.startIndex ..< plain.endIndex
        while let match = plain.range(
            of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange,
        ) {
            let lower = plain.distance(from: plain.startIndex, to: match.lowerBound)
            let upper = plain.distance(from: plain.startIndex, to: match.upperBound)
            let start = attributed.index(attributed.startIndex, offsetByCharacters: lower)
            let end = attributed.index(attributed.startIndex, offsetByCharacters: upper)
            attributed[start ..< end].backgroundColor = highlight

            if match.upperBound == plain.endIndex { break }
            searchRange = match.upperBound ..< plain.endIndex
        }
        return attributed
    }
}

import SwiftUI
import Textual

/// A read-only, scrollable view that renders Markdown source as styled rich text.
///
/// This view is the single rendering path shared by the main app's *rendered*
/// mode, the Quick Look preview extension, and the thumbnail extension, so the
/// in-app render and the Finder preview are guaranteed identical.
///
/// Rendering is backed by [Textual](https://github.com/gonzalezreal/textual)'s
/// `StructuredText`, styled with its GitHub preset (heading scale, dividers,
/// code-block backgrounds, table rules) so light and dark both read well.
public struct MarkdownRenderView: View {
    private let source: String
    private let scale: CGFloat
    private let searchTerm: String
    private let showsPlaceholder: Bool

    /// Creates a view that renders the given Markdown source string.
    ///
    /// - Parameters:
    ///   - source: The Markdown source to render.
    ///   - scale: A font-size multiplier for reading-comfort zoom. `1` is the
    ///     document's natural size.
    ///   - searchTerm: When non-empty, occurrences in the *rendered* text are
    ///     highlighted. Matching is case- and diacritic-insensitive.
    ///   - showsPlaceholder: When `true` (the default), an empty document shows
    ///     a "nothing to preview" placeholder. The live editing split passes
    ///     `false` so the preview pane keeps a stable, full-bleed layout while
    ///     the user types into an empty document — a structural swap here would
    ///     otherwise steal first-responder from the editor on the first keystroke.
    public init(source: String, scale: CGFloat = 1, searchTerm: String = "", showsPlaceholder: Bool = true) {
        self.source = source
        self.scale = scale
        self.searchTerm = searchTerm
        self.showsPlaceholder = showsPlaceholder
    }

    /// Creates a view by reading Markdown from a file URL.
    ///
    /// Convenience for the Quick Look extensions, which are handed a
    /// sandbox-granted file URL.
    public init(contentsOf url: URL, scale: CGFloat = 1) throws {
        self.source = try String(contentsOf: url, encoding: .utf8)
        self.scale = scale
        self.searchTerm = ""
        self.showsPlaceholder = true
    }

    public var body: some View {
        if showsPlaceholder, source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "Empty Document",
                systemImage: "doc",
                description: Text("There's nothing to preview yet."),
            )
        } else {
            ScrollView {
                styledText
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
    }

    private var styledText: some View {
        Group {
            if searchTerm.isEmpty {
                StructuredText(markdown: source)
            } else {
                // The parser captures the term; re-key the view by the term so a
                // changed search re-parses (StructuredText only re-parses when its
                // markup string changes, not when the parser instance does).
                StructuredText(source, parser: HighlightingMarkdownParser(term: searchTerm))
                    .id(searchTerm)
            }
        }
        .textual.structuredTextStyle(.gitHub)
        .textual.fontScale(scale)
        .textual.textSelection(.enabled)
    }

    /// The number of occurrences of `term` in the *rendered* text of `source`.
    ///
    /// Counts against the parsed plain text (markdown syntax stripped) so the
    /// reported count matches what ``init(source:scale:searchTerm:)`` highlights.
    @MainActor
    public static func matchCount(in source: String, of term: String) -> Int {
        guard !term.isEmpty else { return 0 }
        let plain = (try? AttributedStringMarkdownParser(baseURL: nil).attributedString(for: source))
            .map { String($0.characters) } ?? source
        var count = 0
        var range = plain.startIndex ..< plain.endIndex
        while let match = plain.range(
            of: term, options: [.caseInsensitive, .diacriticInsensitive], range: range,
        ) {
            count += 1
            if match.upperBound == plain.endIndex { break }
            range = match.upperBound ..< plain.endIndex
        }
        return count
    }
}

#Preview {
    MarkdownRenderView(source: """
    # Coluracetam
    
    Render Markdown the moment you press **space**.
    
    - sharper contrast
    - more vivid color
    - `inline code`
    
    ```swift
    let clarity = true
    ```
    """)
    .frame(width: 480, height: 360)
}

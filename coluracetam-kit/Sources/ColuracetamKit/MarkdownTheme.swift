import AppKit

/// The GitHub-inspired palette and metrics used by ``MarkdownTextStyler``,
/// mirroring Textual's `.gitHub` preset so the TextKit render matches the
/// previous SwiftUI render.
///
/// Every color is appearance-dynamic (resolved at draw time), so a light/dark
/// switch re-renders correctly without rebuilding the attributed string.
nonisolated public enum MarkdownTheme {
    /// The edge inset, in points, around rendered document content.
    ///
    /// Public because the app's source editor applies the same inset so the
    /// source pane lines up exactly with the preview pane in the split view.
    public static let contentInset: CGFloat = 20

    // MARK: Colors (values lifted from Textual's DynamicColor+GitHub)

    static let primary = dynamic(
        light: NSColor(srgbRed: 6 / 255, green: 6 / 255, blue: 6 / 255, alpha: 1),
        dark: NSColor(srgbRed: 251 / 255, green: 251 / 255, blue: 252 / 255, alpha: 1),
    )
    static let secondary = dynamic(
        light: NSColor(srgbRed: 107 / 255, green: 110 / 255, blue: 123 / 255, alpha: 1),
        dark: NSColor(srgbRed: 146 / 255, green: 148 / 255, blue: 160 / 255, alpha: 1),
    )
    static let tertiary = dynamic(
        light: NSColor(srgbRed: 107 / 255, green: 110 / 255, blue: 123 / 255, alpha: 1),
        dark: NSColor(srgbRed: 109 / 255, green: 112 / 255, blue: 125 / 255, alpha: 1),
    )
    static let secondaryBackground = dynamic(
        light: NSColor(srgbRed: 247 / 255, green: 247 / 255, blue: 249 / 255, alpha: 1),
        dark: NSColor(srgbRed: 37 / 255, green: 38 / 255, blue: 42 / 255, alpha: 1),
    )
    static let link = dynamic(
        light: NSColor(srgbRed: 44 / 255, green: 101 / 255, blue: 207 / 255, alpha: 1),
        dark: NSColor(srgbRed: 76 / 255, green: 142 / 255, blue: 248 / 255, alpha: 1),
    )
    static let border = dynamic(
        light: NSColor(srgbRed: 228 / 255, green: 228 / 255, blue: 232 / 255, alpha: 1),
        dark: NSColor(srgbRed: 66 / 255, green: 68 / 255, blue: 78 / 255, alpha: 1),
    )
    static let divider = dynamic(
        light: NSColor(srgbRed: 208 / 255, green: 208 / 255, blue: 211 / 255, alpha: 1),
        dark: NSColor(srgbRed: 51 / 255, green: 52 / 255, blue: 56 / 255, alpha: 1),
    )

    // MARK: Metrics

    /// Heading font multipliers for levels 1–6.
    static let headingScales: [CGFloat] = [2, 1.5, 1.25, 1, 0.875, 0.85]
    /// Code (inline and block) font multiplier.
    static let codeScale: CGFloat = 0.85
    /// Body line spacing as a fraction of the font size.
    static let lineSpacingFactor: CGFloat = 0.25
    /// Code block line spacing as a fraction of the font size.
    static let codeLineSpacingFactor: CGFloat = 0.225
    /// Vertical gap after most blocks, in points (unscaled, like Textual).
    static let blockSpacing: CGFloat = 16
    /// Vertical gap before a heading or around a thematic break, in points.
    static let largeBlockSpacing: CGFloat = 24
    /// Horizontal inset of code block text within its background chip.
    static let codeBlockPadding: CGFloat = 16
    /// Corner radius of the code block background chip.
    static let codeBlockCornerRadius: CGFloat = 6
    /// Per-level indentation step for lists and block quotes.
    static let indentStep: CGFloat = 26
    /// Tight vertical gap between items within one list.
    static let listItemSpacing: CGFloat = 4
    /// Table cell padding: horizontal and vertical.
    static let tableCellPaddingH: CGFloat = 13
    static let tableCellPaddingV: CGFloat = 6

    /// The code-block background chip for a block whose laid-out text occupies
    /// `textRect` (container coordinates): full container width, padded by
    /// ``codeBlockPadding`` above and below the text.
    ///
    /// Shared by the drawing (`MarkdownLayoutManager`) and hover hit-testing
    /// (`MarkdownPreviewTextView`) so the two can never disagree. The paragraph
    /// spacing in ``MarkdownTextStyler`` reserves exactly this overhang plus
    /// the standard block gap.
    static func codeChipRect(textRect: NSRect, containerWidth: CGFloat) -> NSRect {
        NSRect(
            x: 0,
            y: textRect.minY - codeBlockPadding,
            width: containerWidth,
            height: textRect.height + codeBlockPadding * 2,
        )
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        }
    }
}

/// Custom attributes carrying block-decoration metadata from
/// ``MarkdownTextStyler`` to ``MarkdownLayoutManager``'s background drawing.
nonisolated extension NSAttributedString.Key {
    /// Present (as `true`) on the full range of a fenced/indented code block.
    static let markdownCodeBlock = NSAttributedString.Key("glass.kagerou.coluracetam.codeBlock")
    /// Block quote nesting depth (`Int ≥ 1`) on quoted paragraph ranges.
    static let markdownQuoteDepth = NSAttributedString.Key("glass.kagerou.coluracetam.quoteDepth")
    /// Present (as `true`) on the placeholder line of a thematic break.
    static let markdownThematicBreak = NSAttributedString.Key("glass.kagerou.coluracetam.thematicBreak")
    /// Present (as `true`) on level 1–2 headings, which draw a bottom divider.
    static let markdownHeadingDivider = NSAttributedString.Key("glass.kagerou.coluracetam.headingDivider")
}

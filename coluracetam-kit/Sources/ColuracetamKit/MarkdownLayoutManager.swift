import AppKit

/// A layout manager that draws the block decorations plain text attributes
/// can't express: code-block background chips, block-quote bars, thematic
/// break rules, and the divider under level 1–2 headings.
///
/// ``MarkdownTextStyler`` marks the relevant ranges with custom attributes
/// (see `NSAttributedString.Key.markdownCodeBlock` and friends); this class
/// resolves them to line-fragment geometry at draw time, so decorations
/// scroll, wrap, and invalidate with the text for free.
nonisolated final class MarkdownLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // Custom decorations must go down FIRST: `super` paints the selection
        // highlight (and inline-code `backgroundColor` runs), and anything
        // filled after it would cover the selection — making selected text in
        // a code block look unselectable.
        drawBlockDecorations(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawBlockDecorations(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage, let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let width = container.size.width

        textStorage.enumerateAttribute(.markdownCodeBlock, in: charRange) { value, range, _ in
            guard value != nil else { return }
            let rect = decorationRect(for: fullRange(of: .markdownCodeBlock, around: range), in: container)
            var chip = MarkdownTheme.codeChipRect(textRect: rect, containerWidth: width)
            chip.origin.x += origin.x
            chip.origin.y += origin.y
            MarkdownTheme.secondaryBackground.setFill()
            NSBezierPath(
                roundedRect: chip,
                xRadius: MarkdownTheme.codeBlockCornerRadius,
                yRadius: MarkdownTheme.codeBlockCornerRadius,
            ).fill()
        }

        textStorage.enumerateAttribute(.markdownQuoteDepth, in: charRange) { value, range, _ in
            guard let depth = value as? Int else { return }
            let rect = decorationRect(for: range, in: container)
            MarkdownTheme.border.setFill()
            for level in 0 ..< depth {
                let bar = NSRect(
                    x: origin.x + CGFloat(level) * MarkdownTheme.indentStep * 0.7,
                    y: origin.y + rect.minY,
                    width: 3,
                    height: rect.height,
                )
                NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }

        textStorage.enumerateAttribute(.markdownThematicBreak, in: charRange) { value, range, _ in
            guard value != nil else { return }
            let rect = decorationRect(for: range, in: container)
            MarkdownTheme.border.setFill()
            NSRect(
                x: origin.x, y: origin.y + rect.midY - 1.5, width: width, height: 3,
            ).fill()
        }

        textStorage.enumerateAttribute(.markdownHeadingDivider, in: charRange) { value, range, _ in
            guard value != nil else { return }
            let rect = decorationRect(for: range, in: container)
            MarkdownTheme.divider.setFill()
            NSRect(
                x: origin.x, y: origin.y + rect.maxY + 4, width: width, height: 1,
            ).fill()
        }
    }

    /// The union of line-fragment geometry for a character range, in container
    /// coordinates.
    private func decorationRect(for charRange: NSRange, in container: NSTextContainer) -> NSRect {
        let glyphs = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        return boundingRect(forGlyphRange: glyphs, in: container)
    }

    /// Extends `range` to the maximal run of `key`, so a partially visible
    /// block (its top scrolled offscreen) still measures from its true start
    /// and the chip doesn't clip at the viewport edge.
    private func fullRange(of key: NSAttributedString.Key, around range: NSRange) -> NSRange {
        guard let textStorage else { return range }
        var effective = NSRange()
        _ = textStorage.attribute(
            key, at: range.location, longestEffectiveRange: &effective,
            in: NSRange(location: 0, length: textStorage.length),
        )
        return effective
    }
}

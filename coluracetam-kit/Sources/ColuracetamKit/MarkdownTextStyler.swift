import AppKit

/// Converts Markdown source into a fully styled `NSAttributedString` for
/// display in a TextKit text view.
///
/// This is the heavyweight half of the render pipeline (parse + style); the
/// text view's lazy layout is the cheap half. The styler is `nonisolated` and
/// pure so callers can run it off the main actor for large documents.
///
/// Block structure comes from Foundation's Markdown support (cmark-gfm) via
/// `presentationIntent` runs; styling mirrors Textual's GitHub preset (see
/// ``MarkdownTheme``) so the TextKit render matches the previous SwiftUI one.
/// Block decorations that plain attributes can't express — code-block chips,
/// quote bars, thematic breaks, heading dividers — are marked with custom
/// attributes and drawn by `MarkdownLayoutManager`.
nonisolated public enum MarkdownTextStyler {
    /// Parses and styles `markdown` at the given reading-comfort `scale`.
    public static func attributedString(markdown: String, scale: CGFloat = 1) -> NSAttributedString {
        Renderer(scale: scale).render(parse(markdown: markdown))
    }

    /// Parses Markdown into an `AttributedString` with `presentationIntent`
    /// block structure (cmark-gfm via Foundation). Shared by the styler, the
    /// HTML serializer, and the thumbnail renderer.
    static func parse(markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible,
        )
        return (try? AttributedString(markdown: markdown, options: options, baseURL: nil))
            ?? AttributedString(markdown)
    }
}

// MARK: - Renderer

nonisolated private struct Renderer {
    let baseSize: CGFloat

    init(scale: CGFloat) {
        baseSize = NSFont.systemFontSize * scale
    }

    /// One top-level unit of output: a run of text sharing a block identity
    /// (a paragraph, heading, code block, list-item paragraph, table cell…).
    private struct Block {
        var context: BlockContext
        var text = NSMutableAttributedString()
        /// Extra spacing this block must add above itself to keep the visible
        /// inter-block gap uniform when the previous block ends "tight" —
        /// table cells carry no spacing at all, list items only a small one.
        var extraSpacingBefore: CGFloat = 0
    }

    func render(_ parsed: AttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var current: Block?
        var tables = TableAssembler()
        var seenListItemIDs: Set<Int> = []
        var previousContext: BlockContext?

        for run in parsed.runs {
            let context = BlockContext(components: run.presentationIntent?.components ?? [])
            var text = String(parsed.characters[run.range])

            if current?.context.blockID != context.blockID {
                if let block = current {
                    flush(block, into: out, tables: &tables)
                    previousContext = block.context
                }
                var block = Block(context: context)
                block.extraSpacingBefore = extraSpacing(after: previousContext, before: context)
                // The first block of each list item carries the marker; follow-up
                // paragraphs of the same item align to the text column instead.
                if let itemID = context.listItemID, !seenListItemIDs.contains(itemID) {
                    seenListItemIDs.insert(itemID)
                    block.text.append(marker(for: context))
                }
                current = block
            }

            if let inline = run.inlinePresentationIntent {
                if inline.contains(.softBreak) { text = " " }
                if inline.contains(.lineBreak) { text = "\u{2028}" }
            }
            // A thematic break has no content; give it a line to decorate.
            if context.isThematicBreak { text = "\u{00A0}" }

            current?.text.append(NSAttributedString(
                string: text,
                attributes: inlineAttributes(for: run, in: context),
            ))
        }
        if let block = current { flush(block, into: out, tables: &tables) }
        return out
    }

    // MARK: Block assembly

    private func flush(_ block: Block, into out: NSMutableAttributedString, tables: inout TableAssembler) {
        guard block.text.length > 0 else { return }
        let text = block.text
        text.append(NSAttributedString(string: "\n", attributes: [
            .font: baseFont(for: block.context),
            .foregroundColor: MarkdownTheme.primary,
        ]))
        let range = NSRange(location: 0, length: text.length)

        if block.context.isCodeBlock {
            styleCodeBlock(text, extraSpacingBefore: block.extraSpacingBefore)
        } else if let cell = block.context.tableCell {
            text.addAttribute(
                .paragraphStyle,
                value: tables.paragraphStyle(for: cell, baseSize: baseSize),
                range: range,
            )
        } else {
            text.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(for: block.context, extraSpacingBefore: block.extraSpacingBefore),
                range: range,
            )
        }

        if block.context.quoteDepth > 0 {
            text.addAttribute(.markdownQuoteDepth, value: block.context.quoteDepth, range: range)
        }
        if block.context.isThematicBreak {
            text.addAttribute(.markdownThematicBreak, value: true, range: range)
        }
        if let level = block.context.headerLevel, level <= 2 {
            text.addAttribute(.markdownHeadingDivider, value: true, range: range)
        }
        out.append(text)
    }

    /// Code block content arrives as one run containing interior newlines, so
    /// each interior line is its own TextKit paragraph. Spacing must apply only
    /// at the edges of the block, while indent and chip attributes cover it all.
    ///
    /// The chip is drawn overhanging the text by ``MarkdownTheme/codeBlockPadding``
    /// on both ends, so the edge paragraphs reserve that overhang *plus* the
    /// standard gap — keeping the visible chip-to-neighbor distance identical
    /// to every other block gap.
    private func styleCodeBlock(_ text: NSMutableAttributedString, extraSpacingBefore: CGFloat) {
        let range = NSRange(location: 0, length: text.length)
        text.addAttribute(.markdownCodeBlock, value: true, range: range)

        let body = codeParagraphStyle(spacingBefore: 0, spacingAfter: 0)
        text.addAttribute(.paragraphStyle, value: body, range: range)

        let chipPad = MarkdownTheme.codeBlockPadding
        let spacingBefore = chipPad + extraSpacingBefore
        let spacingAfter = chipPad + MarkdownTheme.blockSpacing

        let string = text.string as NSString
        let first = string.paragraphRange(for: NSRange(location: 0, length: 0))
        // length - 1 skips the trailing terminator we appended, so "last" is
        // the final content line.
        let last = string.paragraphRange(for: NSRange(location: max(0, text.length - 1), length: 0))
        let isSingleParagraph = first == last
        text.addAttribute(
            .paragraphStyle,
            value: codeParagraphStyle(
                spacingBefore: spacingBefore,
                spacingAfter: isSingleParagraph ? spacingAfter : 0,
            ),
            range: first,
        )
        if !isSingleParagraph {
            text.addAttribute(
                .paragraphStyle,
                value: codeParagraphStyle(spacingBefore: 0, spacingAfter: spacingAfter),
                range: last,
            )
        }
    }

    /// The spacing a block must add above itself so the *visible* gap to its
    /// predecessor equals the standard block gap, regardless of how tightly
    /// the predecessor's own spacing ends.
    private func extraSpacing(after previous: BlockContext?, before context: BlockContext) -> CGFloat {
        guard let previous else { return 0 }
        // Table cells can't carry spacing (they'd push rows apart), so a gap
        // above a table comes from the previous block's own trailing spacing.
        guard context.tableCell == nil else { return 0 }

        if previous.tableCell != nil {
            return MarkdownTheme.blockSpacing
        }
        let leavingList = previous.listDepth > 0
            && (context.listDepth == 0 || context.listID != previous.listID)
        if leavingList {
            return MarkdownTheme.blockSpacing - MarkdownTheme.listItemSpacing
        }
        return 0
    }

    // MARK: Inline styling

    private func inlineAttributes(
        for run: AttributedString.Runs.Run, in context: BlockContext,
    ) -> [NSAttributedString.Key: Any] {
        var font = baseFont(for: context)
        var color = baseColor(for: context)
        var attributes: [NSAttributedString.Key: Any] = [:]

        if let inline = run.inlinePresentationIntent {
            if inline.contains(.code) {
                font = .monospacedSystemFont(
                    ofSize: font.pointSize * MarkdownTheme.codeScale,
                    weight: context.headerLevel == nil ? .regular : .semibold,
                )
                if !context.isCodeBlock {
                    attributes[.backgroundColor] = MarkdownTheme.secondaryBackground
                }
            }
            if inline.contains(.stronglyEmphasized) { font = font.withTrait(.bold) }
            if inline.contains(.emphasized) { font = font.withTrait(.italic) }
            if inline.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
        }
        if let url = run.link {
            attributes[.link] = url
            color = MarkdownTheme.link
        }

        attributes[.font] = font
        attributes[.foregroundColor] = color
        return attributes
    }

    private func baseFont(for context: BlockContext) -> NSFont {
        if let level = context.headerLevel {
            let scale = MarkdownTheme.headingScales[min(level, 6) - 1]
            return .systemFont(ofSize: baseSize * scale, weight: .semibold)
        }
        if context.isCodeBlock {
            return .monospacedSystemFont(ofSize: baseSize * MarkdownTheme.codeScale, weight: .regular)
        }
        var font = NSFont.systemFont(ofSize: baseSize)
        if let cell = context.tableCell, cell.isHeader {
            font = .systemFont(ofSize: baseSize, weight: .semibold)
        }
        return font
    }

    private func baseColor(for context: BlockContext) -> NSColor {
        if context.headerLevel == 6 { return MarkdownTheme.tertiary }
        if context.quoteDepth > 0 { return MarkdownTheme.secondary }
        return MarkdownTheme.primary
    }

    // MARK: Paragraph styles

    private func paragraphStyle(
        for context: BlockContext, extraSpacingBefore: CGFloat = 0,
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = baseSize * MarkdownTheme.lineSpacingFactor
        style.paragraphSpacing = MarkdownTheme.blockSpacing

        if let level = context.headerLevel {
            style.paragraphSpacingBefore = MarkdownTheme.largeBlockSpacing
            style.lineSpacing = baseSize * MarkdownTheme.headingScales[min(level, 6) - 1] * 0.125
        }
        if context.isThematicBreak {
            style.paragraphSpacingBefore = MarkdownTheme.largeBlockSpacing
            style.paragraphSpacing = MarkdownTheme.largeBlockSpacing
            style.minimumLineHeight = 4
            style.maximumLineHeight = 4
        }

        let quoteIndent = CGFloat(context.quoteDepth) * MarkdownTheme.indentStep * 0.7
        let listIndent = CGFloat(context.listDepth) * MarkdownTheme.indentStep
        let indent = quoteIndent + listIndent
        style.firstLineHeadIndent = context.listDepth > 0 ? indent - MarkdownTheme.indentStep : indent
        style.headIndent = indent
        if context.listDepth > 0 {
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
            style.paragraphSpacing = MarkdownTheme.listItemSpacing
        }
        style.paragraphSpacingBefore = max(style.paragraphSpacingBefore, extraSpacingBefore)
        return style
    }

    private func codeParagraphStyle(spacingBefore: CGFloat, spacingAfter: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let codeSize = baseSize * MarkdownTheme.codeScale
        style.lineSpacing = codeSize * MarkdownTheme.codeLineSpacingFactor
        style.firstLineHeadIndent = MarkdownTheme.codeBlockPadding
        style.headIndent = MarkdownTheme.codeBlockPadding
        style.tailIndent = -MarkdownTheme.codeBlockPadding
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        return style
    }

    private func marker(for context: BlockContext) -> NSAttributedString {
        let glyph: String
        if let ordinal = context.listOrdinal {
            glyph = "\(ordinal)."
        } else {
            let glyphs = ["•", "◦", "▪"]
            glyph = glyphs[min(max(context.listDepth, 1), glyphs.count) - 1]
        }
        return NSAttributedString(string: "\(glyph)\t", attributes: [
            .font: NSFont.systemFont(ofSize: baseSize),
            .foregroundColor: MarkdownTheme.primary,
        ])
    }
}

// MARK: - Block context

/// The block-structure facts extracted from one run's `PresentationIntent`.
///
/// `components` order is innermost-first: a paragraph inside a list inside a
/// quote yields `[paragraph, listItem, unorderedList, blockQuote]`.
nonisolated private struct BlockContext {
    var blockID: Int?
    var headerLevel: Int?
    var isCodeBlock = false
    var isThematicBreak = false
    var quoteDepth = 0
    var listDepth = 0
    var listOrdinal: Int?
    var listItemID: Int?
    /// Identity of the *outermost* list containing this block, for detecting
    /// where one list ends and another (or non-list content) begins.
    var listID: Int?
    var tableCell: TableCellContext?

    init(components: [PresentationIntent.IntentType]) {
        blockID = components.first?.identity

        var tableID: Int?
        var columnIndex: Int?
        var columns: [PresentationIntent.TableColumn] = []
        var rowIndex: Int?
        var isHeaderRow = false
        var innermostListIsOrdered: Bool?

        for component in components {
            switch component.kind {
            case let .header(level):
                headerLevel = level
            case .codeBlock:
                isCodeBlock = true
            case .thematicBreak:
                isThematicBreak = true
            case .blockQuote:
                quoteDepth += 1
            case .orderedList:
                listDepth += 1
                listID = component.identity
                if innermostListIsOrdered == nil { innermostListIsOrdered = true }
            case .unorderedList:
                listDepth += 1
                listID = component.identity
                if innermostListIsOrdered == nil { innermostListIsOrdered = false }
            case let .listItem(ordinal):
                if listItemID == nil {
                    listItemID = component.identity
                    listOrdinal = ordinal
                }
            case let .table(tableColumns):
                tableID = component.identity
                columns = tableColumns
            case let .tableCell(index):
                columnIndex = index
            case .tableHeaderRow:
                isHeaderRow = true
                rowIndex = 0
            case let .tableRow(index):
                // Row indices already count the header row: the first body
                // row arrives as index 1.
                rowIndex = index
            default:
                break
            }
        }
        // The marker glyph follows the *innermost* list's type: an item of an
        // unordered list gets a bullet even when an ordered list wraps it.
        if innermostListIsOrdered != true {
            listOrdinal = nil
        }

        if let tableID, let columnIndex, let rowIndex {
            tableCell = TableCellContext(
                tableID: tableID,
                row: rowIndex,
                column: columnIndex,
                columns: columns,
                isHeader: isHeaderRow,
            )
        }
    }
}

nonisolated private struct TableCellContext {
    var tableID: Int
    var row: Int
    var column: Int
    var columns: [PresentationIntent.TableColumn]
    var isHeader: Bool
}

// MARK: - Table assembly

/// Builds one shared `NSTextTable` per Markdown table and hands out the
/// per-cell paragraph styles that attach cells to it.
nonisolated private struct TableAssembler {
    private var tables: [Int: NSTextTable] = [:]

    mutating func paragraphStyle(for cell: TableCellContext, baseSize: CGFloat) -> NSParagraphStyle {
        let table = table(for: cell)
        let block = NSTextTableBlock(
            table: table,
            startingRow: cell.row,
            rowSpan: 1,
            startingColumn: cell.column,
            columnSpan: 1,
        )
        block.setBorderColor(MarkdownTheme.border)
        block.setWidth(0.5, type: .absoluteValueType, for: .border)
        block.setWidth(MarkdownTheme.tableCellPaddingH, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(MarkdownTheme.tableCellPaddingH, type: .absoluteValueType, for: .padding, edge: .maxX)
        block.setWidth(MarkdownTheme.tableCellPaddingV, type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(MarkdownTheme.tableCellPaddingV, type: .absoluteValueType, for: .padding, edge: .maxY)
        // GitHub shades every second body row (header is row 0).
        if cell.row > 0, cell.row.isMultiple(of: 2) {
            block.backgroundColor = MarkdownTheme.secondaryBackground
        }

        let style = NSMutableParagraphStyle()
        style.textBlocks = [block]
        style.lineSpacing = baseSize * MarkdownTheme.lineSpacingFactor
        if cell.column < cell.columns.count {
            switch cell.columns[cell.column].alignment {
            case .center: style.alignment = .center
            case .right: style.alignment = .right
            default: style.alignment = .natural
            }
        }
        return style
    }

    private mutating func table(for cell: TableCellContext) -> NSTextTable {
        if let existing = tables[cell.tableID] { return existing }
        let table = NSTextTable()
        // Merge adjacent cell borders into single grid lines (GitHub-style)
        // instead of each cell drawing its own four-sided outline.
        table.collapsesBorders = true
        table.numberOfColumns = max(cell.columns.count, 1)
        table.setBorderColor(MarkdownTheme.border)
        table.setWidth(0.5, type: .absoluteValueType, for: .border)
        tables[cell.tableID] = table
        return table
    }
}

// MARK: - Font traits

nonisolated private extension NSFont {
    func withTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(
            fontDescriptor.symbolicTraits.union(trait),
        )
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

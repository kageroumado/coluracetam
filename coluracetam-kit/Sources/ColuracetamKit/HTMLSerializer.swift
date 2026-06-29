import Foundation

/// Serializes a parsed Markdown `AttributedString` into semantic HTML by walking
/// its presentation intents.
///
/// Block structure (headings, lists, code blocks, block quotes, tables) comes
/// from each run's `presentationIntent`; inline emphasis/code/links come from
/// `inlinePresentationIntent` and the `link` attribute. Nested lists are
/// flattened to a single level.
enum HTMLSerializer {
    /// Wraps `body` in a minimal standalone document with an embedded stylesheet.
    static func document(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>
        :root { color-scheme: light dark; }
        body { font: 16px/1.6 -apple-system, system-ui, sans-serif; max-width: 44rem;
               margin: 2rem auto; padding: 0 1rem; }
        h1, h2 { border-bottom: 1px solid color-mix(in srgb, currentColor 15%, transparent);
                 padding-bottom: .3em; }
        code { font-family: ui-monospace, monospace;
               background: color-mix(in srgb, currentColor 8%, transparent);
               padding: .1em .3em; border-radius: 4px; }
        pre { background: color-mix(in srgb, currentColor 6%, transparent);
              padding: 1rem; border-radius: 8px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { margin: 0; padding-left: 1rem;
                     border-left: 3px solid color-mix(in srgb, currentColor 20%, transparent);
                     color: color-mix(in srgb, currentColor 70%, transparent); }
        table { border-collapse: collapse; }
        th, td { border: 1px solid color-mix(in srgb, currentColor 20%, transparent);
                 padding: .4em .7em; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// Emits the `<body>` contents for a parsed document.
    static func body(from attributed: AttributedString) -> String {
        var out = Writer()
        for block in leafBlocks(of: attributed) {
            switch block.kind {
            case let .heading(level):
                out.endContainers()
                out += "<h\(level)>\(block.inlineHTML())</h\(level)>\n"
            case .codeBlock:
                out.endContainers()
                out += "<pre><code>\(escape(block.plainText()))</code></pre>\n"
            case .thematicBreak:
                out.endContainers()
                out += "<hr>\n"
            case let .listItem(listID, ordered):
                out.openList(listID, ordered: ordered)
                out += "<li>\(block.inlineHTML())</li>\n"
            case let .tableCell(tableID, rowID, header):
                out.tableCell(tableID, row: rowID, header: header, inner: block.inlineHTML())
            case .paragraph:
                let inline = block.inlineHTML()
                guard !inline.isEmpty else { continue }
                if block.isQuote {
                    out.quoteParagraph(inline)
                } else {
                    out.endContainers()
                    out += "<p>\(inline)</p>\n"
                }
            }
        }
        out.endContainers()
        return out.html
    }

    // MARK: Output state machine

    /// Accumulates HTML while keeping at most one list/blockquote/table open,
    /// closing them when the block stream moves on.
    private struct Writer {
        var html = ""
        private var openList: (id: Int, ordered: Bool)?
        private var inQuote = false
        private var openTable: Int?
        private var currentRow: Int?

        static func += (writer: inout Writer, text: String) {
            writer.html += text
        }

        mutating func openList(_ id: Int, ordered: Bool) {
            closeQuote(); closeTable()
            if openList?.id != id {
                closeList()
                html += ordered ? "<ol>\n" : "<ul>\n"
                openList = (id, ordered)
            }
        }

        mutating func quoteParagraph(_ inline: String) {
            closeList(); closeTable()
            if !inQuote { html += "<blockquote>\n"; inQuote = true }
            html += "<p>\(inline)</p>\n"
        }

        mutating func tableCell(_ tableID: Int, row: Int, header: Bool, inner: String) {
            closeList(); closeQuote()
            if openTable != tableID {
                closeTable()
                html += "<table>\n"
                openTable = tableID
            }
            if currentRow != row {
                if currentRow != nil { html += "</tr>\n" }
                html += "<tr>\n"
                currentRow = row
            }
            let tag = header ? "th" : "td"
            html += "<\(tag)>\(inner)</\(tag)>\n"
        }

        /// Closes any open list, blockquote, or table.
        mutating func endContainers() {
            closeList(); closeQuote(); closeTable()
        }

        private mutating func closeList() {
            guard let list = openList else { return }
            html += list.ordered ? "</ol>\n" : "</ul>\n"
            openList = nil
        }
        private mutating func closeQuote() {
            guard inQuote else { return }
            html += "</blockquote>\n"
            inQuote = false
        }
        private mutating func closeTable() {
            guard openTable != nil else { return }
            if currentRow != nil { html += "</tr>\n" }
            html += "</table>\n"
            openTable = nil
            currentRow = nil
        }
    }

    // MARK: Leaf blocks

    /// A maximal run of text sharing the same block `presentationIntent`.
    private struct LeafBlock {
        var runs: [(text: String, inline: InlinePresentationIntent, link: URL?)]
        var intent: PresentationIntent?

        enum Kind {
            case heading(Int)
            case paragraph
            case codeBlock
            case thematicBreak
            case listItem(listID: Int, ordered: Bool)
            case tableCell(tableID: Int, rowID: Int, header: Bool)
        }

        var kind: Kind {
            guard let components = intent?.components else { return .paragraph }
            var tableID: Int?, rowID: Int?, isHeaderRow = false, isCell = false
            for c in components {
                switch c.kind {
                case let .header(level): return .heading(min(max(level, 1), 6))
                case .codeBlock: return .codeBlock
                case .thematicBreak: return .thematicBreak
                case .tableCell: isCell = true
                case .tableHeaderRow: isHeaderRow = true; rowID = c.identity
                case .tableRow: rowID = c.identity
                case .table: tableID = c.identity
                default: continue
                }
            }
            if isCell {
                return .tableCell(tableID: tableID ?? 0, rowID: rowID ?? 0, header: isHeaderRow)
            }
            if components.contains(where: { if case .listItem = $0.kind { return true }; return false }) {
                for c in components {
                    if case .unorderedList = c.kind { return .listItem(listID: c.identity, ordered: false) }
                    if case .orderedList = c.kind { return .listItem(listID: c.identity, ordered: true) }
                }
            }
            return .paragraph
        }

        var isQuote: Bool {
            intent?.components.contains { if case .blockQuote = $0.kind { return true }; return false } ?? false
        }

        func plainText() -> String {
            runs.map(\.text).joined()
        }

        /// Renders the runs as inline HTML with emphasis/code/strikethrough/links.
        func inlineHTML() -> String {
            runs.map { run in
                var text = escape(run.text)
                if run.inline.contains(.code) { text = "<code>\(text)</code>" }
                if run.inline.contains(.stronglyEmphasized) { text = "<strong>\(text)</strong>" }
                if run.inline.contains(.emphasized) { text = "<em>\(text)</em>" }
                if run.inline.contains(.strikethrough) { text = "<del>\(text)</del>" }
                if let link = run.link {
                    text = "<a href=\"\(escape(link.absoluteString))\">\(text)</a>"
                }
                return text
            }.joined()
        }
    }

    private static func leafBlocks(of attributed: AttributedString) -> [LeafBlock] {
        var blocks: [LeafBlock] = []
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            let intent = run.presentationIntent
            let inline = run.inlinePresentationIntent ?? []
            let link = run.link

            if var last = blocks.last, intent == last.intent {
                last.runs.append((text, inline, link))
                blocks[blocks.count - 1] = last
            } else {
                blocks.append(LeafBlock(runs: [(text, inline, link)], intent: intent))
            }
        }
        // Drop inter-block gaps: intent-less whitespace runs.
        return blocks.filter {
            !($0.intent == nil && $0.plainText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

/// HTML-escapes text content.
private func escape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        default: out.append(ch)
        }
    }
    return out
}

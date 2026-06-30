import Foundation

/// Reads a *bounded* prefix of a Markdown file for Quick Look previews.
///
/// A Quick Look preview only needs to show the first page or so of a document,
/// but the renderer's cost scales with input length — a multi-megabyte file
/// would read fully into memory and parse in its entirety just to display a
/// screenful. This reads only a leading slice, so preview generation stays fast
/// and bounded regardless of file size. The full document is always available in
/// the app itself.
public enum MarkdownPreviewSource {
    /// The largest prefix, in bytes, that is read from disk. Sized so ordinary
    /// notes and READMEs are shown whole while pathological files stay cheap.
    public static let maxBytes = 256 * 1_024

    /// A hard cap on rendered lines, in case the prefix is many short lines.
    public static let maxLines = 1_200

    /// Reads up to ``maxBytes`` / ``maxLines`` of Markdown from `url`.
    ///
    /// - Returns: The (possibly truncated) source. When truncated, a short
    ///   italic note is appended so the reader knows the preview is partial.
    public static func read(contentsOf url: URL) throws -> String {
        let (text, truncated) = try boundedPrefix(contentsOf: url, maxBytes: maxBytes, maxLines: maxLines)
        guard truncated else { return text }
        return text + "\n\n---\n\n*Preview truncated — open in Coluracetam to read the full document.*\n"
    }

    /// Reads a bounded leading slice of a file via a single `FileHandle` read.
    ///
    /// Shared by the preview and thumbnail paths, which differ only in their
    /// byte/line budgets — a thumbnail needs far less than a preview. Never
    /// loads more than `maxBytes` from disk, so cost is independent of file size.
    ///
    /// - Returns: The sliced text and whether either budget forced a truncation.
    static func boundedPrefix(
        contentsOf url: URL, maxBytes: Int, maxLines: Int,
    ) throws -> (text: String, truncated: Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: maxBytes) ?? Data()
        // Lossy decode is intentional: the byte cap can split a multi-byte UTF-8
        // scalar, and we want a U+FFFD placeholder rather than a nil failure.
        // swiftlint:disable:next optional_data_string_conversion
        var text = String(decoding: data, as: UTF8.self)

        // If we stopped at the byte budget we may have split a line (or a
        // multi-byte scalar via lossy decoding) — drop the trailing partial line.
        var truncated = data.count >= maxBytes
        if truncated, let lastNewline = text.lastIndex(of: "\n") {
            text = String(text[..<lastNewline])
        }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            truncated = true
        }
        return (lines.joined(separator: "\n"), truncated)
    }
}

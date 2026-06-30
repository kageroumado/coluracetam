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
        var result = lines.joined(separator: "\n")

        if truncated {
            result += "\n\n---\n\n*Preview truncated — open in Coluracetam to read the full document.*\n"
        }
        return result
    }
}

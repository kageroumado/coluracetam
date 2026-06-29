# ColuracetamKit

Shared rendering core for Coluracetam, linked by all three targets:

- **Coluracetam** (app) — read/edit window
- **QuickLookPreview** — spacebar preview extension
- **QuickLookThumbnail** — Finder icon-view thumbnails

Keeping the render path in one place guarantees the in-app view and the Finder
preview are byte-for-byte the same.

## Build settings

- Swift tools 6.3, language mode 6 (complete strict concurrency)
- `defaultIsolation(MainActor.self)` — UI module, MainActor by default
- `NonisolatedNonsendingByDefault` upcoming feature

## TODO: pick the Markdown renderer

`MarkdownRenderView` currently uses Foundation's `AttributedString(markdown:)`,
which only renders **inline** styling — no headings, lists, code blocks, or
tables. Replace it before shipping. Options:

| Option | Notes |
| --- | --- |
| **[Textual](https://github.com/gonzalezreal/textual)** ← recommended | Actively-developed SwiftUI text engine; successor to MarkdownUI. `StructuredText` renders headings, lists, code blocks, tables with per-block styling and selection. Newer — pin a version when adding. |
| [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) | Same author, now **maintenance mode**. Battle-tested and fine to ship, but no new development. |
| [swift-markdown](https://github.com/swiftlang/swift-markdown) + custom views | Apple's parser (AST only); render yourself. Most control, most work. Matches Selegiline. |
| [SwiftStreamingMarkdown](https://github.com/microsoft/SwiftStreamingMarkdown) | Geared to incremental/streamed text; overkill for static files. Also used by Selegiline. |

## Wiring into the Xcode project

1. **File ▸ Add Package Dependencies… ▸ Add Local…**, choose this folder.
2. Add the `ColuracetamKit` library to the **Frameworks, Libraries, and Embedded
   Content** of all three targets (app + both extensions).

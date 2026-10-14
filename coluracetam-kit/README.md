# ColuracetamKit

ColuracetamKit shares Markdown parsing and preview between the app and Finder’s Quick Look, with a bounded renderer for thumbnails. It also supplies HTML/PDF export and PDF import through the bundled Rust `ColuracetamPDFCore` library.

[Package manifest](Package.swift)

<details>
<summary>Rendering and export features</summary>

- `MarkdownTextStyler` parses Foundation `AttributedString` and styles its block and inline intents.
- `MarkdownPreviewView` displays styled text in an `NSTextView` with selection, search, links, and viewport layout.
- `MarkdownThumbnail` reads a bounded file prefix and renders it synchronously for the thumbnail extension.

</details>

## Notes

- Swift 6.3; the app and both Quick Look extensions use the `ColuracetamKit` product.
- Rebuild the PDF binary from the repository root with `coluracetam-pdf/build-xcframework.sh`.

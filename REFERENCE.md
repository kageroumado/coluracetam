# coluracetam reference

[Overview](README.md)

## Rendering

`ColuracetamKit` parses Markdown with Foundation’s `AttributedString`. `MarkdownTextStyler` supplies block and inline styling; `MarkdownPreviewView` displays it in an AppKit `NSTextView` shared by the app and Quick Look preview. TextKit lays out the visible region, supports document-wide selection, and supplies the native find bar.

The source editor is a separate AppKit view. Parsing runs off the main actor; edits are debounced and stale results discarded. `MarkdownThumbnail` renders a bounded prefix synchronously for Finder’s thumbnail budget.

## File changes

A `DispatchSource` watch feeds an `AsyncStream` consumed by a SwiftUI `.task`. The watch re-arms after atomic saves replace the inode. Reload applies only while the buffer matches the last disk version, preserving unsaved edits.

## Development notes

- The app and both Quick Look extensions must share a signing team. Renderer tests live in `coluracetam-kit`.

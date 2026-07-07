import SwiftUI

/// A read-only, scrollable view that renders Markdown source as styled rich text.
///
/// This view is the single rendering path shared by the main app's *rendered*
/// mode, the live split's preview pane, and the Quick Look preview extension,
/// so the in-app render and the Finder preview are guaranteed identical.
///
/// Rendering is TextKit-backed (see ``MarkdownReaderView``): one `NSTextView`
/// holds the whole document, giving native document-wide selection, link
/// clicks, the system find bar, and viewport-lazy layout that scales to
/// multi-megabyte documents. Styling mirrors Textual's GitHub preset.
public struct MarkdownRenderView: View {
    private let source: String
    private let scale: CGFloat
    private let showsPlaceholder: Bool
    private let isFindPresented: Binding<Bool>?

    /// Creates a view that renders the given Markdown source string.
    ///
    /// - Parameters:
    ///   - source: The Markdown source to render.
    ///   - scale: A font-size multiplier for reading-comfort zoom. `1` is the
    ///     document's natural size.
    ///   - showsPlaceholder: When `true` (the default), an empty document shows
    ///     a "nothing to preview" placeholder. The live editing split passes
    ///     `false` so the preview pane keeps a stable, full-bleed layout while
    ///     the user types into an empty document — a structural swap here would
    ///     otherwise steal first-responder from the editor on the first keystroke.
    ///   - isFindPresented: Optional binding that shows/hides the native find
    ///     bar, so a toolbar button can drive ⌘F-style find in the preview.
    public init(
        source: String,
        scale: CGFloat = 1,
        showsPlaceholder: Bool = true,
        isFindPresented: Binding<Bool>? = nil,
    ) {
        self.source = source
        self.scale = scale
        self.showsPlaceholder = showsPlaceholder
        self.isFindPresented = isFindPresented
    }

    /// Creates a view by reading Markdown from a file URL.
    ///
    /// Convenience for the Quick Look extensions, which are handed a
    /// sandbox-granted file URL.
    public init(contentsOf url: URL, scale: CGFloat = 1) throws {
        self.init(source: try String(contentsOf: url, encoding: .utf8), scale: scale)
    }

    public var body: some View {
        if showsPlaceholder, source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "Empty Document",
                systemImage: "doc",
                description: Text("There's nothing to preview yet."),
            )
        } else {
            MarkdownReaderView(source: source, scale: scale, isFindPresented: isFindPresented)
        }
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

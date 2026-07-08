import AppKit
import SwiftUI

/// A read-only, scrollable view that renders Markdown source as styled rich text.
///
/// This view is the single rendering path shared by the main app's preview
/// mode, the live split's preview pane, and the Quick Look preview extension,
/// so the in-app preview and the Finder preview are guaranteed identical.
///
/// The whole document lives in one `NSTextView`, which gives native
/// document-wide text selection, link clicks, the system find bar (⌘F with
/// match counts and jump-to), VoiceOver, and viewport-lazy layout — TextKit
/// only lays out what is near the visible rect, so multi-megabyte documents
/// open fast (the same mechanism CotEditor relies on).
///
/// Parsing + styling (the heavyweight step) runs off the main actor via
/// ``MarkdownTextStyler``; edits are debounced and stale results discarded.
/// Hovering a link shows a browser-style URL pill in the bottom-leading
/// corner, rendered here in SwiftUI so it stays glued to the visible viewport
/// (not the document) and picks up Liquid Glass.
public struct MarkdownPreviewView: View {
    private let source: String
    private let scale: CGFloat
    private let showsPlaceholder: Bool
    private let isFindPresented: Binding<Bool>?

    @State private var hoveredLink: URL?

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
    ///   - isFindPresented: Optional two-way binding that shows/hides the
    ///     native find bar, so a toolbar button and the bar itself never drift.
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

    public var body: some View {
        if showsPlaceholder, source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "Empty Document",
                systemImage: "doc",
                description: Text("There's nothing to preview yet."),
            )
        } else {
            PreviewSurface(
                source: source,
                scale: scale,
                isFindPresented: isFindPresented,
                hoveredLink: $hoveredLink,
            )
            .overlay(alignment: .bottomLeading) { linkPill }
        }
    }

    @ViewBuilder
    private var linkPill: some View {
        if let hoveredLink {
            Text(hoveredLink.absoluteString)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)
                .padding(10)
                .frame(maxWidth: 480, alignment: .leading)
                .allowsHitTesting(false)
                // Hover-only chrome; VoiceOver reads links in the text itself.
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }
}

// MARK: - AppKit surface

private struct PreviewSurface: NSViewRepresentable {
    let source: String
    let scale: CGFloat
    let isFindPresented: Binding<Bool>?
    @Binding var hoveredLink: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layoutManager = MarkdownLayoutManager()
        // Lazy, idle-time layout: without this, TextKit lays out the entire
        // document before first paint — the exact cost this view exists to avoid.
        layoutManager.allowsNonContiguousLayout = true
        layoutManager.backgroundLayoutEnabled = true

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude,
        ))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownPreviewTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(
            width: MarkdownTheme.contentInset, height: MarkdownTheme.contentInset,
        )
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.linkTextAttributes = [
            .foregroundColor: MarkdownTheme.link,
            .cursor: NSCursor.pointingHand,
        ]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = FindBarObservingScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.onFindBarVisibilityChange = { [coordinator = context.coordinator] visible in
            coordinator.findBar.visibilityChanged(visible)
        }
        context.coordinator.findBar.isPresented = isFindPresented
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownPreviewTextView else { return }
        textView.linkHoverChanged = { url in hoveredLink = url }
        context.coordinator.findBar.isPresented = isFindPresented
        context.coordinator.setContent(source: source, scale: scale, in: textView)
        if let presented = isFindPresented?.wrappedValue {
            context.coordinator.findBar.sync(presented, in: textView)
        }
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator {
        let findBar = FindBarPresenter()

        private var appliedSource: String?
        private var appliedScale: CGFloat?
        private var generation = 0
        private var restyleTask: Task<Void, Never>?

        /// Styles and applies new content.
        ///
        /// The first render is synchronous so the document is visible the
        /// moment the window (or Quick Look panel) appears; subsequent updates
        /// (typing in the split editor, zoom) restyle off-main behind a small
        /// debounce, and stale results are dropped by generation.
        func setContent(source: String, scale: CGFloat, in textView: NSTextView) {
            guard source != appliedSource || scale != appliedScale else { return }
            let isFirstRender = appliedSource == nil
            appliedSource = source
            appliedScale = scale
            generation += 1
            let generation = generation

            if isFirstRender {
                apply(MarkdownTextStyler.attributedString(markdown: source, scale: scale), to: textView)
                return
            }

            restyleTask?.cancel()
            restyleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let styled = await Self.style(markdown: source, scale: scale)
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.apply(styled, to: textView)
            }
        }

        @concurrent
        private static func style(markdown: String, scale: CGFloat) async -> sending NSAttributedString {
            MarkdownTextStyler.attributedString(markdown: markdown, scale: scale)
        }

        private func apply(_ styled: NSAttributedString, to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            (textView as? MarkdownPreviewTextView)?.prepareForContentReplacement()
            let selected = textView.selectedRange()
            let anchor = firstVisibleCharacter(in: textView)

            textStorage.setAttributedString(styled)

            let length = textStorage.length
            if selected.length > 0, NSMaxRange(selected) <= length {
                textView.setSelectedRange(selected)
            }
            if let anchor, anchor < length {
                textView.scrollRangeToVisible(NSRange(location: anchor, length: 0))
            }
        }

        /// The character index at the top of the viewport, used to keep the
        /// reading position stable across a restyle.
        private func firstVisibleCharacter(in textView: NSTextView) -> Int? {
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  let scrollView = textView.enclosingScrollView
            else { return nil }
            var rect = scrollView.contentView.bounds
            rect.origin.y -= textView.textContainerInset.height
            guard rect.origin.y > 0 else { return nil }
            let glyphs = layoutManager.glyphRange(forBoundingRect: rect, in: container)
            guard glyphs.length > 0 else { return nil }
            return layoutManager.characterIndexForGlyph(at: glyphs.location)
        }
    }
}

#Preview {
    MarkdownPreviewView(source: """
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

import AppKit
import SwiftUI

/// A read-only, TextKit-backed Markdown reader.
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
public struct MarkdownReaderView: View {
    private let source: String
    private let scale: CGFloat
    private let isFindPresented: Binding<Bool>?

    @State private var hoveredLink: URL?

    /// - Parameters:
    ///   - source: Markdown source to render.
    ///   - scale: Reading-comfort font multiplier. `1` is natural size.
    ///   - isFindPresented: Optional two-way binding that shows/hides the
    ///     native find bar, mirroring ``MarkdownSourceEditor``'s pattern so a
    ///     toolbar button and the bar itself never drift.
    public init(source: String, scale: CGFloat = 1, isFindPresented: Binding<Bool>? = nil) {
        self.source = source
        self.scale = scale
        self.isFindPresented = isFindPresented
    }

    public var body: some View {
        ReaderSurface(
            source: source,
            scale: scale,
            isFindPresented: isFindPresented,
            hoveredLink: $hoveredLink,
        )
        .overlay(alignment: .bottomLeading) { linkPill }
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
                .transition(.opacity)
        }
    }
}

// MARK: - AppKit surface

private struct ReaderSurface: NSViewRepresentable {
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

        let textView = MarkdownReaderTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
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

        let scrollView = ReaderFindBarScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.onFindBarVisibilityChange = { [coordinator = context.coordinator] visible in
            coordinator.findBarVisibilityChanged(visible)
        }
        context.coordinator.isFindPresented = isFindPresented
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownReaderTextView else { return }
        textView.linkHoverChanged = { url in hoveredLink = url }
        context.coordinator.isFindPresented = isFindPresented
        context.coordinator.setContent(source: source, scale: scale, in: textView)
        if let presented = isFindPresented?.wrappedValue {
            context.coordinator.syncFind(presented, in: textView)
        }
    }

    /// Matches ``MarkdownSourceEditor``'s 20 pt inset so the reader and the
    /// source pane line up in the split view.
    private static let inset: CGFloat = 20

    // MARK: Coordinator

    @MainActor
    final class Coordinator {
        var isFindPresented: Binding<Bool>?

        private var appliedSource: String?
        private var appliedScale: CGFloat?
        private var generation = 0
        private var restyleTask: Task<Void, Never>?
        private var findShown = false

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
            (textView as? MarkdownReaderTextView)?.prepareForContentReplacement()
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

        // MARK: Find bar

        /// Drives the find bar from shared state (toolbar button / ⌘F).
        func syncFind(_ presented: Bool, in textView: NSTextView) {
            guard presented != findShown else { return }
            findShown = presented
            let item = NSMenuItem()
            item.tag = (
                presented ? NSTextFinder.Action.showFindInterface
                    : NSTextFinder.Action.hideFindInterface
            ).rawValue
            DispatchQueue.main.async { textView.performTextFinderAction(item) }
        }

        /// Reports a visibility change AppKit made itself (e.g. the user
        /// pressing Escape) back into the shared state.
        func findBarVisibilityChanged(_ visible: Bool) {
            guard visible != findShown else { return }
            findShown = visible
            if let binding = isFindPresented, binding.wrappedValue != visible {
                binding.wrappedValue = visible
            }
        }
    }
}

/// An `NSScrollView` that reports find-bar visibility changes — the same
/// mechanism as the source editor's, duplicated here because the text view
/// hosts its find bar in the enclosing scroll view.
private final class ReaderFindBarScrollView: NSScrollView {
    var onFindBarVisibilityChange: (@MainActor (Bool) -> Void)?

    override var isFindBarVisible: Bool {
        get { super.isFindBarVisible }
        set {
            guard newValue != super.isFindBarVisible else { return }
            super.isFindBarVisible = newValue
            onFindBarVisibilityChange?(newValue)
        }
    }
}

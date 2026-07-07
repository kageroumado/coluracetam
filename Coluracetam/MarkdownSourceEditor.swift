import AppKit
import SwiftUI

/// A plain-text editor for Markdown source, used as the lower pane of the live
/// split.
///
/// SwiftUI's `TextEditor` ignores a horizontal content inset, so its text hugs
/// the edge while the rendered preview above is padded 20 pt — the two panes
/// don't line up. This AppKit-backed editor sets the text container inset
/// directly (with zero line-fragment padding) so the source aligns exactly with
/// the rendered text, draws no background so both panes share the window's, and
/// lets the surrounding view drive find and initial focus.
struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    var scale: CGFloat
    /// Two-way binding to the window's shared find state: the toolbar's Find
    /// button shows the editor's find bar, and dismissing the bar (its close
    /// button or the Escape key) clears the flag back, so the two never drift.
    @Binding var isFindPresented: Bool
    /// Whether the line-number ruler is visible.
    var showsLineNumbers = false
    /// A pending go-to-line request; applied once per unique request.
    var lineJump: LineJump?

    /// Matched to ``MarkdownRenderView``'s 20-pt padding so the source text in
    /// this pane lines up with the rendered text above it.
    private static let inset: CGFloat = 20

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFindPresented: $isFindPresented)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.font = Self.font(scale: scale)
        textView.string = text

        let scrollView = FindBarObservingScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.onFindBarVisibilityChange = { [coordinator = context.coordinator] visible in
            coordinator.findBarVisibilityChanged(visible)
        }
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showsLineNumbers
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            (scrollView.verticalRulerView as? LineNumberRulerView)?.invalidateLineIndex()
        }
        if scrollView.rulersVisible != showsLineNumbers {
            scrollView.rulersVisible = showsLineNumbers
        }
        let font = Self.font(scale: scale)
        if textView.font != font { textView.font = font }
        context.coordinator.focusIfNeeded(textView)
        context.coordinator.syncFind(isFindPresented, in: textView)
        if let lineJump {
            context.coordinator.applyIfNeeded(lineJump, in: textView)
        }
    }

    private static func font(scale: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: NSFont.systemFontSize * scale, weight: .regular)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private let isFindPresented: Binding<Bool>
        private var didFocus = false
        /// Our view of whether the find bar is on screen, kept in step with both
        /// the binding (writes) and AppKit's own visibility changes (reads), so
        /// neither path re-issues a redundant show/hide.
        private var findShown = false

        init(text: Binding<String>, isFindPresented: Binding<Bool>) {
            self.text = text
            self.isFindPresented = isFindPresented
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?
                .invalidateLineIndex()
        }

        private var appliedJump: LineJump?

        /// Selects and reveals the requested line (clamped to the last line),
        /// once per unique request.
        func applyIfNeeded(_ jump: LineJump, in textView: NSTextView) {
            guard jump != appliedJump else { return }
            appliedJump = jump

            let string = textView.string as NSString
            var range = NSRange(location: 0, length: 0)
            var line = 1
            if string.length > 0 {
                range = string.lineRange(for: NSRange(location: 0, length: 0))
                while line < jump.line, NSMaxRange(range) < string.length {
                    range = string.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
                    line += 1
                }
            }
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.window?.makeFirstResponder(textView)
        }

        /// Makes the editor first responder once it has a window, so a freshly
        /// opened (empty) document is ready to type into without a click.
        func focusIfNeeded(_ textView: NSTextView) {
            guard !didFocus, textView.window != nil else { return }
            didFocus = true
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }

        /// Drives the find bar from the shared find state (toolbar / ⌘F).
        func syncFind(_ presented: Bool, in textView: NSTextView) {
            guard presented != findShown else { return }
            findShown = presented
            let item = NSMenuItem()
            item.tag = (
                presented ? NSTextFinder.Action.showFindInterface
                    : NSTextFinder.Action.hideFindInterface,
            ).rawValue
            DispatchQueue.main.async { textView.performTextFinderAction(item) }
        }

        /// Reports a find-bar visibility change that AppKit made itself — most
        /// importantly the user dismissing the bar — back into the shared state.
        func findBarVisibilityChanged(_ visible: Bool) {
            guard visible != findShown else { return }
            findShown = visible
            if isFindPresented.wrappedValue != visible {
                isFindPresented.wrappedValue = visible
            }
        }
    }
}

/// An `NSScrollView` that reports find-bar visibility changes.
///
/// `NSTextView` hosts its find bar in the enclosing scroll view (its
/// `NSTextFinderBarContainer`), so overriding the visibility setter is the one
/// place that sees *every* change — including the user closing the bar — which
/// the text view otherwise keeps to itself.
private final class FindBarObservingScrollView: NSScrollView {
    var onFindBarVisibilityChange: (@MainActor (Bool) -> Void)?

    override var isFindBarVisible: Bool {
        get { super.isFindBarVisible }
        set {
            guard newValue != super.isFindBarVisible else { return }
            super.isFindBarVisible = newValue
            onFindBarVisibilityChange?(newValue)
        }
    }

    /// The scroll view underlaps the title bar (content scrolls beneath the
    /// toolbar, offset via automatic content insets), but `tile()` places the
    /// ruler over the full frame height — under the traffic lights. Push it
    /// down to start at the content inset instead.
    override func tile() {
        super.tile()
        guard rulersVisible, let ruler = verticalRulerView else { return }
        let top = contentInsets.top
        guard top > 0, ruler.frame.minY < top else { return }
        ruler.frame = NSRect(
            x: ruler.frame.minX,
            y: top,
            width: ruler.frame.width,
            height: max(0, frame.height - top),
        )
    }
}

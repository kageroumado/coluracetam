import AppKit
import ColuracetamKit
import SwiftUI

/// A plain-text editor for Markdown source, used as the lower pane of the live
/// split.
///
/// SwiftUI's `TextEditor` ignores a horizontal content inset, so its text hugs
/// the edge while the rendered preview above is padded — the two panes don't
/// line up. This AppKit-backed editor applies ``MarkdownTheme/contentInset``
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
        textView.textContainerInset = NSSize(
            width: MarkdownTheme.contentInset, height: MarkdownTheme.contentInset,
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.font = Self.font(scale: scale)
        textView.string = text

        let scrollView = EditorScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.onFindBarVisibilityChange = { [coordinator = context.coordinator] visible in
            coordinator.findBar.visibilityChanged(visible)
        }
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showsLineNumbers
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Skip the O(document) text comparison when this update is just the
        // text view's own edit echoing back through the binding.
        if !context.coordinator.consumePendingEcho(), textView.string != text {
            textView.string = text
            (scrollView.verticalRulerView as? LineNumberRulerView)?.invalidateLineIndex()
        }
        if scrollView.rulersVisible != showsLineNumbers {
            scrollView.rulersVisible = showsLineNumbers
        }
        let font = Self.font(scale: scale)
        if textView.font != font { textView.font = font }
        context.coordinator.focusIfNeeded(textView)
        context.coordinator.findBar.sync(isFindPresented, in: textView)
        if let lineJump {
            context.coordinator.applyIfNeeded(lineJump, in: textView)
        }
    }

    private static func font(scale: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: NSFont.systemFontSize * scale, weight: .regular)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let findBar = FindBarPresenter()

        private let text: Binding<String>
        private var didFocus = false
        /// Set when the buffer write originated from this text view, so the
        /// next SwiftUI update pass can skip comparing the buffer against its
        /// own text.
        private var pendingEcho = false

        init(text: Binding<String>, isFindPresented: Binding<Bool>) {
            self.text = text
            findBar.isPresented = isFindPresented
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            pendingEcho = true
            text.wrappedValue = textView.string
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?
                .invalidateLineIndex()
        }

        /// Returns whether an edit echo was pending, clearing it either way.
        func consumePendingEcho() -> Bool {
            defer { pendingEcho = false }
            return pendingEcho
        }

        private var appliedJump: LineJump?

        /// Selects and reveals the requested line (clamped to the last line),
        /// once per unique request. Line lookup reuses the ruler's index.
        func applyIfNeeded(_ jump: LineJump, in textView: NSTextView) {
            guard jump != appliedJump else { return }
            appliedJump = jump

            let ruler = textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView
            let range = ruler?.characterRange(ofLine: jump.line)
                ?? LineIndex(string: textView.string).characterRange(ofLine: jump.line)
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
    }
}

/// The editor's scroll view: the kit's find-bar reporting, plus ruler
/// placement that respects the title-bar underlap.
private final class EditorScrollView: FindBarObservingScrollView {
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

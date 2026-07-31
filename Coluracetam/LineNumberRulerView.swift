import AppKit

/// A vertical ruler that draws line numbers for an `NSTextView`.
///
/// Numbers are per *logical* line (hard line breaks); a wrapped paragraph is
/// numbered once. Geometry comes from the TextKit 2 layout fragments that
/// intersect the viewport, so cost scales with what's visible, not with the
/// document. Line starts are indexed once per edit.
///
/// Clicking a line number selects that whole line; dragging extends the
/// selection over every line the drag sweeps (in either direction).
final class LineNumberRulerView: NSRulerView {
    private var lineIndex = LineIndex()
    private var lineIndexIsStale = true
    /// The line range where a ruler drag began, unioned with the line under
    /// the cursor as the drag moves.
    private var dragAnchor: NSRange?

    private var textView: NSTextView? {
        clientView as? NSTextView
    }

    init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Marks the line index stale after an edit. O(1) — the O(text length)
    /// re-index happens lazily on the next lookup, so typing with the ruler
    /// hidden never pays for it.
    func invalidateLineIndex() {
        lineIndexIsStale = true
        needsDisplay = true
    }

    /// The character range of `line` (1-based, clamped to the last line).
    /// Shared with go-to-line so it reuses the ruler's index.
    func characterRange(ofLine line: Int) -> NSRange {
        ensureLineIndex()
        return lineIndex.characterRange(ofLine: line)
    }

    private func ensureLineIndex() {
        guard lineIndexIsStale, let string = textView?.string else { return }
        lineIndexIsStale = false
        lineIndex = LineIndex(string: string)

        let digits = max(2, String(lineIndex.lineCount).count)
        let thickness = CGFloat(digits) * Self.digitWidth + Self.padding * 2
        if ruleThickness != thickness {
            // Setting `ruleThickness` retiles the scroll view, which resizes
            // the width-tracking text container. Doing that here — this runs
            // inside `drawHashMarksAndLabels`, mid TextKit 2 layout pass —
            // invalidates the freshly computed layout, and the full-document
            // height estimation never reruns: the text view's frame stays at
            // viewport height and the editor cannot scroll at all. Defer the
            // retile until after the draw pass.
            DispatchQueue.main.async { [self] in
                if ruleThickness != thickness { ruleThickness = thickness }
            }
        }
    }

    /// `NSRulerView`'s default drawing paints a background and a hairline along
    /// the ruler's edge for the ruler's full height — chrome that reads as
    /// noise next to a background-less editor. Draw only the labels; the 6-pt
    /// padding on either side separates the gutter from the text on its own.
    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override var isOpaque: Bool { false }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return }
        ensureLineIndex()

        let visible = textView.visibleRect
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .regular,
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        // Walk only the layout fragments intersecting the viewport.
        let origin = NSPoint(x: visible.minX, y: max(visible.minY, 0))
        guard let startFragment = layoutManager.textLayoutFragment(for: origin) else { return }
        layoutManager.enumerateTextLayoutFragments(
            from: startFragment.rangeInElement.location,
            options: [.ensuresLayout],
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard frame.minY < visible.maxY else { return false }

            let offset = contentManager.offset(
                from: contentManager.documentRange.location,
                to: fragment.rangeInElement.location,
            )
            let line = lineIndex.lineNumber(forCharacterAt: offset)
            let label = NSAttributedString(string: "\(line)", attributes: attributes)
            let size = label.size()

            // Fragment frame → text view coords (inset) → ruler coords.
            let textViewPoint = NSPoint(
                x: 0,
                y: frame.minY + textView.textContainerInset.height,
            )
            let rulerPoint = convert(textViewPoint, from: textView)
            label.draw(at: NSPoint(
                x: ruleThickness - size.width - Self.padding,
                y: rulerPoint.y + (font.pointSize * 0.18),
            ))
            return true
        }
    }

    // MARK: Line selection

    override func mouseDown(with event: NSEvent) {
        guard let range = lineCharacterRange(for: event), let textView else { return }
        defer { textView.window?.makeFirstResponder(textView) }

        if event.modifierFlags.contains(.command) {
            // Toggle this line in/out of a (possibly discontiguous) selection.
            dragAnchor = nil
            var ranges = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
            if let existing = ranges.firstIndex(of: range) {
                ranges.remove(at: existing)
            } else {
                ranges.append(range)
            }
            if ranges.isEmpty {
                textView.setSelectedRange(NSRange(location: range.location, length: 0))
            } else {
                textView.selectedRanges = ranges.map { NSValue(range: $0) }
            }
            return
        }
        if event.modifierFlags.contains(.shift) {
            // Extend from the current selection to the clicked line.
            let union = NSUnionRange(textView.selectedRange(), range)
            dragAnchor = union
            textView.setSelectedRange(union)
            return
        }
        dragAnchor = range
        textView.setSelectedRange(range)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragAnchor, let current = lineCharacterRange(for: event) else { return }
        textView?.setSelectedRange(NSUnionRange(dragAnchor, current))
        textView?.autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragAnchor = nil
    }

    /// The full character range of the logical line at the event's height.
    private func lineCharacterRange(for event: NSEvent) -> NSRange? {
        guard let textView,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return nil }
        let pointInTextView = textView.convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: 0,
            y: pointInTextView.y - textView.textContainerInset.height,
        )
        guard let fragment = layoutManager.textLayoutFragment(for: containerPoint) else { return nil }
        let offset = contentManager.offset(
            from: contentManager.documentRange.location,
            to: fragment.rangeInElement.location,
        )
        let string = textView.string as NSString
        guard offset <= string.length else { return nil }
        return string.lineRange(for: NSRange(location: offset, length: 0))
    }

    private static let digitWidth: CGFloat = 7
    private static let padding: CGFloat = 6
}

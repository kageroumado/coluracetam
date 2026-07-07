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
    private var lineStarts: [Int] = [0]
    /// The line range where a ruler drag began, unioned with the line under
    /// the cursor as the drag moves.
    private var dragAnchor: NSRange?

    private var textView: NSTextView? {
        clientView as? NSTextView
    }

    init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        invalidateLineIndex()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Re-indexes line starts after an edit. O(text length), run per change.
    func invalidateLineIndex() {
        guard let string = textView?.string else { return }
        var starts: [Int] = [0]
        let ns = string as NSString
        var index = 0
        while index < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            index = NSMaxRange(lineRange)
            if index < ns.length { starts.append(index) }
        }
        lineStarts = starts

        let digits = max(2, String(starts.count).count)
        ruleThickness = CGFloat(digits) * Self.digitWidth + Self.padding * 2
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return }

        let visible = textView.visibleRect
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .regular,
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor,
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
            let line = lineNumber(forCharacterAt: offset)
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

    private func lineNumber(forCharacterAt offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    private static let digitWidth: CGFloat = 7
    private static let padding: CGFloat = 6
}

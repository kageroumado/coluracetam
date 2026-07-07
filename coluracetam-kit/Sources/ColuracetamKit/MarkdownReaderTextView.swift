import AppKit

/// The reader's text view: adds hover affordances on top of `NSTextView` —
/// a copy button on code blocks and a browser-style URL pill for links.
///
/// Both affordances are driven by mouse tracking against TextKit geometry:
/// the character under the cursor is resolved through the layout manager and
/// its attributes decide what to show. The copy button lives inside the text
/// view (it belongs to a chip and scrolls with it); the URL pill is pinned to
/// the enclosing scroll view's bottom-left like a browser status pill.
final class MarkdownReaderTextView: NSTextView {
    /// Reports the link under the mouse (or `nil`), for a browser-style URL
    /// pill rendered by the SwiftUI layer — called only on changes.
    var linkHoverChanged: ((URL?) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private var copyableRange: NSRange?
    private var restoreCopyIconTask: Task<Void, Never>?
    private var hoveredLink: URL?

    // MARK: Overlay views

    private lazy var copyButton: NSButton = {
        let button = NSButton(
            image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy code")!,
            target: self,
            action: #selector(copyCodeBlock),
        )
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Copy code"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var copyButtonHost: NSGlassEffectView = {
        let glass = NSGlassEffectView()
        glass.cornerRadius = Self.copyButtonSize / 2
        glass.contentView = copyButton
        glass.isHidden = true
        addSubview(glass)
        return glass
    }()

    private static let copyButtonSize: CGFloat = 26

    // MARK: Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        updateCopyButton(at: point)
        updateLinkPill(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        copyButtonHost.isHidden = true
        copyableRange = nil
        setLinkPill(url: nil)
    }

    /// Hides hover chrome; called when the content is about to be replaced.
    func prepareForContentReplacement() {
        copyButtonHost.isHidden = true
        copyableRange = nil
        setLinkPill(url: nil)
    }

    // MARK: Code block copy button

    private func updateCopyButton(at point: NSPoint) {
        guard let layoutManager, let textContainer, let textStorage,
              textStorage.length > 0
        else { return }
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height,
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length else { return hideCopyButton() }

        var blockRange = NSRange()
        let isCode = textStorage.attribute(
            .markdownCodeBlock, at: charIndex, longestEffectiveRange: &blockRange,
            in: NSRange(location: 0, length: textStorage.length),
        ) != nil
        guard isCode else { return hideCopyButton() }

        // The chip spans the container's full width, taller than its text by
        // the drawn padding — accept hover anywhere on it, not just on glyphs.
        let glyphRange = layoutManager.glyphRange(forCharacterRange: blockRange, actualCharacterRange: nil)
        let text = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let chip = MarkdownTheme.codeChipRect(
            textRect: text, containerWidth: textContainer.size.width,
        )
        guard chip.contains(containerPoint) else { return hideCopyButton() }

        copyableRange = blockRange
        let size = Self.copyButtonSize
        copyButtonHost.frame = NSRect(
            x: textContainerInset.width + chip.maxX - size - 8,
            y: textContainerInset.height + chip.minY + 8,
            width: size,
            height: size,
        )
        copyButton.frame = copyButtonHost.bounds
        copyButtonHost.isHidden = false
    }

    private func hideCopyButton() {
        copyButtonHost.isHidden = true
        copyableRange = nil
    }

    @objc private func copyCodeBlock() {
        guard let copyableRange, let textStorage else { return }
        let code = textStorage.attributedSubstring(from: copyableRange).string
            .trimmingCharacters(in: .newlines)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        copyButton.contentTintColor = .systemGreen
        restoreCopyIconTask?.cancel()
        restoreCopyIconTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self else { return }
            self.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy code")
            self.copyButton.contentTintColor = .secondaryLabelColor
        }
    }

    // MARK: Link URL pill

    private func updateLinkPill(at point: NSPoint) {
        guard let layoutManager, let textContainer, let textStorage,
              textStorage.length > 0
        else { return }
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height,
        )
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction,
        )
        // `glyphIndex(for:)` snaps to the nearest glyph; require a real hit so
        // hovering empty space past a line doesn't light up its trailing link.
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer,
        )
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard glyphRect.insetBy(dx: -1, dy: -1).contains(containerPoint),
              charIndex < textStorage.length,
              let url = textStorage.attribute(.link, at: charIndex, effectiveRange: nil)
        else { return setLinkPill(url: nil) }

        setLinkPill(url: url as? URL ?? (url as? String).flatMap(URL.init(string:)))
    }

    private func setLinkPill(url: URL?) {
        guard url != hoveredLink else { return }
        hoveredLink = url
        linkHoverChanged?(url)
    }
}

import AppKit
import Testing
@testable import ColuracetamKit

/// Performance guardrails for the TextKit render pipeline on a large document.
///
/// These bound the two costs that made the previous SwiftUI pipeline choke:
/// producing the styled string (must be background-friendly and fast enough
/// for a debounce window), and first-paint layout (must be viewport-lazy, not
/// whole-document).
@MainActor
@Suite("Preview performance")
struct MarkdownPreviewPerformanceTests {
    /// ~400 KB / ~8k lines of heading/list/code/table/quote-heavy Markdown,
    /// mirroring the benchmark file from the profiling session.
    private static let heavyDocument: String = {
        var parts: [String] = []
        for index in 0 ..< 300 {
            parts.append("## Section \(index)\n")
            parts.append(String(repeating: "render markdown preview swift textual layout attribute string ", count: 6) + "\n")
            parts.append("Some **bold** and _italic_ and `inline code` and a [link](https://example.com/\(index)).\n")
            parts.append((0 ..< 6).map { "- item \($0) with words and `code`" }.joined(separator: "\n") + "\n")
            parts.append("```swift\nfunc section\(index)() -> Int {\n    let value = \(index) * 42\n    return value\n}\n```\n")
            parts.append("| Column A | Column B | Column C |\n|---|---|---|\n| a\(index) | b\(index) | c\(index) |\n| d\(index) | e\(index) | f\(index) |\n")
            parts.append("> a block quote with a reasonable amount of quoted prose in it\n")
        }
        return parts.joined(separator: "\n")
    }()

    @Test
    func `styling a 400KB document stays within the debounce budget`() {
        let clock = ContinuousClock()
        let duration = clock.measure {
            _ = MarkdownTextStyler.attributedString(markdown: Self.heavyDocument)
        }
        print("styler: \(Self.heavyDocument.utf8.count / 1024) KB in \(duration)")
        // Off-main work, but it bounds split-mode typing latency; a generous
        // ceiling that still catches an accidental return to pathological cost.
        #expect(duration < .seconds(5))
    }

    @Test
    func `first-paint layout is viewport-lazy, not whole-document`() {
        let styled = MarkdownTextStyler.attributedString(markdown: Self.heavyDocument)

        let layoutManager = MarkdownLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let textStorage = NSTextStorage(attributedString: styled)
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let clock = ContinuousClock()
        let viewportDuration = clock.measure {
            _ = layoutManager.glyphRange(
                forBoundingRect: NSRect(x: 0, y: 0, width: 760, height: 1_000),
                in: container,
            )
        }
        print("viewport layout: \(viewportDuration)")
        #expect(viewportDuration < .seconds(1))
        #expect(layoutManager.hasNonContiguousLayout)
    }
}

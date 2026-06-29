import Foundation
import SwiftUI
import Testing
@testable import ColuracetamKit

@MainActor
@Suite("Find match counting")
struct MatchCountTests {
    static let doc = """
    # Clarity
    
    The word clarity appears here. Seeking clarity in the contrast — clarity again.
    
    - clarity in lists
    - something else
    """

    @Test
    func `counts rendered occurrences, case-insensitively`() {
        // "Clarity" (heading) + clarity ×4 in prose/list = 5.
        #expect(MarkdownRenderView.matchCount(in: Self.doc, of: "clarity") == 5)
        #expect(MarkdownRenderView.matchCount(in: Self.doc, of: "CLARITY") == 5)
        #expect(MarkdownRenderView.matchCount(in: Self.doc, of: "nope") == 0)
        #expect(MarkdownRenderView.matchCount(in: Self.doc, of: "") == 0)
    }

    @Test
    func `matches rendered text, not markdown syntax`() {
        // The asterisks of **bold** are not in the rendered text.
        #expect(MarkdownRenderView.matchCount(in: "a **bold** word", of: "*") == 0)
        #expect(MarkdownRenderView.matchCount(in: "a **bold** word", of: "bold") == 1)
    }

    @Test
    func `highlighting parser paints exactly the matched ranges`() throws {
        let parser = HighlightingMarkdownParser(term: "clarity")
        let attributed = try parser.attributedString(
            for: "Find clarity, then more clarity, but not other text.",
        )
        let highlighted = attributed.runs.compactMap { run -> String? in
            run.backgroundColor == nil ? nil : String(attributed[run.range].characters)
        }
        // Exactly the two occurrences are highlighted; nothing else is.
        #expect(highlighted == ["clarity", "clarity"])
    }
}

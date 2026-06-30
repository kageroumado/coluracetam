import AppKit
import Testing
@testable import ColuracetamKit

@Suite("MarkdownThumbnail")
struct MarkdownThumbnailTests {
    private let sample = """
    # Big Heading
    
    This is a **markdown** paragraph with some text.
    
    - item one
    - item two
    
    ```swift
    let clarity = true
    ```
    
    ## Second section
    
    More body text.
    """

    @Test(arguments: [64, 128, 256, 512] as [CGFloat])
    func `Produces a non-empty image across thumbnail sizes`(side: CGFloat) {
        let image = MarkdownThumbnail.image(
            source: sample, size: CGSize(width: side, height: side), displayScale: 2,
        )
        #expect(image != nil)
        #expect(image.map { $0.size.width > 0 && $0.size.height > 0 } == true)
    }

    @Test
    func `Returns nil for an empty document`() {
        let image = MarkdownThumbnail.image(
            source: "   \n\n  ", size: CGSize(width: 128, height: 128), displayScale: 2,
        )
        #expect(image == nil)
    }
}

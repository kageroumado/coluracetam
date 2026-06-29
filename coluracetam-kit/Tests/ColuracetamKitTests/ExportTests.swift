import Foundation
import Testing
@testable import ColuracetamKit

@MainActor
@Suite("Markdown export")
struct ExportTests {
    static let sample = """
    # Daily Brief
    
    A short **intro** with _emphasis_, `inline code`, and a [link](https://example.com).
    
    ## Tasks
    
    - first item
    - second item with **bold**
    - third item
    
    1. step one
    2. step two
    
    > A quoted line.
    > Still quoted.
    
    ```swift
    let clarity = true
    ```
    
    | Name | Role |
    | --- | --- |
    | Sora | sky |
    | Kiri | taste |
    
    ---
    
    Closing paragraph.
    """

    @Test
    func `HTML is semantic and well-formed`() throws {
        let html = MarkdownExport.html(source: Self.sample, title: "Daily Brief")
        let dir = ProcessInfo.processInfo.environment["SCRATCH"] ?? NSTemporaryDirectory()
        try html.write(toFile: dir + "/export-sample.html", atomically: true, encoding: .utf8)

        #expect(html.contains("<h1>Daily Brief</h1>"))
        #expect(html.contains("<h2>Tasks</h2>"))
        #expect(html.contains("<ul>"))
        #expect(html.contains("<ol>"))
        #expect(html.contains("<li>first item</li>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<em>emphasis</em>"))
        #expect(html.contains("<code>inline code</code>"))
        #expect(html.contains("<a href=\"https://example.com\">link</a>"))
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("<pre><code>"))
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>Name</th>"))
        #expect(html.contains("<td>Sora</td>"))
        #expect(html.contains("<hr>"))
    }

    @Test
    func `PDF renders with content`() throws {
        let data = try #require(MarkdownExport.pdf(source: Self.sample))
        #expect(data.count > 1_000)
        let dir = ProcessInfo.processInfo.environment["SCRATCH"] ?? NSTemporaryDirectory()
        try data.write(to: URL(fileURLWithPath: dir + "/export-sample.pdf"))
    }
}

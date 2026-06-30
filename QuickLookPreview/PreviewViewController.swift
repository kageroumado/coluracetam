import Cocoa
import ColuracetamKit
import Quartz
import SwiftUI

class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Only a bounded prefix reaches the renderer — a preview needs ~one page,
        // not a full multi-megabyte parse. See `MarkdownPreviewSource`.
        let source = try MarkdownPreviewSource.read(contentsOf: url)
        let hosting = NSHostingController(rootView: MarkdownRenderView(source: source))
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

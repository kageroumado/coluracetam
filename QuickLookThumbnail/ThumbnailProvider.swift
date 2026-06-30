import AppKit
import ColuracetamKit
import QuickLookThumbnailing

class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void,
    ) {
        let url = request.fileURL
        let maximumSize = request.maximumSize
        let scale = request.scale
        // The reply must be rendered on the main actor (ImageRenderer/SwiftUI).
        // `handler` is a non-Sendable callback we invoke exactly once from that
        // task and never touch again, so transferring it in is race-free.
        nonisolated(unsafe) let handler = handler

        Task { @MainActor in
            // Reads only a bounded prefix of the file (see MarkdownThumbnail.maxBytes)
            // rather than loading the whole document into the memory-limited XPC.
            guard let image = MarkdownThumbnail.image(
                contentsOf: url, size: maximumSize, displayScale: scale,
            )
            else {
                // Hand back nothing so Finder falls back to the generic icon.
                handler(nil, nil)
                return
            }

            let reply = QLThumbnailReply(contextSize: maximumSize, currentContextDrawing: {
                // The page is rendered large and drawn down — ask for a quality
                // downscale so shrunken text stays legible rather than aliased.
                NSGraphicsContext.current?.imageInterpolation = .high
                image.draw(in: CGRect(origin: .zero, size: maximumSize))
                return true
            })
            handler(reply, nil)
        }
    }
}

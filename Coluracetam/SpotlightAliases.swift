import CoreSpotlight
import os

/// Makes Spotlight find the app by what it *is*, not just its name.
///
/// Spotlight's built-in app results only match an app's name, so searching
/// "text editor" would never surface Coluracetam. Indexing a Core Spotlight
/// item that represents the app itself — title, description, and honest
/// keyword aliases — fills that gap; activating the result launches the app.
/// Re-indexed on every launch since searchable items expire.
enum SpotlightAliases {
    private static let identifier = "glass.kagerou.coluracetam.app-alias"

    static func index() {
        let attributes = CSSearchableItemAttributeSet(contentType: .application)
        attributes.title = "Coluracetam"
        attributes.contentDescription = "A simple, fast, native Markdown editor"
        attributes.keywords = ["text editor", "markdown editor", "markdown", "editor", "plain text"]

        let item = CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: identifier,
            attributeSet: attributes,
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                Logger(subsystem: "glass.kagerou.coluracetam", category: "spotlight")
                    .error("Alias indexing failed: \(error.localizedDescription)")
            }
        }
    }
}

import AppIntents
import AppKit
import UniformTypeIdentifiers

/// "Create Markdown Document" for Shortcuts, Spotlight, and Finder Quick
/// Actions: with a folder, creates and opens a uniquely named document there
/// (optionally seeded with content); without one, opens a new unsaved
/// document.
struct CreateMarkdownDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Markdown Document"
    static let description = IntentDescription(
        "Creates a new Markdown document, optionally inside a folder and with initial content.",
        categoryName: "Documents",
    )
    /// Document windows only exist in the foreground app.
    static let openAppWhenRun = true

    @Parameter(
        title: "Folder",
        description: "Where to create the document. Leave empty to open an unsaved untitled document instead.",
        supportedContentTypes: [.folder],
    )
    var folder: IntentFile?

    @Parameter(title: "Initial Content", description: "Text the new document starts with.")
    var content: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        NSApp.activate()
        guard let folderURL = folder?.fileURL else {
            ServiceProvider.pendingText = content
            NSDocumentController.shared.newDocument(nil)
            return .result()
        }

        let scoped = folderURL.startAccessingSecurityScopedResource()
        defer { if scoped { folderURL.stopAccessingSecurityScopedResource() } }
        let url = try ServiceProvider.createDocument(in: folderURL, contents: content ?? "")
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        return .result()
    }
}

/// Surfaces the intent in Spotlight and Siri with app-name phrases.
struct ColuracetamAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateMarkdownDocumentIntent(),
            phrases: [
                "Create a Markdown document in \(.applicationName)",
                "New \(.applicationName) document",
            ],
            shortTitle: "New Document",
            systemImageName: "doc.badge.plus",
        )
    }
}

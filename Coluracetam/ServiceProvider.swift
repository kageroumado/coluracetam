import AppKit
import UniformTypeIdentifiers

/// Registers the app's Finder services as early as possible — the system can
/// deliver a service message immediately after launch when the service itself
/// started the app — and provides the Dock icon's context menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = ServiceProvider()

    func applicationWillFinishLaunching(_: Notification) {
        NSApp.servicesProvider = services

        // Testing hook: launch with `-ForcedAppearance dark|light` to pin the
        // app's appearance (screenshots, theme checks) without changing the
        // system-wide setting.
        if let forced = UserDefaults.standard.string(forKey: "ForcedAppearance") {
            NSApp.appearance = NSAppearance(named: forced == "dark" ? .darkAqua : .aqua)
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        SpotlightAliases.index()
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let newDocument = NSMenuItem(
            title: "New Document",
            action: #selector(NSDocumentController.newDocument(_:)),
            keyEquivalent: "",
        )
        newDocument.target = NSDocumentController.shared
        menu.addItem(newDocument)
        return menu
    }
}

/// Handles the "New Markdown Document at Folder" Finder service (declared in
/// Info.plist): right-clicking a folder creates an empty, uniquely named
/// Markdown file there and opens it for editing — the same pattern as
/// Terminal's "New Terminal at Folder".
///
/// Sandbox note: items sent to a service carry the same access grants as a
/// drag and drop, so the user-selected read-write entitlement covers creating
/// the file inside the received folder.
final class ServiceProvider: NSObject {
    /// Text handed off to the next untitled document, for flows that create an
    /// unsaved document with content (the selection service, the App Intent).
    /// `ContentView` consumes it when an empty document appears —
    /// ``DocumentGroup`` offers no direct way to seed an untitled document.
    static var pendingText: String?

    /// Returns and clears ``pendingText``.
    static func takePendingText() -> String? {
        defer { pendingText = nil }
        return pendingText
    }

    /// Creates a uniquely named Markdown document in `folder` and returns its
    /// URL. Shared by the folder service and the App Intent.
    static func createDocument(in folder: URL, contents: String = "") throws -> URL {
        let url = uniqueDocumentURL(in: folder)
        try Data(contents.utf8).write(to: url, options: .withoutOverwriting)
        return url
    }

    @objc
    func newMarkdownDocumentAtFolder(
        _ pasteboard: NSPasteboard,
        userData _: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>,
    ) {
        guard let folder = folderURL(from: pasteboard) else {
            error.pointee = "No folder was provided."
            return
        }
        let url: URL
        do {
            url = try Self.createDocument(in: folder)
        } catch let writeError {
            error.pointee = "Could not create the document: \(writeError.localizedDescription)" as NSString
            return
        }

        NSApp.activate()
        NSDocumentController.shared.openDocument(
            withContentsOf: url, display: true,
        ) { _, _, _ in }
    }

    /// TextEdit-style: the selected text in any app becomes a new, unsaved
    /// document.
    @objc
    func newMarkdownDocumentWithSelection(
        _ pasteboard: NSPasteboard,
        userData _: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>,
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text was provided."
            return
        }
        Self.pendingText = text
        NSApp.activate()
        NSDocumentController.shared.newDocument(nil)
    }

    private func folderURL(from pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true],
        ) as? [URL]
        return urls?.first {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    /// "Untitled.md" in `folder`, or "Untitled 2.md", "Untitled 3.md", … if
    /// taken — Finder's own naming convention for duplicates.
    private static func uniqueDocumentURL(in folder: URL) -> URL {
        let base = "Untitled"
        var url = folder.appendingPathComponent("\(base).md")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(counter).md")
            counter += 1
        }
        return url
    }
}

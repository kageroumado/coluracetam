import AppKit
import ColuracetamKit
import SwiftUI

/// How a document window presents its content.
enum ViewMode: String, CaseIterable {
    /// Rendered document only.
    case preview
    /// Rendered document above the source editor.
    case split
    /// Source editor only.
    case edit
}

struct ContentView: View {
    @Binding var document: ColuracetamDocument
    @Environment(\.documentConfiguration) private var documentConfiguration
    @AppStorage("showsLineNumbers") private var showsLineNumbers = false

    @State private var workspace = DocumentWorkspace()
    @State private var mode: ViewMode
    /// The text last known to be on disk — the baseline for deciding whether the
    /// buffer has unsaved edits when an external change arrives.
    @State private var lastDiskText: String

    init(document: Binding<ColuracetamDocument>) {
        _document = document
        // A new or empty document has nothing to preview, so open ready to type.
        _mode = State(initialValue: document.wrappedValue.text.isEmpty ? .split : .preview)
        _lastDiskText = State(initialValue: document.wrappedValue.text)
    }

    private var fileURL: URL? {
        documentConfiguration?.fileURL
    }

    var body: some View {
        @Bindable var workspace = workspace
        content
            // Floor for window resizing: below this the layout (toolbar,
            // split panes, insets) stops making sense.
            .frame(minWidth: 160, minHeight: 160)
            .toolbar { toolbarContent }
            .alert("Go to Line", isPresented: $workspace.isGoToLinePresented) {
                TextField("Line number", text: $workspace.goToLineText)
                Button("Go") { goToLine() }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            }
            .focusedSceneValue(\.documentWorkspace, workspace)
            .onChange(of: document.text) { _, text in
                workspace.source = text
            }
            .onChange(of: fileURL) { _, url in workspace.fileURL = url }
            .task(id: fileURL) { await watchForExternalChanges() }
            .onAppear {
                // Seed an untitled document created by a service or App Intent
                // with its pending content (see ServiceProvider.pendingText).
                if document.text.isEmpty, let pending = ServiceProvider.takePendingText() {
                    document.text = pending
                }
                workspace.source = document.text
                workspace.fileURL = fileURL
                workspace.replaceText = { document.text = $0 }
            }
            .background(WindowReader { workspace.window = $0 })
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        @Bindable var workspace = workspace
        switch mode {
        case .preview:
            MarkdownPreviewView(
                source: document.text,
                scale: workspace.scale,
                isFindPresented: $workspace.isFindPresented,
            )
        case .split:
            // Live split: rendered preview on top, raw source below. The shared
            // render path updates as the buffer changes, so edits are reflected
            // immediately without leaving the editor. Both panes share the find
            // state, so Find opens a bar in each — the search term carries
            // between them through the system find pasteboard.
            VSplitView {
                MarkdownPreviewView(
                    source: document.text,
                    scale: workspace.scale,
                    showsPlaceholder: false,
                    isFindPresented: $workspace.isFindPresented,
                )
                .frame(minHeight: 120)
                sourceEditor
                    .frame(minHeight: 120)
            }
        case .edit:
            sourceEditor
        }
    }

    private var sourceEditor: some View {
        @Bindable var workspace = workspace
        return MarkdownSourceEditor(
            text: $document.text,
            scale: workspace.scale,
            isFindPresented: $workspace.isFindPresented,
            showsLineNumbers: showsLineNumbers,
            lineJump: workspace.lineJump,
        )
    }

    /// Confirms the go-to-line alert: needs the editor on screen, so preview
    /// mode falls into split.
    private func goToLine() {
        if mode == .preview { mode = .split }
        workspace.performGoToLine()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View Mode", selection: $mode) {
                Label("Preview", systemImage: "doc.richtext")
                    .tag(ViewMode.preview)
                    .help("Show the preview")
                Label("Split", systemImage: "rectangle.split.1x2")
                    .tag(ViewMode.split)
                    .help("Show the preview and the source")
                Label("Edit", systemImage: "square.and.pencil")
                    .tag(ViewMode.edit)
                    .help("Show the source")
            }
            .pickerStyle(.segmented)
        }
        ToolbarItem(placement: .primaryAction) {
            shareButton
        }
        // Search is navigation, Share is an action — the HIG wants them in
        // visually separate sections; a fixed spacer is Liquid Glass's
        // standard small separator between platters.
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button {
                workspace.toggleFind()
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .help("Find in document")
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let url = fileURL {
            ShareLink(item: url)
        } else {
            ShareLink(item: document.text)
        }
    }

    // MARK: External change reload

    private func watchForExternalChanges() async {
        guard let url = fileURL else { return }
        for await _ in FileWatcher.changes(for: url) {
            reload(from: url)
        }
    }

    /// Reloads from disk when the buffer has no unsaved edits; otherwise keeps
    /// the user's in-progress edits rather than clobbering them. Decoding goes
    /// through the document's fallback chain so a file that needed a fallback
    /// to open keeps live-reloading.
    private func reload(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let disk = ColuracetamDocument.decode(data)
        if disk == document.text {
            lastDiskText = disk
            acceptExternalChange(at: url)
        } else if document.text == lastDiskText {
            document.text = disk
            lastDiskText = disk
            acceptExternalChange(at: url)
        }
    }

    /// Tells the NSDocument machinery that the on-disk change has been
    /// deliberately absorbed. Writing the reloaded text into the binding marks
    /// the document edited, so its next autosave would compare its stale
    /// `fileModificationDate` against the externally changed file and raise
    /// the "changed by another application" conflict alert — for a change the
    /// user never made. Adopting the file's current date (and, once the
    /// binding write has settled, clearing the change count, since buffer and
    /// disk are identical) keeps the reload silent.
    private func acceptExternalChange(at url: URL) {
        guard let nsDocument = NSDocumentController.shared.document(for: url) else { return }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        if let date = values?.contentModificationDate {
            nsDocument.fileModificationDate = date
        }
        // The SwiftUI document bridge registers the binding write as an edit
        // asynchronously; clear it after that has happened.
        DispatchQueue.main.async {
            if document.text == lastDiskText {
                nsDocument.updateChangeCount(.changeCleared)
            }
        }
    }
}

/// Reports the `NSWindow` hosting this view — SwiftUI offers no direct way to
/// reach it, and the workspace needs it to apply window options (pin, opacity).
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context _: Context) {
        // `view.window` is nil during the first update; report asynchronously
        // once the view lands in its window.
        DispatchQueue.main.async { [onWindow] in onWindow(view.window) }
    }
}

#Preview {
    ContentView(document: .constant(ColuracetamDocument(text: "# Hello\n\nWorld")))
}

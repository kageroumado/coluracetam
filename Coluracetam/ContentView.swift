import AppKit
import ColuracetamKit
import SwiftUI

struct ContentView: View {
    @Binding var document: ColuracetamDocument
    @Environment(\.documentConfiguration) private var documentConfiguration

    @State private var workspace = DocumentWorkspace()
    @State private var isEditing: Bool
    /// The text last known to be on disk — the baseline for deciding whether the
    /// buffer has unsaved edits when an external change arrives.
    @State private var lastDiskText: String

    init(document: Binding<ColuracetamDocument>) {
        _document = document
        // A new or empty document has nothing to preview, so open in Edit.
        _isEditing = State(initialValue: document.wrappedValue.text.isEmpty)
        _lastDiskText = State(initialValue: document.wrappedValue.text)
    }

    private var fileURL: URL? {
        documentConfiguration?.fileURL
    }

    var body: some View {
        content
            .toolbar { toolbarContent }
            .focusedSceneValue(\.documentWorkspace, workspace)
            .onChange(of: document.text) { _, text in
                workspace.source = text
            }
            .onChange(of: fileURL) { _, url in workspace.fileURL = url }
            .task(id: fileURL) { await watchForExternalChanges() }
            .onAppear {
                workspace.source = document.text
                workspace.fileURL = fileURL
            }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isEditing {
            // Live split: rendered preview on top, raw source below. The shared
            // render path updates as the buffer changes, so edits are reflected
            // immediately without leaving the editor. The editor pane owns the
            // find bar in this mode.
            VSplitView {
                MarkdownRenderView(
                    source: document.text,
                    scale: workspace.scale,
                    showsPlaceholder: false,
                )
                .frame(minHeight: 120)
                sourceEditor
                    .frame(minHeight: 120)
            }
        } else {
            MarkdownRenderView(
                source: document.text,
                scale: workspace.scale,
                isFindPresented: Binding(
                    get: { workspace.isFindPresented },
                    set: { workspace.isFindPresented = $0 },
                ),
            )
        }
    }

    private var sourceEditor: some View {
        MarkdownSourceEditor(
            text: $document.text,
            scale: workspace.scale,
            isFindPresented: Binding(
                get: { workspace.isFindPresented },
                set: { workspace.isFindPresented = $0 },
            ),
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                workspace.toggleFind()
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .help("Find in document")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            shareButton
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $isEditing) {
                Label("Edit", systemImage: "square.and.pencil")
            }
            .help("Edit source")
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
    /// the user's in-progress edits rather than clobbering them.
    private func reload(from url: URL) {
        guard let disk = try? String(contentsOf: url, encoding: .utf8) else { return }
        if disk == document.text {
            lastDiskText = disk
        } else if document.text == lastDiskText {
            document.text = disk
            lastDiskText = disk
        }
    }
}

#Preview {
    ContentView(document: .constant(ColuracetamDocument(text: "# Hello\n\nWorld")))
}

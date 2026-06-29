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
    @State private var matchCount = 0
    @FocusState private var findFieldFocused: Bool

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
            .overlay(alignment: .top) { findBar }
            .focusedSceneValue(\.documentWorkspace, workspace)
            .onChange(of: isEditing) { _, editing in
                if !editing { findFieldFocused = false }
            }
            .onChange(of: document.text) { _, text in
                workspace.source = text
                updateMatchCount()
            }
            .onChange(of: workspace.searchText) { updateMatchCount() }
            .onChange(of: workspace.isFindPresented) { _, presented in
                if presented, !isEditing { findFieldFocused = true }
                if !presented { workspace.searchText = "" }
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
            // immediately without leaving the editor.
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
                searchTerm: workspace.isFindPresented ? workspace.searchText : "",
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

    @ViewBuilder
    private var findBar: some View {
        if workspace.isFindPresented, !isEditing {
            FindBar(
                text: $workspace.searchText,
                matchCount: matchCount,
                focused: $findFieldFocused,
            ) {
                workspace.isFindPresented = false
            }
            .padding(12)
        }
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

    // MARK: Find

    private func updateMatchCount() {
        let term = workspace.searchText
        matchCount = term.isEmpty ? 0 : MarkdownRenderView.matchCount(in: document.text, of: term)
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

/// A compact find field overlaid on the rendered view.
private struct FindBar: View {
    @Binding var text: String
    var matchCount: Int
    @FocusState.Binding var focused: Bool
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .frame(width: 180)
            if !text.isEmpty {
                Text(matchCount == 0 ? "Not found" : "\(matchCount)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
            .help("Close find")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .rect(cornerRadius: 9))
        .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

#Preview {
    ContentView(document: .constant(ColuracetamDocument(text: "# Hello\n\nWorld")))
}

import SwiftUI

@main
struct ColuracetamApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: ColuracetamDocument()) { file in
            ContentView(document: file.$document)
        }
        .defaultSize(width: 720, height: 900)
        .commands {
            DocumentCommands()
        }
    }
}

/// Menu commands that act on the focused document window's ``DocumentWorkspace``.
private struct DocumentCommands: Commands {
    @FocusedValue(\.documentWorkspace) private var workspace
    @AppStorage("showsLineNumbers") private var showsLineNumbers = false

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button {
                openNewTab()
            } label: {
                Label("New Tab", systemImage: "plus.rectangle.on.rectangle")
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(after: .textEditing) {
            Button {
                workspace?.toggleFind()
            } label: {
                Label("Find…", systemImage: "text.page.badge.magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(workspace == nil)
            Button {
                workspace?.promptGoToLine()
            } label: {
                Label("Go to Line…", systemImage: "number")
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(workspace == nil)
        }

        // Zoom lives in the system-provided View menu. A `CommandMenu("View")`
        // would collide with that menu and drop its items, so anchor to a
        // View-menu placement instead.
        CommandGroup(after: .toolbar) {
            Divider()
            Button {
                workspace?.zoomIn()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(!(workspace?.canZoomIn ?? false))
            Button {
                workspace?.zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!(workspace?.canZoomOut ?? false))
            Button {
                workspace?.resetZoom()
            } label: {
                Label("Actual Size", systemImage: "1.magnifyingglass")
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(workspace == nil)
            Divider()
            Toggle(isOn: $showsLineNumbers) {
                Label("Line Numbers", systemImage: "list.number")
            }
            Picker(selection: Binding(
                get: { workspace?.lineEnding ?? .lf },
                set: { workspace?.setLineEnding($0) },
            )) {
                Text("macOS / Unix (LF)").tag(LineEnding.lf)
                Text("Windows (CRLF)").tag(LineEnding.crlf)
            } label: {
                Label("Line Endings", systemImage: "return")
            }
            .pickerStyle(.menu)
            .disabled(workspace == nil)
            Divider()
            Button {
                NSApp.keyWindow?.toggleTabBar(nil)
            } label: {
                Label("Show or Hide Tab Bar", systemImage: "rectangle.split.3x1")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            Button {
                NSApp.keyWindow?.toggleToolbarShown(nil)
            } label: {
                Label("Show or Hide Toolbar", systemImage: "rectangle.topthird.inset.filled")
            }
            // Not Finder's ⌥⌘T: something system-side consumes that chord
            // before apps ever see it (verified with an event monitor), and
            // SwiftUI menus can't match Option-transformed equivalents anyway.
            .keyboardShortcut("t", modifiers: [.command, .control])
        }

        // Refrax-style window options: pin, translucency, and size presets —
        // handy for keeping a note floating over other work. Pin and opacity
        // go through the focused workspace (not NSApp.keyWindow directly) so
        // the menu checkmarks are observable and stay current.
        CommandGroup(after: .windowSize) {
            Divider()
            Toggle(isOn: Binding(
                get: { workspace?.isPinned ?? false },
                set: { workspace?.isPinned = $0 },
            )) {
                Label("Keep on Top", systemImage: "pin")
            }
            .disabled(workspace == nil)
            Picker(selection: Binding(
                get: { workspace?.opacity ?? .full },
                set: { workspace?.opacity = $0 },
            )) {
                ForEach(WindowOpacity.allCases, id: \.self) { opacity in
                    Text(opacity.title).tag(opacity)
                }
            } label: {
                Label("Window Opacity", systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)
            .disabled(workspace == nil)
            Menu {
                ForEach(Self.sizePresets, id: \.title) { preset in
                    Button(preset.title) { resizeKeyWindow(to: preset.size) }
                }
            } label: {
                Label("Quick Resize", systemImage: "aspectratio")
            }
        }

        CommandGroup(after: .importExport) {
            Button {
                workspace?.exportPDF()
            } label: {
                Label("Export as PDF…", systemImage: "richtext.page")
            }
            .disabled(workspace == nil)
            Button {
                workspace?.exportHTML()
            } label: {
                Label("Export as HTML…", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .disabled(workspace == nil)
        }

        // Replace (not augment) the default print commands: DocumentGroup's
        // built-in Print… routes to NSDocument's unimplemented printDocument:
        // ("This application does not support printing.") and owns ⌘P.
        CommandGroup(replacing: .printItem) {
            Button {
                workspace?.printDocument()
            } label: {
                Label("Print…", systemImage: "printer")
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(workspace == nil)
        }
    }

    /// Quick Resize presets: typical web content widths, since documents are
    /// mostly read at web-page proportions — the width is what matters, and
    /// the height follows the app's letter-ish default aspect (720 × 900).
    private static let sizePresets: [(title: String, size: NSSize)] = [
        ("640 × 800", NSSize(width: 640, height: 800)),
        ("720 × 900 (Default)", NSSize(width: 720, height: 900)),
        ("960 × 1200", NSSize(width: 960, height: 1_200)),
        ("1200 × 1500", NSSize(width: 1_200, height: 1_500)),
    ]

    /// Resizes the key window, keeping its top-left corner fixed (so the
    /// title bar doesn't jump) and clamping to the screen's visible area.
    private func resizeKeyWindow(to size: NSSize) {
        guard let window = NSApp.keyWindow else { return }
        var target = size
        if let screen = window.screen?.visibleFrame {
            target.width = min(target.width, screen.width)
            target.height = min(target.height, screen.height)
        }
        var frame = window.frame
        frame.origin.y += frame.height - target.height
        frame.size = target
        window.setFrame(frame, display: true, animate: true)
    }

    /// Opens a new untitled document as a *tab* of the key window: the window
    /// briefly prefers tabbing while the document controller creates the new
    /// window, then returns to the automatic (user-preference) behavior.
    private func openNewTab() {
        let keyWindow = NSApp.keyWindow
        keyWindow?.tabbingMode = .preferred
        NSDocumentController.shared.newDocument(nil)
        DispatchQueue.main.async { keyWindow?.tabbingMode = .automatic }
    }
}


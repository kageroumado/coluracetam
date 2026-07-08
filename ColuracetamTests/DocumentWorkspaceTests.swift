import AppKit
import Testing
@testable import Coluracetam

@MainActor
@Suite("DocumentWorkspace")
struct DocumentWorkspaceTests {
    // MARK: Zoom

    @Test
    func `Zoom steps by a tenth and clamps to its bounds`() {
        let workspace = DocumentWorkspace()
        #expect(workspace.scale == 1)

        workspace.zoomIn()
        #expect(abs(workspace.scale - 1.1) < 0.0001)

        for _ in 0..<40 { workspace.zoomIn() }
        #expect(workspace.scale == DocumentWorkspace.maxScale)
        #expect(!workspace.canZoomIn)
        #expect(workspace.canZoomOut)

        for _ in 0..<40 { workspace.zoomOut() }
        #expect(workspace.scale == DocumentWorkspace.minScale)
        #expect(!workspace.canZoomOut)
        #expect(workspace.canZoomIn)

        workspace.resetZoom()
        #expect(workspace.scale == 1)
    }

    // MARK: Line endings

    @Test
    func `Line ending detection prefers CRLF when any is present`() {
        let workspace = DocumentWorkspace()
        workspace.source = "a\nb"
        #expect(workspace.lineEnding == .lf)
        workspace.source = "a\r\nb"
        #expect(workspace.lineEnding == .crlf)
        workspace.source = "a\r\nb\nc"
        #expect(workspace.lineEnding == .crlf)
    }

    @Test
    func `Converting line endings normalizes every variant`() {
        let workspace = DocumentWorkspace()
        var replaced: String?
        workspace.replaceText = { replaced = $0 }

        workspace.source = "a\r\nb\rc\nd"
        workspace.setLineEnding(.lf)
        #expect(replaced == "a\nb\nc\nd")

        replaced = nil
        workspace.source = "a\nb\rc"
        workspace.setLineEnding(.crlf)
        #expect(replaced == "a\r\nb\r\nc")
    }

    @Test
    func `Converting to the current ending is a no-op`() {
        let workspace = DocumentWorkspace()
        var replaceCalls = 0
        workspace.replaceText = { _ in replaceCalls += 1 }

        workspace.source = "a\nb"
        workspace.setLineEnding(.lf)
        #expect(replaceCalls == 0)
    }

    // MARK: Go to line

    @Test
    func `Go-to-line parses trimmed positive integers only`() {
        let workspace = DocumentWorkspace()

        workspace.goToLineText = " 42 "
        workspace.performGoToLine()
        #expect(workspace.lineJump?.line == 42)

        workspace.lineJump = nil
        for rejected in ["abc", "0", "-3", "", "1.5"] {
            workspace.goToLineText = rejected
            workspace.performGoToLine()
            #expect(workspace.lineJump == nil, "\(rejected) should be rejected")
        }
    }

    @Test
    func `Repeated jumps to the same line are distinct requests`() {
        #expect(LineJump(line: 7) != LineJump(line: 7))
    }

    // MARK: Window options

    @Test
    func `Pin and opacity apply to the hosting window`() {
        let workspace = DocumentWorkspace()
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        workspace.window = window

        workspace.isPinned = true
        #expect(window.level == .floating)
        workspace.isPinned = false
        #expect(window.level == .normal)

        workspace.opacity = .medium
        #expect(abs(window.alphaValue - 0.6) < 0.0001)
        workspace.opacity = .full
        #expect(window.alphaValue == 1)
    }

    @Test
    func `Opacity presets mirror Refrax's steps`() {
        #expect(WindowOpacity.allCases.map(\.alpha) == [1, 0.8, 0.6, 0.4])
        for preset in WindowOpacity.allCases {
            #expect(!preset.title.isEmpty)
        }
    }
}

import Foundation
import Testing
@testable import Coluracetam

@MainActor
@Suite("ServiceProvider")
struct ServiceProviderTests {
    @Test
    func `Documents get unique Finder-style names`() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("service-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = try ServiceProvider.createDocument(in: folder)
        let second = try ServiceProvider.createDocument(in: folder, contents: "# Hi")
        let third = try ServiceProvider.createDocument(in: folder)

        #expect(first.lastPathComponent == "Untitled.md")
        #expect(second.lastPathComponent == "Untitled 2.md")
        #expect(third.lastPathComponent == "Untitled 3.md")
        #expect(try String(contentsOf: second, encoding: .utf8) == "# Hi")
        #expect(try Data(contentsOf: first).isEmpty)
    }

    @Test
    func `Pending text is consumed exactly once`() {
        ServiceProvider.pendingText = "hello"
        #expect(ServiceProvider.takePendingText() == "hello")
        #expect(ServiceProvider.takePendingText() == nil)
    }
}

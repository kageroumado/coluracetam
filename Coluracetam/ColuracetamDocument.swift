import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The Daring Fireball Markdown type that `.md`/`.markdown` resolve to.
    /// Declared as an imported type in the app's Info.plist.
    nonisolated static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

/// A plain-text Markdown document, edited and saved as UTF-8.
nonisolated struct ColuracetamDocument: FileDocument {
    var text: String

    init(text: String = "") {
        self.text = text
    }

    static let readableContentTypes: [UTType] = [.markdown]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

import Foundation
import Testing
@testable import Coluracetam

@Suite("Document decoding")
struct ColuracetamDocumentTests {
    @Test
    func `UTF-8 decodes exactly, including emoji`() {
        let text = "# Héllo 😀\n\n- ライン"
        #expect(ColuracetamDocument.decode(Data(text.utf8)) == text)
    }

    @Test
    func `UTF-16 little-endian with BOM falls back correctly`() {
        var data = Data([0xFF, 0xFE])
        data.append("hi\n".data(using: .utf16LittleEndian)!)
        #expect(ColuracetamDocument.decode(data) == "hi\n")
    }

    @Test
    func `UTF-16 big-endian with BOM falls back correctly`() {
        var data = Data([0xFE, 0xFF])
        data.append("hi\n".data(using: .utf16BigEndian)!)
        #expect(ColuracetamDocument.decode(data) == "hi\n")
    }

    @Test
    func `Invalid UTF-8 falls back to Latin-1 rather than failing`() {
        // 0xE9 is "é" in Latin-1 and an invalid standalone byte in UTF-8.
        let data = Data([0x63, 0x61, 0x66, 0xE9])
        #expect(ColuracetamDocument.decode(data) == "café")
    }

    @Test
    func `Empty data decodes to an empty document`() {
        #expect(ColuracetamDocument.decode(Data()) == "")
    }
}

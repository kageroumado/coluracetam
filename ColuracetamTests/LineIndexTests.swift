import Foundation
import Testing
@testable import Coluracetam

@Suite("LineIndex")
struct LineIndexTests {
    @Test
    func `Empty string still has one line`() {
        let index = LineIndex(string: "")
        #expect(index.lineCount == 1)
        #expect(index.lineNumber(forCharacterAt: 0) == 1)
        #expect(index.characterRange(ofLine: 1) == NSRange(location: 0, length: 0))
    }

    @Test
    func `Single line without a trailing newline`() {
        let index = LineIndex(string: "hello")
        #expect(index.lineCount == 1)
        #expect(index.characterRange(ofLine: 1) == NSRange(location: 0, length: 5))
    }

    @Test
    func `Line numbers at and around break boundaries`() {
        // Offsets: a=0 \n=1 b=2 b=3 \n=4 c=5 c=6 c=7
        let index = LineIndex(string: "a\nbb\nccc")
        #expect(index.lineCount == 3)
        #expect(index.lineNumber(forCharacterAt: 0) == 1)
        #expect(index.lineNumber(forCharacterAt: 1) == 1)
        #expect(index.lineNumber(forCharacterAt: 2) == 2)
        #expect(index.lineNumber(forCharacterAt: 4) == 2)
        #expect(index.lineNumber(forCharacterAt: 7) == 3)
    }

    @Test
    func `Ranges include the trailing line break`() {
        let index = LineIndex(string: "a\nbb\nccc")
        #expect(index.characterRange(ofLine: 1) == NSRange(location: 0, length: 2))
        #expect(index.characterRange(ofLine: 2) == NSRange(location: 2, length: 3))
        #expect(index.characterRange(ofLine: 3) == NSRange(location: 5, length: 3))
    }

    @Test
    func `A trailing newline does not open a new line`() {
        // Matches NSString.lineRange semantics: "a\n" is one logical line.
        let index = LineIndex(string: "a\n")
        #expect(index.lineCount == 1)
        #expect(index.characterRange(ofLine: 1) == NSRange(location: 0, length: 2))
    }

    @Test
    func `CRLF counts as a single break`() {
        let index = LineIndex(string: "a\r\nb")
        #expect(index.lineCount == 2)
        #expect(index.characterRange(ofLine: 2) == NSRange(location: 3, length: 1))
    }

    @Test
    func `Out-of-range lines clamp instead of trapping`() {
        let index = LineIndex(string: "a\nb")
        #expect(index.characterRange(ofLine: 99) == index.characterRange(ofLine: 2))
        #expect(index.characterRange(ofLine: 0) == index.characterRange(ofLine: 1))
        #expect(index.characterRange(ofLine: -5) == index.characterRange(ofLine: 1))
    }

    @Test
    func `Offsets are UTF-16 units, surviving surrogate pairs`() {
        // "é" is 1 UTF-16 unit, "😀" is 2 — line 2 starts at offset 4.
        let index = LineIndex(string: "é😀\nx")
        #expect(index.lineCount == 2)
        #expect(index.lineNumber(forCharacterAt: 3) == 1)
        #expect(index.lineNumber(forCharacterAt: 4) == 2)
        #expect(index.characterRange(ofLine: 2) == NSRange(location: 4, length: 1))
    }
}

import Foundation

/// Start offsets of every logical line in a string — one shared lookup used by
/// the line-number ruler and go-to-line, so neither walks the document per
/// query.
///
/// Building is O(text length); lookups are O(log lines) binary searches.
/// Offsets are UTF-16 (`NSString`/`NSRange`) units.
nonisolated struct LineIndex {
    /// The offset of each line's first character. Never empty: an empty string
    /// still has line 1 starting at 0.
    private let starts: [Int]
    /// The indexed string's length, bounding the last line's range.
    private let length: Int

    init(string: String = "") {
        let ns = string as NSString
        var starts: [Int] = [0]
        var index = 0
        while index < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            index = NSMaxRange(lineRange)
            if index < ns.length { starts.append(index) }
        }
        self.starts = starts
        length = ns.length
    }

    var lineCount: Int {
        starts.count
    }

    /// The 1-based number of the line containing `offset`.
    func lineNumber(forCharacterAt offset: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    /// The character range of `line` (1-based, clamped to the last line),
    /// including its trailing line break.
    func characterRange(ofLine line: Int) -> NSRange {
        let index = max(0, min(line - 1, starts.count - 1))
        let start = starts[index]
        let end = index + 1 < starts.count ? starts[index + 1] : length
        return NSRange(location: start, length: end - start)
    }
}

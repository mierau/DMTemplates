// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

/// Template source as UTF-8 bytes, with the scanning the template parser needs.
/// Positions are byte offsets.
struct SourceText {
   let bytes: [UInt8]

   init(_ source: String) {
      self.bytes = Array(source.utf8)
   }

   var count: Int { bytes.count }

   func text(_ range: Range<Int>) -> String {
      String(decoding: bytes[range], as: UTF8.self)
   }

   /// The first position at or after `start` where `needle` appears.
   func find(_ needle: [UInt8], from start: Int) -> Int? {
      guard let first = needle.first, needle.count <= bytes.count else {
         return nil
      }
      var i = start
      while i <= bytes.count - needle.count {
         if bytes[i] == first && bytes[i..<(i + needle.count)].elementsEqual(needle) {
            return i
         }
         i += 1
      }
      return nil
   }

   /// `range` without leading and trailing whitespace.
   func trimmed(_ range: Range<Int>) -> Range<Int> {
      var start = range.lowerBound
      var end = range.upperBound
      while start < end, bytes[start].isSpace { start += 1 }
      while end > start, bytes[end - 1].isSpace { end -= 1 }
      return start..<end
   }

   /// The position after one `\n`, `\r\n` or `\r` at `position`, or `position`
   /// when there's no newline there.
   func skippingNewline(at position: Int, before end: Int) -> Int {
      guard position < end else {
         return position
      }
      if bytes[position] == UInt8(ascii: "\r") {
         let next = position + 1
         return next < end && bytes[next] == UInt8(ascii: "\n") ? next + 1 : next
      }
      return bytes[position] == UInt8(ascii: "\n") ? position + 1 : position
   }

   /// Whether `word`, which must be lowercase, appears at `position`, ignoring
   /// ASCII case.
   func matches(_ word: String, at position: Int, before end: Int) -> Bool {
      guard position + word.utf8.count <= end else {
         return false
      }
      var i = position
      for byte in word.utf8 {
         if bytes[i].lowercasedASCII != byte {
            return false
         }
         i += 1
      }
      return true
   }

   /// Finds `word` (such as "in") in `range` with whitespace on both sides,
   /// ignoring case and anything inside quotes.
   func findWord(_ word: String, in range: Range<Int>) -> Range<Int>? {
      var quote: UInt8?
      var i = range.lowerBound
      while i < range.upperBound {
         let byte = bytes[i]
         if let open = quote {
            if byte == UInt8(ascii: "\\") {
               i += 1
            }
            else if byte == open {
               quote = nil
            }
         }
         else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
            quote = byte
         }
         else if i > range.lowerBound, bytes[i - 1].isSpace, matches(word, at: i, before: range.upperBound) {
            let end = i + word.utf8.count
            if end < range.upperBound, bytes[end].isSpace {
               return i..<end
            }
         }
         i += 1
      }
      return nil
   }

   /// The position of the `)` that closes the `(` at `open`, skipping
   /// anything inside quotes, or nil when it isn't closed before `end`.
   func closingParenthesis(from open: Int, before end: Int) -> Int? {
      var depth = 0
      var quote: UInt8?
      var i = open
      while i < end {
         let byte = bytes[i]
         if let close = quote {
            if byte == UInt8(ascii: "\\") {
               i += 1
            }
            else if byte == close {
               quote = nil
            }
         }
         else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
            quote = byte
         }
         else if byte == UInt8(ascii: "(") {
            depth += 1
         }
         else if byte == UInt8(ascii: ")") {
            depth -= 1
            if depth == 0 {
               return i
            }
         }
         i += 1
      }
      return nil
   }

   /// The line and column (both from 1) of `offset`, counting columns in
   /// characters.
   func location(of offset: Int) -> (line: Int, column: Int) {
      let prefix = bytes[..<min(offset, bytes.count)]
      let lineStart = (prefix.lastIndex(of: UInt8(ascii: "\n")) ?? -1) + 1
      let line = prefix.filter { $0 == UInt8(ascii: "\n") }.count + 1
      let column = String(decoding: prefix[lineStart...], as: UTF8.self).count + 1
      return (line, column)
   }
}

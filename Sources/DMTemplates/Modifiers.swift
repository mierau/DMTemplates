// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

/// Single-character transforms applied to a value tag's output, written in
/// brackets before the expression: `{%[e] name %}`. Several run in order:
/// `{%[we] name %}` applies `w`, then `e`.
public struct Modifiers: Sendable {
   public typealias Transform = @Sendable (String) -> String

   private var modifiers: [Character: Modifier]

   /// No modifiers.
   public init() {
      self.modifiers = [:]
   }

   /// The built-in modifiers: `e` escapes XML/HTML, `u` percent-encodes for
   /// URLs, and `b` formats a byte count (`2034421` becomes `1.9 MB`).
   public static let standard: Modifiers = {
      var modifiers = Modifiers()
      modifiers.modifiers["e"] = .escapeXML
      modifiers.modifiers["u"] = .percentEncode
      modifiers.modifiers["b"] = .byteCount
      return modifiers
   }()

   public subscript(character: Character) -> Transform? {
      get {
         guard let modifier = modifier(for: character) else {
            return nil
         }
         return { modifier.apply($0) }
      }
      set { modifiers[character] = newValue.map { .custom($0) } }
   }

   func modifier(for character: Character) -> Modifier? {
      modifiers[character] ?? modifiers[Character(character.lowercased())]
   }
}

/// A modifier as the renderer stores it. Built-ins are plain cases rather than
/// closures so applying them takes no reference counting on shared state.
enum Modifier: Sendable {
   case escapeXML
   case percentEncode
   case byteCount
   case custom(Modifiers.Transform)

   func apply(_ text: String) -> String {
      switch self {
      case .escapeXML: return escapingXMLEntities(text)
      case .percentEncode: return addingPercentEncoding(text)
      case .byteCount: return readableByteCount(Int64(leadingIntegerOf: text))
      case .custom(let transform): return transform(text)
      }
   }
}

// MARK: - Built-in transforms

/// Escapes the same characters DMTemplateEngine's `e` modifier does.
func escapingXMLEntities(_ text: String) -> String {
   // Most values need no escaping; return them untouched.
   let needsEscaping = text.utf8.contains { byte in
      switch byte {
      case UInt8(ascii: "&"), UInt8(ascii: "<"), UInt8(ascii: ">"), UInt8(ascii: "\""), UInt8(ascii: "'"), 0x09...0x0D, 0xC2: return true
      default: return false
      }
   }
   if !needsEscaping {
      return text
   }

   var text = text
   return text.withUTF8 { bytes in
      func entity(_ byte: UInt8, _ next: UInt8?) -> StaticString? {
         switch byte {
         case UInt8(ascii: "&"): return "&amp;"
         case UInt8(ascii: "<"): return "&lt;"
         case UInt8(ascii: ">"): return "&gt;"
         case UInt8(ascii: "\""): return "&quot;"
         case UInt8(ascii: "'"): return "&apos;"
         case 0x09: return "&#x09;"
         case 0x0A: return "&#x0A;"
         case 0x0B: return "&#x0B;"
         case 0x0C: return "&#x0C;"
         case 0x0D: return "&#x0D;"
         case 0xC2 where next == 0xA0: return "&nbsp;"
         default: return nil
         }
      }

      var result: [UInt8] = []
      result.reserveCapacity(bytes.count + 16)
      var i = 0
      while i < bytes.count {
         let byte = bytes[i]
         if let replacement = entity(byte, i + 1 < bytes.count ? bytes[i + 1] : nil) {
            replacement.withUTF8Buffer { result.append(contentsOf: $0) }
            i += byte == 0xC2 ? 2 : 1
         }
         else {
            result.append(byte)
            i += 1
         }
      }
      return String(decoding: result, as: UTF8.self)
   }
}

/// Percent-encodes everything except RFC 3986 unreserved characters, so the
/// result is safe as a path segment or a query value.
func addingPercentEncoding(_ text: String) -> String {
   let hex: [Character] = Array("0123456789ABCDEF")
   var result = ""
   result.reserveCapacity(text.utf8.count)
   for byte in text.utf8 {
      switch byte {
      case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
         result.unicodeScalars.append(Unicode.Scalar(byte))
      default:
         result.append("%")
         result.append(hex[Int(byte >> 4)])
         result.append(hex[Int(byte & 0x0F)])
      }
   }
   return result
}

/// Formats a byte count the way NSByteCountFormatter's binary style does:
/// whole KB, one decimal for MB, two for GB and larger.
func readableByteCount(_ bytes: Int64) -> String {
   if bytes == 0 {
      return "Zero KB"
   }
   if bytes == 1 || bytes == -1 {
      return "\(bytes) byte"
   }
   if bytes.magnitude < 1024 {
      return "\(bytes) bytes"
   }

   let units = ["KB", "MB", "GB", "TB", "PB", "EB"]
   let decimals = [0, 1, 2, 2, 2, 2]
   var value = Double(bytes) / 1024
   var unit = 0
   while abs(value) >= 1024, unit < units.count - 1 {
      value /= 1024
      unit += 1
   }

   var text = String(format: "%.\(decimals[unit])f", value)
   if text.contains(".") {
      while text.hasSuffix("0") { text.removeLast() }
      if text.hasSuffix(".") { text.removeLast() }
   }
   return "\(text) \(units[unit])"
}

extension Int64 {
   /// Reads leading digits the way NSString's `longLongValue` does, giving 0
   /// when there are none.
   init(leadingIntegerOf text: String) {
      var digits = Substring(text.drop { $0.isWhitespace })
      var sign: Int64 = 1
      if let first = digits.first, first == "-" || first == "+" {
         sign = first == "-" ? -1 : 1
         digits = digits.dropFirst()
      }
      var value: Int64 = 0
      for character in digits {
         guard let digit = character.wholeNumberValue, character.isASCII else { break }
         let (shifted, overflow1) = value.multipliedReportingOverflow(by: 10)
         let (added, overflow2) = shifted.addingReportingOverflow(Int64(digit))
         if overflow1 || overflow2 {
            self = sign == 1 ? .max : .min
            return
         }
         value = added
      }
      self = sign * value
   }
}

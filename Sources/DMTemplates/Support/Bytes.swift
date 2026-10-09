// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

// Byte tests used when scanning templates and expressions as UTF-8.

extension UInt8 {
   /// Space, tab, newline or carriage return.
   var isSpace: Bool {
      self == UInt8(ascii: " ") || self == UInt8(ascii: "\t") || self == UInt8(ascii: "\n") || self == UInt8(ascii: "\r")
   }

   var isDigit: Bool {
      self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9")
   }

   /// ASCII letters, `_`, and any byte of a non-ASCII character, so names can
   /// use letters from any script.
   var isIdentifierStart: Bool {
      (self >= UInt8(ascii: "a") && self <= UInt8(ascii: "z")) || (self >= UInt8(ascii: "A") && self <= UInt8(ascii: "Z")) || self == UInt8(ascii: "_") || self >= 0x80
   }

   var isIdentifierPart: Bool {
      isIdentifierStart || isDigit
   }

   /// The byte lowercased if it is an ASCII capital letter.
   var lowercasedASCII: UInt8 {
      (self >= UInt8(ascii: "A") && self <= UInt8(ascii: "Z")) ? self + 32 : self
   }
}

// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

/// A value a template renders against. Everything a template can see, from the
/// root context down to loop variables, is one of these.
public enum TemplateValue: Sendable, Hashable {
   case null
   case bool(Bool)
   case int(Int)
   case double(Double)
   /// An exact decimal number, such as a price. Arithmetic with whole numbers
   /// and other decimals stays exact.
   // Boxed: unboxed, its 20 bytes would make every value larger, and
   // rendering measurably slower.
   indirect case decimal(Decimal)
   case string(String)
   /// Renders in ISO 8601, or as a formatting function asks, as in
   /// `{% post.date | date %}`.
   case date(Date)
   case array([TemplateValue])
   case dictionary([String: TemplateValue])
}

// MARK: - Conversion

extension TemplateValue {
   /// Converts Foundation and Swift values (dictionaries, arrays, strings,
   /// numbers, dates, NSNull, property list objects, JSON objects) into a
   /// template value. Anything unrecognized renders as its description.
   public init(any value: Any?) {
      guard let value else {
         self = .null
         return
      }

      // Strings and collections come first. Casting a Swift collection to a
      // class such as NSNull or NSNumber bridges (copies) the whole thing, which
      // made checking for those first many times slower.
      switch value {
      case let v as String:
         self = .string(v)
      case let v as [String: Any]:
         self = .dictionary(v.mapValues(TemplateValue.init(any:)))
      case let v as [Any]:
         self = .array(v.map(TemplateValue.init(any:)))
      case let v as TemplateValue:
         self = v
      default:
         self = TemplateValue(scalar: value)
      }
   }

   private init(scalar value: Any) {
      // Compare types exactly so a Bool never passes for a number, or a number
      // for a Bool, through NSNumber bridging.
      let type = type(of: value)
      if type == Bool.self {
         self = .bool(value as! Bool)
      }
      else if type == Int.self {
         self = .int(value as! Int)
      }
      else if type == Double.self {
         self = .double(value as! Double)
      }
      else if type == Decimal.self {
         self = .decimal(value as! Decimal)
      }
      else if let v = value as? Date {
         self = .date(v)
      }
      else if value is NSNull {
         self = .null
      }
      else if let v = value as? NSNumber {
         self = TemplateValue(number: v)
      }
      else if let v = value as? Substring {
         self = .string(String(v))
      }
      else if let v = value as? any BinaryInteger {
         self = Int(exactly: v).map { .int($0) } ?? .double(Double(v))
      }
      else if let v = value as? any BinaryFloatingPoint {
         self = .double(Double(v))
      }
      else {
         self = .string(String(describing: value))
      }
   }

   /// Converts any Encodable value (a struct, an array of structs), seeing it
   /// the way JSONEncoder would, except that dates stay dates.
   public init<T: Encodable>(encoding value: T) throws {
      self = try TemplateValueEncoder.encode(value)
   }

   private init(number: NSNumber) {
      switch UInt8(bitPattern: number.objCType.pointee) {
      case UInt8(ascii: "c"), UInt8(ascii: "B"):
         self = .bool(number.boolValue)
      case UInt8(ascii: "f"), UInt8(ascii: "d"):
         self = .double(number.doubleValue)
      default:
         self = .int(number.intValue)
      }
   }
}

// MARK: - Codable

extension TemplateValue: Codable {
   public init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      // Decoders can only be asked for a type and fail if it's wrong, and each
      // failure builds an error, so the most common types go first.
      if container.decodeNil() {
         self = .null
      }
      else if let v = try? container.decode(String.self) {
         self = .string(v)
      }
      else if let v = try? container.decode(Int.self) {
         self = .int(v)
      }
      else if let v = try? container.decode(Double.self) {
         self = .double(v)
      }
      else if let v = try? container.decode(Bool.self) {
         self = .bool(v)
      }
      else if let v = try? container.decode([String: TemplateValue].self) {
         self = .dictionary(v)
      }
      else {
         self = .array(try container.decode([TemplateValue].self))
      }
   }

   public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .null: try container.encodeNil()
      case .bool(let v): try container.encode(v)
      case .int(let v): try container.encode(v)
      case .double(let v): try container.encode(v)
      case .decimal(let v): try container.encode(v)
      case .string(let v): try container.encode(v)
      case .date(let v): try container.encode(v)
      case .array(let v): try container.encode(v)
      case .dictionary(let v): try container.encode(v)
      }
   }
}

// MARK: - Literals

extension TemplateValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
   public init(nilLiteral: ()) { self = .null }
   public init(booleanLiteral value: Bool) { self = .bool(value) }
   public init(integerLiteral value: Int) { self = .int(value) }
   public init(floatLiteral value: Double) { self = .double(value) }
   public init(stringLiteral value: String) { self = .string(value) }
   public init(arrayLiteral elements: TemplateValue...) { self = .array(elements) }
   public init(dictionaryLiteral elements: (String, TemplateValue)...) {
      self = .dictionary(Dictionary(elements, uniquingKeysWith: { _, last in last }))
   }
}

// MARK: - Rendering and coercion

extension TemplateValue {
   /// The text a value tag writes for this value. Null renders as nothing.
   public var renderedString: String {
      switch self {
      case .null:
         return ""
      case .bool(let v):
         return v ? "true" : "false"
      case .int(let v):
         return String(v)
      case .double(let v):
         // Whole numbers render without a trailing ".0", like NSNumber.
         if v.rounded(.towardZero) == v, abs(v) < 1e15 {
            return String(Int(v))
         }
         return String(v)
      case .decimal(let v):
         return v.description
      case .string(let v):
         return v
      case .date(let v):
         return v.formatted(.iso8601)
      case .array(let v):
         return v.map(\.renderedString).joined(separator: ", ")
      case .dictionary(let v):
         return "{" + v.keys.sorted().map { "\($0): \(v[$0]!.renderedString)" }.joined(separator: ", ") + "}"
      }
   }

   /// Truthiness used by `if` and the logical operators.
   public var isTruthy: Bool {
      switch self {
      case .null: return false
      case .bool(let v): return v
      case .int(let v): return v != 0
      case .double(let v): return v != 0
      case .decimal(let v): return !v.isZero
      case .string(let v): return !v.isEmpty
      case .date: return true
      case .array(let v): return !v.isEmpty
      case .dictionary(let v): return !v.isEmpty
      }
   }

   enum Number {
      case int(Int)
      case double(Double)
      indirect case decimal(Decimal)

      var double: Double {
         switch self {
         case .int(let v): return Double(v)
         case .double(let v): return v
         case .decimal(let v): return NSDecimalNumber(decimal: v).doubleValue
         }
      }

      /// The number as an exact decimal, unless it's a `Double`.
      var exactDecimal: Decimal? {
         switch self {
         case .int(let v): return Decimal(v)
         case .double: return nil
         case .decimal(let v): return v
         }
      }
   }

   /// The value as a number, reading numeric strings and booleans the way KVC
   /// and NSPredicate coerce them.
   var number: Number? {
      switch self {
      case .int(let v): return .int(v)
      case .double(let v): return .double(v)
      case .decimal(let v): return .decimal(v)
      case .bool(let v): return .int(v ? 1 : 0)
      case .string(let v):
         return Self.number(reading: v)
      default:
         return nil
      }
   }

   /// Decimal text as a number, ignoring spaces around it. Text Swift would
   /// otherwise read as a number, such as "nan", "inf" or "0x10", isn't one.
   private static func number(reading text: String) -> Number? {
      var text = Substring(text)
      if text.first?.isWhitespace == true || text.last?.isWhitespace == true {
         text = Substring(text.trimmingCharacters(in: .whitespaces))
      }
      let isDecimal = text.utf8.allSatisfy { byte in
         byte.isDigit || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") || byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E")
      }
      guard isDecimal else {
         return nil
      }
      if let i = Int(text) { return .int(i) }
      if let d = Double(text) { return .double(d) }
      return nil
   }
}

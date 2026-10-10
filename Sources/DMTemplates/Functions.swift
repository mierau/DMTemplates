// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

/// Swift closures templates can call. A template calls a function on a value
/// the way Swift calls a method, through a pipe, or with the value as the
/// first argument; all three mean the same:
///
///     {% person.name.prefix(1).uppercased() %}
///     {% person.name | prefix(1) | uppercased %}
///     {% uppercased(prefix(person.name, 1)) %}
///
/// Templates can only call functions registered here.
///
///     var options = TemplateOptions()
///     options.functions["initials"] = { receiver, _ in
///        .string(receiver.renderedString.split(separator: " ").compactMap(\.first).map(String.init).joined())
///     }
///     let template = try Template("{% name | initials %}", options: options)
///     template.render(["name": "Dustin Mierau"])  // "DM"
public struct Functions: Sendable {
   public typealias Function = @Sendable (_ receiver: TemplateValue, _ arguments: [TemplateValue]) -> TemplateValue

   private var table: [String: Function]

   /// No functions.
   public init() {
      self.table = [:]
   }

   /// Common text and list functions, named after their Swift counterparts:
   ///
   /// - `uppercased`, `lowercased`, `capitalized`, `trimmed`
   /// - `prefix(n)`, `suffix(n)`, `dropFirst(n)`, `dropLast(n)`; n defaults to 1
   ///   for the `drop` functions
   /// - `replacing(old, new)`
   /// - `reversed`, which reverses text or a list
   /// - `joined(separator)`, which joins a list into text
   /// - `path(components...)`, which joins its receiver and arguments with `/`
   /// - `default(fallback)`, the fallback when the value is nil or empty
   /// - `escaped`, which escapes text for HTML and XML
   /// - `urlEncoded`, which percent-encodes everything but letters, digits
   ///   and `-._~`
   /// - `bytes`, which shows a byte count for people, as in `1.9 MB`
   ///
   /// Templates also get formatting functions, such as `date` and `currency`,
   /// which follow the template's locale; see `TemplateOptions.locale`.
   ///
   /// Text functions applied to a list apply to each element, so
   /// `files.name | lowercased` lowercases every name.
   public static let standard: Functions = {
      var functions = Functions()

      functions["uppercased"] = textFunction { text, _ in .string(text.uppercased()) }
      functions["lowercased"] = textFunction { text, _ in .string(text.lowercased()) }
      functions["capitalized"] = textFunction { text, _ in .string(text.capitalized) }
      functions["trimmed"] = textFunction { text, _ in .string(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
      functions["prefix"] = textFunction { text, arguments in
         guard let count = integer(arguments.first), count >= 0 else { return .null }
         return .string(String(text.prefix(count)))
      }
      functions["suffix"] = textFunction { text, arguments in
         guard let count = integer(arguments.first), count >= 0 else { return .null }
         return .string(String(text.suffix(count)))
      }
      functions["dropFirst"] = textFunction { text, arguments in
         guard let count = arguments.isEmpty ? 1 : integer(arguments.first), count >= 0 else { return .null }
         return .string(String(text.dropFirst(count)))
      }
      functions["dropLast"] = textFunction { text, arguments in
         guard let count = arguments.isEmpty ? 1 : integer(arguments.first), count >= 0 else { return .null }
         return .string(String(text.dropLast(count)))
      }
      functions["replacing"] = textFunction { text, arguments in
         guard arguments.count == 2, let target = string(arguments[0]), !target.isEmpty else { return .null }
         return .string(text.replacingOccurrences(of: target, with: arguments[1].renderedString))
      }
      functions["reversed"] = { receiver, _ in
         switch receiver {
         case .array(let items): return .array(items.reversed())
         default: return string(receiver).map { .string(String($0.reversed())) } ?? .null
         }
      }
      functions["joined"] = { receiver, arguments in
         guard case .array(let items) = receiver else { return string(receiver).map { .string($0) } ?? .null }
         let separator = arguments.first?.renderedString ?? ""
         return .string(items.filter { $0 != .null }.map(\.renderedString).joined(separator: separator))
      }
      functions["path"] = { receiver, arguments in
         var parts: [String] = []
         for value in [receiver] + arguments {
            switch value {
            case .null: continue
            case .array(let items): parts += items.filter { $0 != .null }.map(\.renderedString)
            default: parts.append(value.renderedString)
            }
         }
         return parts.isEmpty ? .null : .string(joinedPath(parts))
      }
      functions["escaped"] = textFunction { text, _ in .string(escapingXMLEntities(text)) }
      functions["urlEncoded"] = textFunction { text, _ in .string(addingPercentEncoding(text)) }
      functions["bytes"] = textFunction { text, _ in .string(readableByteCount(Int64(leadingIntegerOf: text))) }
      functions["default"] = { receiver, arguments in
         switch receiver {
         case .null: return arguments.first ?? .null
         case .string(let text) where text.isEmpty: return arguments.first ?? .null
         default: return receiver
         }
      }
      return functions
   }()

   public subscript(name: String) -> Function? {
      get { table[name] }
      set { table[name] = newValue }
   }

   /// Makes a function from a transform of text, such as
   ///
   ///     options.functions["shout"] = Functions.text { $0.uppercased() + "!" }
   ///
   /// Applied to a list, it transforms each element. Nil stays nil.
   public static func text(_ transform: @escaping @Sendable (String) -> String) -> Function {
      textFunction { text, _ in .string(transform(text)) }
   }

   /// Functions from `other` added to these, replacing any with the same name.
   func adding(_ other: Functions) -> Functions {
      var result = self
      result.table.merge(other.table) { _, new in new }
      return result
   }

   /// A function on text. Applied to a list, it applies to each element.
   static func textFunction(_ body: @escaping @Sendable (String, [TemplateValue]) -> TemplateValue) -> Function {
      @Sendable func apply(_ receiver: TemplateValue, _ arguments: [TemplateValue]) -> TemplateValue {
         if case .array(let items) = receiver {
            return .array(items.map { apply($0, arguments) })
         }
         return string(receiver).map { body($0, arguments) } ?? .null
      }
      return apply
   }

   private static func joinedPath(_ parts: [String]) -> String {
      var path = parts.joined(separator: "/")
      while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
      return path
   }

   static func string(_ value: TemplateValue) -> String? {
      switch value {
      case .null, .array, .dictionary: return nil
      default: return value.renderedString
      }
   }

   static func integer(_ value: TemplateValue?) -> Int? {
      switch value?.number {
      case .int(let v)?: return v
      case .double(let v)?: return Int(exactly: v.rounded(.towardZero))
      case nil: return nil
      }
   }
}

/// Optional template features, switched on or off for each render.
public struct RenderFeatures: OptionSet, Sendable {
   public let rawValue: UInt8

   public init(rawValue: UInt8) {
      self.rawValue = rawValue
   }

   /// Sends `log(...)` tags to `TemplateOptions.log`. When off, they're skipped.
   public static let log = RenderFeatures(rawValue: 1 << 1)

   /// Logging on.
   public static let `default`: RenderFeatures = [.log]
}

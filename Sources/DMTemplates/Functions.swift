// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

/// Swift closures templates can call. A template calls a function on a value
/// the way Swift calls a method, through a pipe, or with the value as the
/// first argument; all three mean the same:
///
///     {% person.name.prefix(1).uppercase() %}
///     {% person.name | prefix(1) | uppercase %}
///     {% uppercase(prefix(person.name, 1)) %}
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
   /// - `uppercase`, `lowercase`, `capitalize`, `trim`
   /// - `prefix(n)`, `suffix(n)`, `dropFirst(n)`, `dropLast(n)`; n defaults to 1
   ///   for the `drop` functions
   /// - `replace(old, new)`
   /// - `reverse`, which reverses text or a list
   /// - `join(separator)`, which joins a list into text
   /// - `path(components...)`, which joins its receiver and arguments with `/`
   /// - `default(fallback)`, the fallback when the value is nil or empty
   /// - `escape`, which escapes text for HTML and XML
   /// - `urlEncode`, which percent-encodes everything but letters, digits
   ///   and `-._~`
   /// - `bytes`, which shows a byte count for people, as in `1.9 MB`
   /// - `truncate(n, ending)`, which shortens text to at most `n` characters,
   ///   ending with `ending` ("…" by default) when it cuts
   /// - `pluralize(singular, plural)`, as in `3 | pluralize("comment")`,
   ///   which gives `3 comments`; `plural` defaults to `singular` plus "s"
   /// - `sort` and `sort(key)`, `where(key, value)` and `where(key)` for the
   ///   elements whose key is truthy, and `unique`
   /// - `first`, `last` and `count`
   /// - `round(places)`, `floor`, `ceil` and `abs`
   ///
   /// Templates also get formatting functions, such as `date` and `currency`,
   /// which follow the template's locale; see `TemplateOptions.locale`.
   ///
   /// Text functions applied to a list apply to each element, so
   /// `files.name | lowercase` lowercases every name.
   public static let standard: Functions = {
      var functions = Functions()

      functions["uppercase"] = textFunction { text, _ in .string(text.uppercased()) }
      functions["lowercase"] = textFunction { text, _ in .string(text.lowercased()) }
      functions["capitalize"] = textFunction { text, _ in .string(text.capitalized) }
      functions["trim"] = textFunction { text, _ in .string(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
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
      functions["replace"] = textFunction { text, arguments in
         guard arguments.count == 2, let target = string(arguments[0]), !target.isEmpty else { return .null }
         return .string(text.replacingOccurrences(of: target, with: arguments[1].renderedString))
      }
      functions["reverse"] = { receiver, _ in
         switch receiver {
         case .array(let items): return .array(items.reversed())
         default: return string(receiver).map { .string(String($0.reversed())) } ?? .null
         }
      }
      functions["join"] = { receiver, arguments in
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
      functions["escape"] = textFunction { text, _ in .string(escapingXMLEntities(text)) }
      functions["urlEncode"] = textFunction { text, _ in .string(addingPercentEncoding(text)) }
      functions["bytes"] = textFunction { text, _ in .string(readableByteCount(Int64(leadingIntegerOf: text))) }
      functions["truncate"] = textFunction { text, arguments in
         guard let limit = integer(arguments.first), limit >= 0 else { return .null }
         guard text.count > limit else { return .string(text) }
         let ending = arguments.count > 1 ? arguments[1].renderedString : "…"
         let kept = max(0, limit - ending.count)
         return .string(String(text.prefix(kept)).trimmingCharacters(in: .whitespaces) + ending)
      }
      functions["pluralize"] = { receiver, arguments in
         guard let count = receiver.number, let singular = arguments.first.flatMap({ string($0) }) else { return .null }
         let plural = arguments.count > 1 ? arguments[1].renderedString : singular + "s"
         let isOne: Bool
         switch count {
         case .int(let v): isOne = v == 1 || v == -1
         case .double(let v): isOne = v == 1 || v == -1
         }
         return .string("\(receiver.renderedString) \(isOne ? singular : plural)")
      }

      functions["sort"] = { receiver, arguments in
         guard case .array(let items) = receiver else { return receiver }
         let key = arguments.first.flatMap({ string($0) })
         func sortKey(_ item: TemplateValue) -> TemplateValue { key.map { item.member($0) } ?? item }
         // Values that can't be ordered, such as nil, go last.
         let sorted = items.enumerated().sorted { a, b in
            let x = sortKey(a.element), y = sortKey(b.element)
            switch (x == .null, y == .null) {
            case (true, false): return false
            case (false, true): return true
            default: break
            }
            let order = compareValues(x, y, []) ?? 0
            return order == 0 ? a.offset < b.offset : order < 0
         }
         return .array(sorted.map(\.element))
      }
      functions["where"] = { receiver, arguments in
         guard case .array(let items) = receiver, let key = arguments.first.flatMap({ string($0) }) else { return receiver }
         if arguments.count > 1 {
            return .array(items.filter { valuesEqual($0.member(key), arguments[1], []) })
         }
         return .array(items.filter { $0.member(key).isTruthy })
      }
      functions["unique"] = { receiver, _ in
         guard case .array(let items) = receiver else { return receiver }
         var seen = Set<TemplateValue>()
         return .array(items.filter { seen.insert($0).inserted })
      }
      functions["first"] = { receiver, _ in
         switch receiver {
         case .string(let text): return text.first.map { .string(String($0)) } ?? .null
         default: return receiver.firstElement
         }
      }
      functions["last"] = { receiver, _ in
         switch receiver {
         case .string(let text): return text.last.map { .string(String($0)) } ?? .null
         default: return receiver.lastElement
         }
      }
      functions["count"] = { receiver, _ in receiver.elementCount }

      functions["round"] = roundingFunction { number, arguments in
         let places = integer(arguments.first) ?? 0
         guard places > 0 else { return whole(number.rounded()) }
         let scale = pow(10, Double(min(places, 15)))
         return .double((number * scale).rounded() / scale)
      }
      functions["floor"] = roundingFunction { number, _ in whole(number.rounded(.down)) }
      functions["ceil"] = roundingFunction { number, _ in whole(number.rounded(.up)) }
      functions["abs"] = { receiver, _ in
         switch receiver.number {
         case .int(let v)?: return v == .min ? .double(-Double(v)) : .int(Swift.abs(v))
         case .double(let v)?: return .double(Swift.abs(v))
         case nil: return receiver
         }
      }

      functions["default"] = { receiver, arguments in
         switch receiver {
         case .null: return arguments.first ?? .null
         case .string(let text) where text.isEmpty: return arguments.first ?? .null
         case .array(let items) where items.isEmpty: return arguments.first ?? .null
         case .dictionary(let items) where items.isEmpty: return arguments.first ?? .null
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

   /// A function on numbers. Lists apply it to each element; whole numbers
   /// and values that aren't numbers stay as they are.
   static func roundingFunction(_ body: @escaping @Sendable (Double, [TemplateValue]) -> TemplateValue) -> Function {
      @Sendable func apply(_ receiver: TemplateValue, _ arguments: [TemplateValue]) -> TemplateValue {
         if case .array(let items) = receiver {
            return .array(items.map { apply($0, arguments) })
         }
         switch receiver.number {
         case .int(let v)?: return .int(v)
         case .double(let v)?: return body(v, arguments)
         case nil: return receiver
         }
      }
      return apply
   }

   /// A rounded number, as a whole number when it fits.
   private static func whole(_ value: Double) -> TemplateValue {
      if let int = Int(exactly: value) { return .int(int) }
      return .double(value)
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

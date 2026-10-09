// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

/// Swift closures templates can call with `FUNCTION(receiver, "name", args...)`.
/// Templates can only call functions registered here, and only when a render
/// turns on `RenderFeatures.functions`.
///
///     var options = TemplateOptions()
///     options.functions["initials"] = { receiver, _ in
///        .string(receiver.renderedString.split(separator: " ").compactMap(\.first).map(String.init).joined())
///     }
///     let template = try Template("{% FUNCTION(name, 'initials') %}", options: options)
///     template.render(["name": "Dustin Mierau"], features: [.functions])  // "DM"
public struct Functions: Sendable {
   public typealias Function = @Sendable (_ receiver: TemplateValue, _ arguments: [TemplateValue]) -> TemplateValue

   private var table: [String: Function]

   /// No functions.
   public init() {
      self.table = [:]
   }

   /// Stand-ins for the NSString methods templates most often called through
   /// NSExpression's FUNCTION: `uppercaseString`, `lowercaseString`,
   /// `capitalizedString`, `length`, `substringToIndex:`, `substringFromIndex:`
   /// and `pathWithComponents:`.
   public static let standard: Functions = {
      var functions = Functions()
      functions["uppercaseString"] = { receiver, _ in
         string(receiver).map { .string($0.uppercased()) } ?? .null
      }
      functions["lowercaseString"] = { receiver, _ in
         string(receiver).map { .string($0.lowercased()) } ?? .null
      }
      functions["capitalizedString"] = { receiver, _ in
         string(receiver).map { .string($0.capitalized) } ?? .null
      }
      functions["length"] = { receiver, _ in
         string(receiver).map { .int($0.utf16.count) } ?? .null
      }
      functions["substringToIndex:"] = { receiver, arguments in
         guard let text = string(receiver), let count = integer(arguments.first), count >= 0 else { return .null }
         return .string(String(text.prefix(count)))
      }
      functions["substringFromIndex:"] = { receiver, arguments in
         guard let text = string(receiver), let count = integer(arguments.first), count >= 0 else { return .null }
         return .string(String(text.dropFirst(count)))
      }
      functions["pathWithComponents:"] = { _, arguments in
         // Builds a path from its arguments; the receiver is ignored.
         guard case .array(let components)? = arguments.first else { return .null }
         let parts = components.map(\.renderedString)
         var path = parts.joined(separator: "/")
         while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
         return .string(path)
      }
      return functions
   }()

   public subscript(name: String) -> Function? {
      get { table[name] }
      set { table[name] = newValue }
   }

   private static func string(_ value: TemplateValue) -> String? {
      switch value {
      case .null, .array, .dictionary: return nil
      default: return value.renderedString
      }
   }

   private static func integer(_ value: TemplateValue?) -> Int? {
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

   /// Runs `FUNCTION(...)` calls. When off, they evaluate to nil.
   public static let functions = RenderFeatures(rawValue: 1 << 0)

   /// Sends `log(...)` tags to `TemplateOptions.log`. When off, they're skipped.
   public static let log = RenderFeatures(rawValue: 1 << 1)

   /// Logging on, functions off.
   public static let `default`: RenderFeatures = [.log]
}

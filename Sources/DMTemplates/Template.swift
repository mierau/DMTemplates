// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

/// A parsed template.
///
/// Creating a template parses it and compiles every tag's expression, and
/// throws a `TemplateError` for mistakes such as an unclosed `if`. Rendering is
/// then a pure function of the template and a context, so one template can
/// render on many threads at once.
///
///     let template = try Template("Hello, {% firstName %}.")
///     template.render(["firstName": "Dustin"])  // "Hello, Dustin."
public struct Template: Sendable {
   private let program: Program

   public init(_ source: String, options: TemplateOptions = TemplateOptions()) throws {
      let parsed = try TemplateParser.parse(source, options: options)
      self.program = Program(parsed, options: options)
   }

   public init(contentsOf url: URL, options: TemplateOptions = TemplateOptions()) throws {
      try self.init(String(contentsOf: url, encoding: .utf8), options: options)
   }

   /// Renders the template against `context`, with the optional `features`
   /// switched on.
   public func render(_ context: TemplateValue, features: RenderFeatures = .default) -> String {
      var output: [UInt8] = []
      program.run(context, features: features, into: &output)
      return String(decoding: output, as: UTF8.self)
   }

   /// Renders the template against `context`, writing the result to `output`
   /// in pieces as it goes rather than building one string, which keeps
   /// memory down for long output. Rendering into a `String` appends to it.
   ///
   ///     var page = "<!doctype html>\n"
   ///     template.render(context, into: &page)
   public func render(_ context: TemplateValue, features: RenderFeatures = .default, into output: inout some TextOutputStream) {
      var buffer: [UInt8] = []
      program.run(context, features: features, into: &buffer, flushingAt: Self.chunkSize) { bytes in
         output.write(String(decoding: bytes, as: UTF8.self))
         bytes.removeAll(keepingCapacity: true)
      }
      if !buffer.isEmpty {
         output.write(String(decoding: buffer, as: UTF8.self))
      }
   }

   /// About how much `render(_:features:into:)` writes at a time.
   static let chunkSize = 16 * 1024

   /// Renders the template against Foundation or Swift values, such as a
   /// dictionary read from a property list or JSON.
   public func render(object: Any?, features: RenderFeatures = .default) -> String {
      render(TemplateValue(any: object), features: features)
   }

   /// Renders the template against Foundation or Swift values, writing the
   /// result to `output` in pieces as it goes.
   public func render(object: Any?, features: RenderFeatures = .default, into output: inout some TextOutputStream) {
      render(TemplateValue(any: object), features: features, into: &output)
   }

   /// Renders the template against an Encodable value.
   public func render<T: Encodable>(encoding value: T, features: RenderFeatures = .default) throws -> String {
      render(try TemplateValue(encoding: value), features: features)
   }

   /// Renders the template against an Encodable value, writing the result to
   /// `output` in pieces as it goes.
   public func render<T: Encodable>(encoding value: T, features: RenderFeatures = .default, into output: inout some TextOutputStream) throws {
      render(try TemplateValue(encoding: value), features: features, into: &output)
   }
}

/// Settings that shape how a template is parsed.
public struct TemplateOptions: Sendable {
   /// Marks the start of a tag. Default: `{%`.
   public var beginDelimiter = "{%"

   /// Marks the end of a tag. Default: `%}`.
   public var endDelimiter = "%}"

   /// Compiles tag expressions. Default: `NativeExpressionCompiler`.
   public var expressionCompiler: any ExpressionCompiler = NativeExpressionCompiler()

   /// Functions templates can call, as in `name.uppercase()` or
   /// `name | uppercase`. Default: `Functions.standard`. Templates also get
   /// the formatting functions `date`, `time`, `dateTime`, `iso8601`,
   /// `relative`, `number`, `percent`, `currency` and `format(pattern)`, which
   /// follow `locale`, `timeZone` and `currencyCode`; a function registered
   /// here under one of those names replaces it.
   ///
   /// These belong to `expressionCompiler` when it's a
   /// `NativeExpressionCompiler`; other compilers ignore them.
   public var functions: Functions {
      get { (expressionCompiler as? NativeExpressionCompiler)?.functions ?? Functions() }
      set {
         if var native = expressionCompiler as? NativeExpressionCompiler {
            native.functions = newValue
            expressionCompiler = native
         }
      }
   }

   /// The locale formatting functions use, for things like month names and
   /// number separators. Default: the current locale.
   public var locale = Locale.current

   /// The time zone formatting functions show dates in. Default: the current
   /// time zone.
   public var timeZone = TimeZone.current

   /// The currency `currency` shows, as an ISO 4217 code such as "EUR".
   /// Default: the locale's currency, or "USD" when it has none.
   public var currencyCode: String?

   /// How value tags escape what they write. Default: `.none`, which writes
   /// values as they are. Set it to `.html` for HTML or XML templates:
   ///
   ///     var options = TemplateOptions()
   ///     options.escaping = .html
   ///     let page = try Template("<h1>{% title %}</h1>", options: options)
   ///     page.render(["title": "Tom & Jerry"])  // "<h1>Tom &amp; Jerry</h1>"
   ///
   /// A value tag whose last step is `raw` or `escape`, as in
   /// `{% post.body | raw %}`, is written as it is. Template text and `log`
   /// tags are never escaped.
   public var escaping: Escaping = .none

   /// Receives output from `log(...)` tags. Default: standard error.
   public var log: @Sendable (String) -> Void = { message in
      FileHandle.standardError.write(Data((message + "\n").utf8))
   }

   public init() {}
}

/// How value tags escape the text they write.
public struct Escaping: Sendable {
   enum Kind {
      case none
      case html
      case custom(@Sendable (String) -> String)
   }

   let kind: Kind

   /// Values are written as they are.
   public static let none = Escaping(kind: .none)

   /// Escapes `&`, `<`, `>`, `"` and `'` as HTML entities.
   public static let html = Escaping(kind: .html)

   /// Escapes with `transform`, such as one for Markdown:
   ///
   ///     options.escaping = Escaping { $0.replacingOccurrences(of: "*", with: "\\*") }
   public init(_ transform: @escaping @Sendable (String) -> String) {
      self.kind = .custom(transform)
   }

   private init(kind: Kind) {
      self.kind = kind
   }
}

/// A problem found while parsing a template, with the line and column (both
/// starting at 1) where it starts.
public struct TemplateError: Error, Sendable, CustomStringConvertible {
   public let message: String
   public let line: Int
   public let column: Int

   public var description: String {
      "line \(line), column \(column): \(message)"
   }
}

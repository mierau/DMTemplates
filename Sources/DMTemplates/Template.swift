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
      self.program = Program(parsed, log: options.log)
   }

   public init(contentsOf url: URL, options: TemplateOptions = TemplateOptions()) throws {
      try self.init(String(contentsOf: url, encoding: .utf8), options: options)
   }

   /// Renders the template against `context`, with the optional `features`
   /// switched on.
   public func render(_ context: TemplateValue, features: RenderFeatures = .default) -> String {
      program.run(context, features: features)
   }

   /// Renders the template against Foundation or Swift values, such as a
   /// dictionary read from a property list or JSON.
   public func render(object: Any?, features: RenderFeatures = .default) -> String {
      render(TemplateValue(any: object), features: features)
   }

   /// Renders the template against an Encodable value.
   public func render<T: Encodable>(encoding value: T, features: RenderFeatures = .default) throws -> String {
      render(try TemplateValue(encoding: value), features: features)
   }
}

/// Settings that shape how a template is parsed.
public struct TemplateOptions: Sendable {
   /// Marks the start of a tag. Default: `{%`.
   public var beginDelimiter = "{%"

   /// Marks the end of a tag. Default: `%}`.
   public var endDelimiter = "%}"

   /// Modifiers available to value tags. Default: `Modifiers.standard`.
   public var modifiers = Modifiers.standard

   /// Compiles tag expressions. Default: `NativeExpressionCompiler`.
   public var expressionCompiler: any ExpressionCompiler = NativeExpressionCompiler()

   /// Functions templates can call with `FUNCTION(...)`. Default:
   /// `Functions.standard`. Calls only run when a render turns on
   /// `RenderFeatures.functions`.
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

   /// Receives output from `log(...)` tags. Default: standard error.
   public var log: @Sendable (String) -> Void = { message in
      FileHandle.standardError.write(Data((message + "\n").utf8))
   }

   public init() {}
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

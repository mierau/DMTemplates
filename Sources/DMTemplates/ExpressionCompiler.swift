// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

/// Turns the source of a tag's expression into something that can be evaluated
/// repeatedly. Templates call this once per tag, when the template is parsed.
///
/// `locals` lists the loop variables visible at the tag, indexed by slot. A
/// compiler resolves names against it at compile time and reads them at render
/// time through `ExpressionScope.local(_:)`; names not in `locals` are looked up
/// on the root context.
public protocol ExpressionCompiler: Sendable {
   func compile(_ source: String, locals: [String]) throws -> any CompiledExpression
}

/// An expression compiled once and evaluated on every render.
public protocol CompiledExpression: Sendable {
   func evaluate(in scope: ExpressionScope) -> TemplateValue
}

/// What an expression can see while a template renders.
public struct ExpressionScope: Sendable {
   /// The context the template is rendering against.
   public let root: TemplateValue

   /// The optional features this render turned on.
   public let features: RenderFeatures

   /// Loop variables, by slot.
   var locals: [TemplateValue]

   init(root: TemplateValue, features: RenderFeatures, localCount: Int) {
      self.root = root
      self.features = features
      self.locals = Array(repeating: .null, count: localCount)
   }

   /// The value of the loop variable in `slot`, as numbered by the `locals`
   /// passed to `ExpressionCompiler.compile(_:locals:)`.
   public func local(_ slot: Int) -> TemplateValue {
      locals[slot]
   }
}

/// A problem found while compiling an expression. `offset` counts UTF-8 bytes
/// from the start of the expression source.
public struct ExpressionError: Error, Sendable, CustomStringConvertible {
   public let message: String
   public let offset: Int

   public var description: String { message }
}

// MARK: - Built-in language

/// The built-in expression language, modeled on NSPredicate's syntax.
///
/// - Key paths and loop variables: `person.name`, `people[0]`, `person["first"]`,
///   `people[FIRST]`, `people[LAST]`, `people[SIZE]`. A key path through an
///   array collects the key from every element.
/// - Collection operators: `@count`, `@sum`, `@avg`, `@min`, `@max`, as in
///   `people.@avg.age`.
/// - Arithmetic: `+ - * / %`.
/// - Comparisons: `== = != <> < <= > >=`, `BETWEEN`, `IN`, `CONTAINS`,
///   `BEGINSWITH`, `ENDSWITH`, with `[c]`, `[d]` or `[cd]` to ignore case or
///   diacritics.
/// - Logic: `AND OR NOT`, or `&& || !`.
/// - Literals: strings, numbers, `true`/`false`/`YES`/`NO`, `nil`, and arrays
///   written `{1, 2}` or `[1, 2]`.
/// - Calls to `functions`: `name.prefix(3)`, `name | prefix(3)` and
///   `prefix(name, 3)` all call `prefix` with `name` as the receiver.
///   `FUNCTION(name, "prefix", 3)` works too. A render can turn calls off by
///   leaving `RenderFeatures.functions` out of its features.
public struct NativeExpressionCompiler: ExpressionCompiler {
   /// Functions templates may call. Calling any other is a compile error.
   public var functions: Functions

   public init(functions: Functions = .standard) {
      self.functions = functions
   }

   public func compile(_ source: String, locals: [String]) throws -> any CompiledExpression {
      try NativeExpression(syntax: parse(source, locals: locals))
   }

   func parse(_ source: String, locals: [String]) throws -> Expr {
      var parser = try ExpressionParser(source: source, locals: locals, functions: functions)
      return try parser.parse()
   }
}

/// An expression compiled by `NativeExpressionCompiler`.
///
/// Templates don't evaluate these directly: they take the syntax tree and
/// compile it into their own code, so all of a template's expressions live in
/// one place. This type serves callers using the compiler on its own.
public struct NativeExpression: CompiledExpression {
   let syntax: Expr
   private let code: ExpressionCode
   private let entry: Int32

   init(syntax: Expr) {
      var builder = ExpressionCode.Builder()
      self.syntax = syntax
      self.entry = builder.add(syntax)
      self.code = ExpressionCode(builder)
   }

   public func evaluate(in scope: ExpressionScope) -> TemplateValue {
      code.interpreter.evaluate(entry, in: scope)
   }
}

// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

/// The parsed form of a built-in expression. Templates compile it further into
/// `ExpressionCode` before rendering.
indirect enum Expr: Sendable {
   case literal(TemplateValue)
   /// The context being rendered (`self`).
   case root
   /// A loop variable, by slot.
   case local(Int)
   /// An array literal.
   case list([Expr])
   /// A value followed by keys, subscripts and collection operators.
   case path(Expr, [PathStep])
   case negate(Expr)
   case not(Expr)
   case and(Expr, Expr)
   case or(Expr, Expr)
   case arithmetic(ArithmeticOperator, Expr, Expr)
   case comparison(ComparisonOperator, StringOptions, Expr, Expr)
   /// A call such as `receiver.name(arguments...)`, resolved to its function.
   case function(Functions.Function, receiver: Expr, arguments: [Expr])
}

/// One step along a key path, applied left to right.
enum PathStep: Sendable {
   case key(String)
   case index(Expr)
   case first
   case last
   case size
   case aggregate(Aggregate)
}

/// A collection operator, such as the `@avg` in `people.@avg.age`.
enum Aggregate: String, Sendable {
   case count, sum, avg, min, max
}

enum ArithmeticOperator: Sendable {
   case add, subtract, multiply, divide, modulo
}

enum ComparisonOperator: Sendable {
   case equal, notEqual, less, lessOrEqual, greater, greaterOrEqual
   case between, `in`, contains, beginsWith, endsWith, like, matches
}

/// The `[c]` and `[d]` flags on a string comparison.
struct StringOptions: OptionSet, Sendable {
   let rawValue: UInt8
   static let caseInsensitive = StringOptions(rawValue: 1)
   static let diacriticInsensitive = StringOptions(rawValue: 2)
}

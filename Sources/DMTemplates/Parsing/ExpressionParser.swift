// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

// Parses the built-in expression language into `Expr` syntax trees.
// See `NativeExpressionCompiler` for the language.

// MARK: - Lexer

private struct Token {
   enum Kind: Equatable {
      case number(TemplateValue)
      case string(String)
      case identifier(String)
      case aggregate(String)
      case symbol(String)
      case end
   }

   let kind: Kind
   let offset: Int

   /// Identifiers uppercased, for matching keywords without regard to case.
   let keyword: String

   init(_ kind: Kind, at offset: Int) {
      self.kind = kind
      self.offset = offset
      if case .identifier(let name) = kind {
         self.keyword = name.uppercased()
      }
      else {
         self.keyword = ""
      }
   }
}

/// Splits expression source into tokens.
private struct Lexer {
   private static let pairs: Set<String> = ["==", "!=", "<>", "<=", ">=", "=<", "=>", "&&", "||"]
   private static let singles: Set<UInt8> = Set("=<>!+-*/%()[]{},.|".utf8)

   private let bytes: [UInt8]
   private var position = 0

   private init(_ source: String) {
      self.bytes = Array(source.utf8)
   }

   static func tokenize(_ source: String) throws -> [Token] {
      var lexer = Lexer(source)
      var tokens: [Token] = []
      while let token = try lexer.next() {
         tokens.append(token)
      }
      tokens.append(Token(.end, at: lexer.bytes.count))
      return tokens
   }

   private mutating func next() throws -> Token? {
      while position < bytes.count, bytes[position].isSpace {
         position += 1
      }
      guard position < bytes.count else {
         return nil
      }

      let start = position
      let byte = bytes[position]

      if byte.isDigit {
         return Token(scanNumber(), at: start)
      }
      if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
         return Token(.string(try scanString()), at: start)
      }
      if byte.isIdentifierStart {
         return Token(.identifier(scanName()), at: start)
      }
      if byte == UInt8(ascii: "@") {
         position += 1
         let name = scanName()
         if name.isEmpty {
            throw ExpressionError(message: "Expected a collection operator after '@'", offset: start)
         }
         return Token(.aggregate(name), at: start)
      }
      if byte == UInt8(ascii: "$") {
         throw ExpressionError(message: "$variables are not supported", offset: start)
      }
      if position + 1 < bytes.count, Lexer.pairs.contains(text(position..<(position + 2))) {
         position += 2
         return Token(.symbol(text(start..<position)), at: start)
      }
      if Lexer.singles.contains(byte) {
         position += 1
         return Token(.symbol(text(start..<position)), at: start)
      }
      throw ExpressionError(message: "Unexpected character '\(text(start..<(start + 1)))'", offset: start)
   }

   private func text(_ range: Range<Int>) -> String {
      String(decoding: bytes[range], as: UTF8.self)
   }

   private mutating func skipDigits() {
      while position < bytes.count, bytes[position].isDigit {
         position += 1
      }
   }

   /// `12`, `1.5`, `2e3`.
   private mutating func scanNumber() -> Token.Kind {
      let start = position
      var isDouble = false
      skipDigits()
      if position + 1 < bytes.count, bytes[position] == UInt8(ascii: "."), bytes[position + 1].isDigit {
         isDouble = true
         position += 1
         skipDigits()
      }
      if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
         var exponent = position + 1
         if exponent < bytes.count, bytes[exponent] == UInt8(ascii: "+") || bytes[exponent] == UInt8(ascii: "-") {
            exponent += 1
         }
         if exponent < bytes.count, bytes[exponent].isDigit {
            isDouble = true
            position = exponent
            skipDigits()
         }
      }
      let literal = text(start..<position)
      if !isDouble, let value = Int(literal) {
         return .number(.int(value))
      }
      return .number(.double(Double(literal) ?? 0))
   }

   /// A single- or double-quoted string, with `\n`, `\t`, `\r` and `\<char>`
   /// escapes.
   private mutating func scanString() throws -> String {
      let start = position
      let quote = bytes[position]
      position += 1
      var value: [UInt8] = []
      while position < bytes.count {
         let byte = bytes[position]
         position += 1
         if byte == quote {
            return String(decoding: value, as: UTF8.self)
         }
         if byte == UInt8(ascii: "\\"), position < bytes.count {
            let escaped = bytes[position]
            position += 1
            switch escaped {
            case UInt8(ascii: "n"): value.append(UInt8(ascii: "\n"))
            case UInt8(ascii: "t"): value.append(UInt8(ascii: "\t"))
            case UInt8(ascii: "r"): value.append(UInt8(ascii: "\r"))
            default: value.append(escaped)
            }
         }
         else {
            value.append(byte)
         }
      }
      throw ExpressionError(message: "Unterminated string", offset: start)
   }

   private mutating func scanName() -> String {
      let start = position
      while position < bytes.count, bytes[position].isIdentifierPart {
         position += 1
      }
      return text(start..<position)
   }
}

// MARK: - Parser

/// Recursive descent over the tokens, lowest precedence first:
///
///     or             := and (("OR" | "||") and)*
///     and            := not (("AND" | "&&") not)*
///     not            := ("NOT" | "!") not | comparison
///     comparison     := additive (operator ("[c]" | "[d]" | "[cd]")? additive)?
///     additive       := multiplicative (("+" | "-") multiplicative)*
///     multiplicative := unary (("*" | "/" | "%") unary)*
///     unary          := ("-" | "+") unary | postfix
///     postfix        := primary ("." name | "." name call | "." @operator | "[" or "]" | "|" name call?)*
///     primary        := number | string | keyword | name | name call | @operator
///                     | "(" or ")" | "{" list "}" | "[" list "]"
///     call           := "(" (or ("," or)*)? ")"
///
/// Calls name a registered function. `value.name(a, b)`, `value | name(a, b)`
/// and `name(value, a, b)` all mean the same thing: call `name` with `value`
/// as the receiver. A pipe binds as tightly as `.`, so `name | lowercase ==
/// "x"` compares the lowercased name.
struct ExpressionParser {
   private let tokens: [Token]
   private let locals: [String]
   private let functions: Functions
   private var position = 0

   init(source: String, locals: [String], functions: Functions) throws {
      self.tokens = try Lexer.tokenize(source)
      self.locals = locals
      self.functions = functions
   }

   mutating func parse() throws -> Expr {
      if case .end = current.kind {
         throw error("Expected an expression")
      }
      let expr = try parseOr()
      if case .end = current.kind {
         return expr
      }
      if current.keyword == "AS" {
         throw error("Format with a pipe, as in 'value | date', not 'as'")
      }
      throw error("Unexpected \(describe(current))")
   }

   private var current: Token { tokens[position] }

   private mutating func advance() { position += 1 }

   private func error(_ message: String, at token: Token? = nil) -> ExpressionError {
      ExpressionError(message: message, offset: (token ?? current).offset)
   }

   private func describe(_ token: Token) -> String {
      switch token.kind {
      case .number(let v): return v.renderedString
      case .string(let v): return "\"\(v)\""
      case .identifier(let v): return v
      case .aggregate(let v): return "@" + v
      case .symbol(let v): return v
      case .end: return "end of expression"
      }
   }

   private func isSymbol(_ symbol: String) -> Bool {
      current.kind == .symbol(symbol)
   }

   private func isKeyword(_ keyword: String) -> Bool {
      current.keyword == keyword
   }

   private mutating func expect(_ symbol: String) throws {
      guard isSymbol(symbol) else {
         throw error("Expected '\(symbol)' but found \(describe(current))")
      }
      advance()
   }

   private mutating func parseOr() throws -> Expr {
      var lhs = try parseAnd()
      while isKeyword("OR") || isSymbol("||") {
         advance()
         lhs = .or(lhs, try parseAnd())
      }
      return lhs
   }

   private mutating func parseAnd() throws -> Expr {
      var lhs = try parseNot()
      while isKeyword("AND") || isSymbol("&&") {
         advance()
         lhs = .and(lhs, try parseNot())
      }
      return lhs
   }

   private mutating func parseNot() throws -> Expr {
      if isKeyword("NOT") || isSymbol("!") {
         advance()
         return .not(try parseNot())
      }
      return try parseComparison()
   }

   private mutating func parseComparison() throws -> Expr {
      let lhs = try parseAdditive()
      let op: ComparisonOperator

      switch current.kind {
      case .symbol("=="), .symbol("="): op = .equal
      case .symbol("!="), .symbol("<>"): op = .notEqual
      case .symbol("<"): op = .less
      case .symbol("<="), .symbol("=<"): op = .lessOrEqual
      case .symbol(">"): op = .greater
      case .symbol(">="), .symbol("=>"): op = .greaterOrEqual
      case .identifier:
         switch current.keyword {
         case "BETWEEN": op = .between
         case "IN": op = .in
         case "CONTAINS": op = .contains
         case "BEGINSWITH": op = .beginsWith
         case "ENDSWITH": op = .endsWith
         case "LIKE": op = .like
         case "MATCHES": op = .matches
         default:
            return lhs
         }
      default:
         return lhs
      }
      advance()

      let options = parseStringOptions()
      let rhsToken = current
      let rhs = try parseAdditive()
      // A pattern written in the template is checked now, so a bad one fails
      // when the template is created rather than never matching.
      if op == .matches, case .literal(.string(let pattern)) = rhs,
         wholeStringRegex(pattern, options) == nil {
         throw error("Invalid regular expression \"\(pattern)\"", at: rhsToken)
      }
      return .comparison(op, options, lhs, rhs)
   }

   /// Reads a `[c]`, `[d]` or `[cd]` suffix after a comparison operator.
   private mutating func parseStringOptions() -> StringOptions {
      guard isSymbol("["), position + 3 < tokens.count,
            case .identifier = tokens[position + 1].kind,
            tokens[position + 2].kind == .symbol("]") else {
         return []
      }
      let flags = tokens[position + 1].keyword
      guard !flags.isEmpty, flags.allSatisfy({ $0 == "C" || $0 == "D" }), startsOperand(tokens[position + 3]) else {
         // Without an operand after it, `[c]` is a list, as in `x IN [c]`.
         return []
      }
      position += 3
      var options: StringOptions = []
      if flags.contains("C") { options.insert(.caseInsensitive) }
      if flags.contains("D") { options.insert(.diacriticInsensitive) }
      return options
   }

   /// Whether `token` can begin the operand of a comparison.
   private func startsOperand(_ token: Token) -> Bool {
      switch token.kind {
      case .number, .string, .aggregate:
         return true
      case .identifier:
         return !["AND", "OR"].contains(token.keyword)
      case .symbol(let symbol):
         return ["(", "{", "[", "-", "+"].contains(symbol)
      case .end:
         return false
      }
   }

   private mutating func parseAdditive() throws -> Expr {
      var lhs = try parseMultiplicative()
      while true {
         if isSymbol("+") {
            advance()
            lhs = .arithmetic(.add, lhs, try parseMultiplicative())
         }
         else if isSymbol("-") {
            advance()
            lhs = .arithmetic(.subtract, lhs, try parseMultiplicative())
         }
         else {
            return lhs
         }
      }
   }

   private mutating func parseMultiplicative() throws -> Expr {
      var lhs = try parseUnary()
      while true {
         let op: ArithmeticOperator
         if isSymbol("*") { op = .multiply }
         else if isSymbol("/") { op = .divide }
         else if isSymbol("%") { op = .modulo }
         else { return lhs }
         advance()
         lhs = .arithmetic(op, lhs, try parseUnary())
      }
   }

   private mutating func parseUnary() throws -> Expr {
      if isSymbol("-") {
         advance()
         let operand = try parseUnary()
         if case .literal(.int(let v)) = operand { return .literal(.int(-v)) }
         if case .literal(.double(let v)) = operand { return .literal(.double(-v)) }
         return .negate(operand)
      }
      if isSymbol("+") {
         advance()
         return try parseUnary()
      }
      return try parsePostfix()
   }

   private mutating func parsePostfix() throws -> Expr {
      var startsWithIdentifier = false
      if case .identifier = current.kind { startsWithIdentifier = true }
      var base = try parsePrimary()
      var steps: [PathStep] = []

      // Identifiers come back from parsePrimary as a path already; keep
      // appending to it so `a.b[0].c` is one path.
      if startsWithIdentifier, case .path(let pathBase, let pathSteps) = base {
         base = pathBase
         steps = pathSteps
      }

      // Ends the path so far, making it the receiver of a call.
      func receiver() -> Expr {
         defer { steps = [] }
         return steps.isEmpty ? base : .path(base, steps)
      }

      while true {
         if isSymbol(".") {
            advance()
            switch current.kind {
            case .identifier(let name):
               let token = current
               advance()
               if isSymbol("(") {
                  base = try parseCall(name, at: token, receiver: receiver())
               }
               else {
                  steps.append(.key(name))
               }
            case .aggregate(let name):
               steps.append(.aggregate(try aggregate(named: name)))
               advance()
            default:
               throw error("Expected a key after '.' but found \(describe(current))")
            }
         }
         else if isSymbol("|") {
            advance()
            guard case .identifier(let name) = current.kind else {
               throw error("Expected a function name after '|' but found \(describe(current))")
            }
            let token = current
            advance()
            base = try parseCall(name, at: token, receiver: receiver())
         }
         else if isSymbol("[") {
            advance()
            if position + 1 < tokens.count, tokens[position + 1].kind == .symbol("]"), ["FIRST", "LAST", "SIZE"].contains(current.keyword) {
               switch current.keyword {
               case "FIRST": steps.append(.first)
               case "LAST": steps.append(.last)
               default: steps.append(.size)
               }
               advance()
            }
            else {
               steps.append(.index(try parseOr()))
            }
            try expect("]")
         }
         else {
            break
         }
      }

      return steps.isEmpty ? base : .path(base, steps)
   }

   private mutating func parsePrimary() throws -> Expr {
      let token = current
      switch token.kind {
      case .number(let v):
         advance()
         return .literal(v)

      case .string(let v):
         advance()
         return .literal(.string(v))

      case .aggregate(let name):
         // A bare operator applies to the root object, like `@count`.
         advance()
         return .path(.root, [.aggregate(try aggregate(named: name, at: token))])

      case .identifier(let name):
         advance()
         if isSymbol("(") {
            // `name(value, args...)` is `value.name(args...)`. Any registered
            // name can be called, keywords included.
            var arguments = try parseArguments()
            let receiver: Expr = arguments.isEmpty ? .literal(.null) : arguments.removeFirst()
            return .function(try lookUpFunction(name, at: token), receiver: receiver, arguments: arguments)
         }
         switch token.keyword {
         case "TRUE", "YES": return .literal(.bool(true))
         case "FALSE", "NO": return .literal(.bool(false))
         case "NIL", "NULL": return .literal(.null)
         case "SELF": return .root
         case "AND", "OR", "BETWEEN", "IN", "CONTAINS", "BEGINSWITH", "ENDSWITH", "LIKE", "MATCHES":
            throw error("Unexpected \(name)", at: token)
         case "ANY", "ALL", "SOME", "NONE", "SUBQUERY", "CAST", "TERNARY":
            throw error("\(token.keyword) is not supported", at: token)
         default:
            break
         }
         if let slot = locals.lastIndex(of: name) {
            return .local(slot)
         }
         return .path(.root, [.key(name)])

      case .symbol("("):
         advance()
         let inner = try parseOr()
         try expect(")")
         return inner

      case .symbol("{"):
         advance()
         return .list(try parseList(closing: "}"))

      case .symbol("["):
         advance()
         return .list(try parseList(closing: "]"))

      default:
         throw error("Unexpected \(describe(token))")
      }
   }

   /// A call to `name` on `receiver`, after the name: `(arguments...)`, or
   /// nothing at all after a pipe.
   private mutating func parseCall(_ name: String, at token: Token, receiver: Expr) throws -> Expr {
      let function = try lookUpFunction(name, at: token)
      let arguments = try isSymbol("(") ? parseArguments() : []
      return .function(function, receiver: receiver, arguments: arguments)
   }

   /// `(a, b, ...)`, including the parentheses.
   private mutating func parseArguments() throws -> [Expr] {
      try expect("(")
      return try parseList(closing: ")")
   }

   private func lookUpFunction(_ name: String, at token: Token) throws -> Functions.Function {
      guard let function = functions[name] else {
         throw error("Unknown function \(name)()", at: token)
      }
      return function
   }

   private mutating func parseList(closing: String) throws -> [Expr] {
      var elements: [Expr] = []
      if isSymbol(closing) {
         advance()
         return elements
      }
      while true {
         elements.append(try parseOr())
         if isSymbol(",") {
            advance()
            continue
         }
         try expect(closing)
         return elements
      }
   }

   private func aggregate(named name: String, at token: Token? = nil) throws -> Aggregate {
      guard let aggregate = Aggregate(rawValue: name.lowercased()) else {
         throw error("Unsupported collection operator @\(name)", at: token)
      }
      return aggregate
   }
}

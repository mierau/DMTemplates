// StringCheese
// Dustin Mierau
// Cared for under the MIT license.

/// A template's structure as parsed, before it's compiled into a `Program`.
struct ParsedTemplate {
   let nodes: [Node]

   /// How many variable slots rendering needs.
   let localCount: Int
}

enum Node {
   case text(String)
   case value(TagExpression)
   case conditional([Branch], otherwise: [Node]?)
   /// `otherwise` runs when the sequence is empty.
   case loop(slot: Int, sequence: TagExpression, body: [Node], otherwise: [Node]?)
   case log(TagExpression)
   /// `set name = value`: stores the value in a variable's slot.
   case set(slot: Int, TagExpression)
}

/// An `if` or `elseif` and the nodes it guards.
struct Branch {
   let condition: TagExpression
   let body: [Node]
}

/// A tag's compiled expression, and the line its tag is on.
struct TagExpression {
   /// A syntax tree from the built-in language, or whatever a custom
   /// `ExpressionCompiler` returned.
   enum Kind {
      case native(Expr)
      case custom(any CompiledExpression)
   }

   let kind: Kind
   let line: Int
}

/// Splits a template into text and tags and builds the node tree.
///
/// Positions are byte offsets into the source's UTF-8, turned into lines and
/// columns only when reporting an error.
struct TemplateParser {
   private let source: SourceText
   private let beginDelimiter: [UInt8]
   private let endDelimiter: [UInt8]
   private let compileExpression: (_ source: String, _ locals: [String]) throws -> TagExpression.Kind

   // The parser deliberately holds no existentials (such as
   // `TemplateOptions.expressionCompiler`): they make the struct address-only,
   // and its byte scanning many times slower.

   /// Blocks still open, innermost last. The first is the template itself.
   private var blocks: [Block] = [Block(kind: .root, offset: 0)]

   /// Variable names by slot. Slots are never reused, so a variable's slot
   /// starts out nil, and a variable that goes out of scope keeps its slot
   /// with its name blanked, so it can't be found.
   private var locals: [String] = []

   /// The line `lineOffset` is on. Tags are read in order, so finding a tag's
   /// line only counts the newlines since the last one.
   private var line = 1
   private var lineOffset = 0

   private struct Block {
      enum Kind {
         case root
         case conditional
         case loop(slot: Int, sequence: TagExpression)
      }

      let kind: Kind
      /// Where the opening tag is, for errors about it.
      let offset: Int
      /// Loops: the slots variables in scope had when the loop opened. Ones
      /// added after go out of scope when the loop's body ends.
      var scope = 0
      /// The nodes collected so far, for the branch being read.
      var nodes: [Node] = []
      /// Conditionals: finished `if` and `elseif` branches.
      var branches: [Branch] = []
      /// Conditionals: the condition of the branch being read, or nil once
      /// past `else`.
      var condition: TagExpression?
      /// Loops: the loop's body, once past `else`.
      var loopBody: [Node]?
   }

   private enum Tag {
      case value(Range<Int>)
      case `if`(Range<Int>)
      case elseIf(Range<Int>)
      case `else`
      case endIf
      case forEach(Range<Int>)
      case endForEach
      case end
      case log(Range<Int>)
      case set(Range<Int>)
      case comment
   }

   static func parse(_ source: String, options: TemplateOptions) throws -> ParsedTemplate {
      var parser = TemplateParser(source: source, options: options)
      return try parser.parse()
   }

   private init(source: String, options: TemplateOptions) {
      self.source = SourceText(source)
      self.beginDelimiter = Array(options.beginDelimiter.utf8)
      self.endDelimiter = Array(options.endDelimiter.utf8)

      if var compiler = options.expressionCompiler as? NativeExpressionCompiler {
         // Formatting functions depend on the options' locale, time zone and
         // currency. The app's functions win over them.
         compiler.functions = compiler.functions.falling(backOn: .formatting(for: options))
         let native = compiler
         // Keep the syntax tree; the program compiles it alongside the
         // template's other expressions.
         self.compileExpression = { source, locals in
            .native(try native.parse(source, locals: locals))
         }
      }
      else {
         let compiler = options.expressionCompiler
         self.compileExpression = { source, locals in
            let compiled = try compiler.compile(source, locals: locals)
            if let native = compiled as? NativeExpression {
               return .native(native.syntax)
            }
            return .custom(compiled)
         }
      }
   }

   private mutating func parse() throws -> ParsedTemplate {
      guard !beginDelimiter.isEmpty, !endDelimiter.isEmpty else {
         throw TemplateError(message: "Delimiters can't be empty", line: 1, column: 1)
      }

      var cursor = 0
      var swallowNewline = false
      var trimNext = false

      while cursor < source.count {
         let tagStart = source.find(beginDelimiter, from: cursor) ?? source.count
         var contentStart = tagStart + beginDelimiter.count
         // `{%-` trims the whitespace before the tag, and `-%}` the
         // whitespace after it, line breaks included.
         let trimBefore = contentStart < source.count && source.bytes[contentStart] == UInt8(ascii: "-")
         if trimBefore {
            contentStart += 1
         }

         var textStart = cursor
         var textEnd = tagStart
         if trimNext {
            while textStart < textEnd, source.bytes[textStart].isSpace {
               textStart += 1
            }
         }
         else if swallowNewline {
            // Control tags swallow the newline right after them, so a tag on
            // its own line doesn't leave a blank line behind.
            textStart = source.skippingNewline(at: textStart, before: tagStart)
         }
         if trimBefore {
            while textEnd > textStart, source.bytes[textEnd - 1].isSpace {
               textEnd -= 1
            }
         }
         if textStart < textEnd {
            appendText(source.text(textStart..<textEnd))
         }

         guard tagStart < source.count else {
            break
         }
         guard var contentEnd = source.find(endDelimiter, from: contentStart) else {
            throw error("Tag is missing its closing \(String(decoding: endDelimiter, as: UTF8.self))", at: tagStart)
         }
         cursor = contentEnd + endDelimiter.count
         trimNext = contentEnd > contentStart && source.bytes[contentEnd - 1] == UInt8(ascii: "-")
         if trimNext {
            contentEnd -= 1
         }
         swallowNewline = try handleTag(contentStart..<contentEnd)
      }

      if blocks.count > 1 {
         let block = blocks[blocks.count - 1]
         if case .loop = block.kind {
            throw error("foreach is never closed", at: block.offset)
         }
         throw error("if is never closed", at: block.offset)
      }

      return ParsedTemplate(nodes: blocks[0].nodes, localCount: locals.count)
   }

   /// Handles one tag's content. Returns whether the tag swallows the newline
   /// after it, which every tag but a value does.
   private mutating func handleTag(_ content: Range<Int>) throws -> Bool {
      let content = source.trimmed(content)
      if content.isEmpty {
         return false
      }

      let tag = try classify(content)

      let offset = content.lowerBound
      switch tag {
      case .value(let expression):
         append(.value(try compile(expression)))
         return false

      case .if(let condition):
         blocks.append(Block(kind: .conditional, offset: offset, condition: try compile(condition)))

      case .elseIf(let condition):
         let compiled = try compile(condition)
         try continueConditional(at: offset, tag: "elseif", nextCondition: compiled)

      case .else:
         if case .loop = blocks[blocks.count - 1].kind {
            try startLoopElse(at: offset)
         }
         else {
            try continueConditional(at: offset, tag: "else", nextCondition: nil)
         }

      case .endIf:
         try closeConditional(at: offset, tag: "endif")

      case .forEach(let statement):
         try openLoop(statement, at: offset)

      case .endForEach:
         try closeLoop(at: offset, tag: "endforeach")

      case .end:
         if case .loop = blocks[blocks.count - 1].kind {
            try closeLoop(at: offset, tag: "end")
         }
         else {
            try closeConditional(at: offset, tag: "end")
         }

      case .log(let expression):
         append(.log(try compile(expression)))

      case .set(let statement):
         try set(statement, at: offset)

      case .comment:
         break
      }

      return true
   }

   // MARK: Tags

   /// Identifies a tag by its keyword, ignoring case. Tags that take a
   /// statement in parentheses, like `if( this )`, come back with it.
   private func classify(_ content: Range<Int>) throws -> Tag {
      if source.bytes[content.lowerBound] == UInt8(ascii: "#") { return .comment }
      if let statement = try call("if", in: content, bare: true) { return .if(statement) }
      if let statement = try call("elseif", in: content, bare: true) { return .elseIf(statement) }
      if let statement = try elseIf(in: content) { return .elseIf(statement) }
      if isWord("else", content) { return .else }
      if isWord("endif", content) { return .endIf }
      if isWord("endforeach", content) { return .endForEach }
      if isWord("end", content) { return .end }
      if let statement = try call("foreach", in: content, bare: true) { return .forEach(statement) }
      if let statement = try call("log", in: content) { return .log(statement) }
      if let statement = keyword("set", in: content) { return .set(statement) }
      return .value(content)
   }

   private func isWord(_ word: String, _ content: Range<Int>) -> Bool {
      content.count == word.utf8.count && source.matches(word, at: content.lowerBound, before: content.upperBound)
   }

   /// If `content` is `name( ... )`, the expression after the name: what's
   /// inside the parentheses when they wrap the rest of the tag, as in
   /// `if(a)`, or else everything from the `(` on, as in `if (a) or (b)`.
   /// With `bare`, the parentheses are optional, as in `if a`.
   private func call(_ name: String, in content: Range<Int>, bare: Bool = false) throws -> Range<Int>? {
      guard source.matches(name, at: content.lowerBound, before: content.upperBound) else {
         return nil
      }
      var paren = content.lowerBound + name.utf8.count
      while paren < content.upperBound, source.bytes[paren].isSpace {
         paren += 1
      }
      guard paren < content.upperBound, source.bytes[paren] == UInt8(ascii: "(") else {
         // `if x`: the keyword, a space and an expression.
         let spaced = paren > content.lowerBound + name.utf8.count
         return bare && spaced && paren < content.upperBound ? paren..<content.upperBound : nil
      }
      let close = source.closingParenthesis(from: paren, before: content.upperBound)
      if close == content.upperBound - 1 {
         let statement = source.trimmed((paren + 1)..<(content.upperBound - 1))
         guard !statement.isEmpty else {
            throw error("Expected an expression inside ( )", at: paren)
         }
         return statement
      }
      guard close != nil else {
         throw error("Expected ) at the end of the tag", at: content.upperBound - 1)
      }
      return paren..<content.upperBound
   }

   /// If `content` is `name` followed by a space and more, what's after it.
   private func keyword(_ name: String, in content: Range<Int>) -> Range<Int>? {
      let end = content.lowerBound + name.utf8.count
      guard end < content.upperBound, source.bytes[end].isSpace,
            source.matches(name, at: content.lowerBound, before: content.upperBound) else {
         return nil
      }
      return source.trimmed(end..<content.upperBound)
   }

   /// `else if( ... )`, the spelling the earlier Swift draft used.
   private func elseIf(in content: Range<Int>) throws -> Range<Int>? {
      guard source.matches("else", at: content.lowerBound, before: content.upperBound) else {
         return nil
      }
      var next = content.lowerBound + 4
      guard next < content.upperBound, source.bytes[next].isSpace else {
         return nil
      }
      while next < content.upperBound, source.bytes[next].isSpace {
         next += 1
      }
      return try call("if", in: next..<content.upperBound, bare: true)
   }

   // MARK: Blocks

   private mutating func append(_ node: Node) {
      blocks[blocks.count - 1].nodes.append(node)
   }

   private mutating func appendText(_ text: String) {
      // Merge with preceding text so rendering writes it in one go.
      if case .text(let previous)? = blocks[blocks.count - 1].nodes.last {
         blocks[blocks.count - 1].nodes.removeLast()
         append(.text(previous + text))
      }
      else {
         append(.text(text))
      }
   }

   /// Ends the current branch of the open conditional and starts the next:
   /// another condition for `elseif`, or nil for `else`.
   private mutating func continueConditional(at offset: Int, tag: String, nextCondition: TagExpression?) throws {
      let block = try openConditional(at: offset, tag: tag)
      guard let condition = block.condition else {
         throw error("\(tag) after else", at: offset)
      }
      blocks[blocks.count - 1].branches.append(Branch(condition: condition, body: block.nodes))
      blocks[blocks.count - 1].nodes = []
      blocks[blocks.count - 1].condition = nextCondition
   }

   private mutating func closeConditional(at offset: Int, tag: String) throws {
      var block = try openConditional(at: offset, tag: tag)
      blocks.removeLast()
      if let condition = block.condition {
         block.branches.append(Branch(condition: condition, body: block.nodes))
         append(.conditional(block.branches, otherwise: nil))
      }
      else {
         append(.conditional(block.branches, otherwise: block.nodes))
      }
   }

   private func openConditional(at offset: Int, tag: String) throws -> Block {
      let block = blocks[blocks.count - 1]
      guard case .conditional = block.kind else {
         throw error("\(tag) without a matching if", at: offset)
      }
      return block
   }

   /// `foreach(item in items)`. The loop gets four slots: the item, its
   /// index as `itemIndex`, and whether it's the first or last as
   /// `itemIsFirst` and `itemIsLast`.
   private mutating func openLoop(_ statement: Range<Int>, at offset: Int) throws {
      guard let separator = source.findWord("in", in: statement) else {
         throw error("foreach needs the form foreach(item in items)", at: offset)
      }
      let nameRange = source.trimmed(statement.lowerBound..<separator.lowerBound)
      let name = source.text(nameRange)
      guard let first = name.utf8.first, first.isIdentifierStart, name.utf8.allSatisfy(\.isIdentifierPart) else {
         throw error("'\(name)' isn't a valid loop variable name", at: nameRange.lowerBound)
      }

      // The sequence is evaluated outside the loop, so compile it before the
      // loop's variables come into scope.
      let sequence = try compile(source.trimmed(separator.upperBound..<statement.upperBound))
      let scope = locals.count
      locals += [name, name + "Index", name + "IsFirst", name + "IsLast"]
      blocks.append(Block(kind: .loop(slot: scope, sequence: sequence), offset: offset, scope: scope))
   }

   /// `else` in a loop: what follows runs when there's nothing to loop over.
   private mutating func startLoopElse(at offset: Int) throws {
      guard blocks[blocks.count - 1].loopBody == nil else {
         throw error("else after else", at: offset)
      }
      blocks[blocks.count - 1].loopBody = blocks[blocks.count - 1].nodes
      blocks[blocks.count - 1].nodes = []
      // The loop's variables have no value here.
      endScope(at: blocks[blocks.count - 1].scope)
   }

   private mutating func closeLoop(at offset: Int, tag: String) throws {
      guard case .loop(let slot, let sequence) = blocks[blocks.count - 1].kind else {
         throw error("\(tag) without a matching foreach", at: offset)
      }
      let block = blocks.removeLast()
      if let body = block.loopBody {
         append(.loop(slot: slot, sequence: sequence, body: body, otherwise: block.nodes))
      }
      else {
         endScope(at: block.scope)
         append(.loop(slot: slot, sequence: sequence, body: block.nodes, otherwise: nil))
      }
   }

   /// Hides the variables from `scope` on.
   private mutating func endScope(at scope: Int) {
      for slot in scope..<locals.count {
         locals[slot] = ""
      }
   }

   /// `set name = value`. A variable already in scope gets the new value, so
   /// a loop can add to a total set before it; otherwise the name is new,
   /// and in scope until the end of the loop it's set in, or of the template.
   private mutating func set(_ statement: Range<Int>, at offset: Int) throws {
      var nameEnd = statement.lowerBound
      while nameEnd < statement.upperBound, source.bytes[nameEnd].isIdentifierPart {
         nameEnd += 1
      }
      var equals = nameEnd
      while equals < statement.upperBound, source.bytes[equals].isSpace {
         equals += 1
      }
      guard nameEnd > statement.lowerBound, source.bytes[statement.lowerBound].isIdentifierStart,
            equals < statement.upperBound, source.bytes[equals] == UInt8(ascii: "="),
            equals + 1 == statement.upperBound || source.bytes[equals + 1] != UInt8(ascii: "=") else {
         throw error("set needs the form set name = value", at: offset)
      }
      let value = source.trimmed((equals + 1)..<statement.upperBound)
      guard !value.isEmpty else {
         throw error("Expected a value after =", at: equals)
      }
      // Compiled before the name is in scope, so `set count = count + 1`
      // starts from the context's `count`.
      let expression = try compile(value)
      let name = source.text(statement.lowerBound..<nameEnd)
      let slot: Int
      if let existing = locals.lastIndex(of: name) {
         slot = existing
      }
      else {
         slot = locals.count
         locals.append(name)
      }
      append(.set(slot: slot, expression))
   }

   // MARK: Expressions

   private mutating func compile(_ range: Range<Int>) throws -> TagExpression {
      let expression = source.text(range)
      do {
         return TagExpression(kind: try compileExpression(expression, locals), line: line(at: range.lowerBound))
      }
      catch let problem as ExpressionError {
         throw error("\(problem.message) in '\(expression)'", at: range.lowerBound + problem.offset)
      }
      catch {
         throw self.error("\(error) in '\(expression)'", at: range.lowerBound)
      }
   }

   private mutating func line(at offset: Int) -> Int {
      if offset < lineOffset {
         line = 1
         lineOffset = 0
      }
      for index in lineOffset..<offset where source.bytes[index] == UInt8(ascii: "\n") {
         line += 1
      }
      lineOffset = offset
      return line
   }

   private func error(_ message: String, at offset: Int) -> TemplateError {
      let (line, column) = source.location(of: offset)
      return TemplateError(message: message, line: line, column: column)
   }
}

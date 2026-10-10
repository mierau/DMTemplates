// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

/// A template's structure as parsed, before it's compiled into a `Program`.
struct ParsedTemplate {
   let nodes: [Node]

   /// How many loop variable slots rendering needs.
   let localCount: Int
}

enum Node {
   case text(String)
   case value(TagExpression)
   case conditional([Branch], otherwise: [Node]?)
   case loop(slot: Int, sequence: TagExpression, body: [Node])
   case log(TagExpression)
}

/// An `if` or `elseif` and the nodes it guards.
struct Branch {
   let condition: TagExpression
   let body: [Node]
}

/// A tag's compiled expression: a syntax tree from the built-in language, or
/// whatever a custom `ExpressionCompiler` returned.
enum TagExpression {
   case native(Expr)
   case custom(any CompiledExpression)
}

/// Splits a template into text and tags and builds the node tree.
///
/// Positions are byte offsets into the source's UTF-8, turned into lines and
/// columns only when reporting an error.
struct TemplateParser {
   private let source: SourceText
   private let beginDelimiter: [UInt8]
   private let endDelimiter: [UInt8]
   private let compileExpression: (_ source: String, _ locals: [String]) throws -> TagExpression

   // The parser deliberately holds no existentials (such as
   // `TemplateOptions.expressionCompiler`): they make the struct address-only,
   // and its byte scanning many times slower.

   /// Blocks still open, innermost last. The first is the template itself.
   private var blocks: [Block] = [Block(kind: .root, offset: 0)]

   /// Loop variables in scope, by slot.
   private var locals: [String] = []
   private var localCount = 0

   private struct Block {
      enum Kind {
         case root
         case conditional
         case loop(slot: Int, sequence: TagExpression)
      }

      let kind: Kind
      /// Where the opening tag is, for errors about it.
      let offset: Int
      /// The nodes collected so far, for the branch being read.
      var nodes: [Node] = []
      /// Conditionals: finished `if` and `elseif` branches.
      var branches: [Branch] = []
      /// Conditionals: the condition of the branch being read, or nil once
      /// past `else`.
      var condition: TagExpression?
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

      while cursor < source.count {
         let tagStart = source.find(beginDelimiter, from: cursor) ?? source.count

         var textStart = cursor
         if swallowNewline {
            // Control tags swallow the newline right after them, so a tag on
            // its own line doesn't leave a blank line behind.
            textStart = source.skippingNewline(at: textStart, before: tagStart)
         }
         if textStart < tagStart {
            appendText(source.text(textStart..<tagStart))
         }

         guard tagStart < source.count else {
            break
         }
         let contentStart = tagStart + beginDelimiter.count
         guard let contentEnd = source.find(endDelimiter, from: contentStart) else {
            throw error("Tag is missing its closing \(String(decoding: endDelimiter, as: UTF8.self))", at: tagStart)
         }
         cursor = contentEnd + endDelimiter.count
         swallowNewline = try handleTag(contentStart..<contentEnd)
      }

      if blocks.count > 1 {
         let block = blocks[blocks.count - 1]
         if case .loop = block.kind {
            throw error("foreach is never closed", at: block.offset)
         }
         throw error("if is never closed", at: block.offset)
      }

      return ParsedTemplate(nodes: blocks[0].nodes, localCount: localCount)
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
         try continueConditional(at: offset, tag: "else", nextCondition: nil)

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
      }

      return true
   }

   // MARK: Tags

   /// Identifies a tag by its keyword, ignoring case. Tags that take a
   /// statement in parentheses, like `if( this )`, come back with it.
   private func classify(_ content: Range<Int>) throws -> Tag {
      if let statement = try call("if", in: content, bare: true) { return .if(statement) }
      if let statement = try call("elseif", in: content, bare: true) { return .elseIf(statement) }
      if let statement = try elseIf(in: content) { return .elseIf(statement) }
      if isWord("else", content) { return .else }
      if isWord("endif", content) { return .endIf }
      if isWord("endforeach", content) { return .endForEach }
      if isWord("end", content) { return .end }
      if let statement = try call("foreach", in: content, bare: true) { return .forEach(statement) }
      if let statement = try call("log", in: content) { return .log(statement) }
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

   /// `foreach(item in items)`. The loop gets two slots: the item, and its
   /// index as `itemIndex`.
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
      let slot = locals.count
      locals.append(name)
      locals.append(name + "Index")
      localCount = max(localCount, locals.count)
      blocks.append(Block(kind: .loop(slot: slot, sequence: sequence), offset: offset))
   }

   private mutating func closeLoop(at offset: Int, tag: String) throws {
      guard case .loop(let slot, let sequence) = blocks[blocks.count - 1].kind else {
         throw error("\(tag) without a matching foreach", at: offset)
      }
      let block = blocks.removeLast()
      locals.removeLast(2)
      append(.loop(slot: slot, sequence: sequence, body: block.nodes))
   }

   // MARK: Expressions

   private func compile(_ range: Range<Int>) throws -> TagExpression {
      let expression = source.text(range)
      do {
         return try compileExpression(expression, locals)
      }
      catch let problem as ExpressionError {
         throw error("\(problem.message) in '\(expression)'", at: range.lowerBound + problem.offset)
      }
      catch {
         throw self.error("\(error) in '\(expression)'", at: range.lowerBound)
      }
   }

   private func error(_ message: String, at offset: Int) -> TemplateError {
      let (line, column) = source.location(of: offset)
      return TemplateError(message: message, line: line, column: column)
   }
}

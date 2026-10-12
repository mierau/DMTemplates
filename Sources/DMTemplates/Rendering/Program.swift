// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

/// A template compiled to a flat list of instructions, with its text and
/// expressions alongside.
///
/// Like `ExpressionCode`, everything is written once and only read while
/// rendering, so any number of threads can run the same program, and running
/// it touches no reference counts the program owns.
final class Program: @unchecked Sendable {
   enum Instruction {
      /// Writes `text[range]`.
      case text(Span)
      /// Writes an expression's value, escaped as the options ask unless
      /// `raw`.
      case value(ExpressionRef, raw: Bool)
      /// Continues if the expression is truthy, otherwise jumps to `otherwise`.
      case branch(ExpressionRef, otherwise: Int32)
      case jump(Int32)
      /// Starts looping over the expression's elements, or a dictionary's
      /// entries, or jumps to `exit` when there are none.
      case loop(ExpressionRef, slot: Int32, exit: Int32)
      /// Moves to the loop's next element and jumps back to `body`, or falls
      /// through when done.
      case next(slot: Int32, body: Int32)
      case log(ExpressionRef)
      /// Stores the expression's value in a variable's slot.
      case set(ExpressionRef, slot: Int32)
   }

   /// Where an instruction's expression lives.
   enum ExpressionRef {
      /// An operation in `code`.
      case native(Int32)
      /// An expression from a custom compiler, in `custom`.
      case custom(Int32)
   }

   private let instructions: UnsafeMutableBufferPointer<Instruction>
   /// The template line of each instruction's tag, for messages.
   private let lines: UnsafeMutableBufferPointer<Int32>
   private let text: UnsafeMutableBufferPointer<UInt8>
   private let custom: UnsafeMutableBufferPointer<any CompiledExpression>
   private let code: ExpressionCode
   private let localCount: Int
   private let escaping: Escaping.Kind
   private let log: @Sendable (String) -> Void

   init(_ template: ParsedTemplate, options: TemplateOptions) {
      var builder = Builder(options: options)
      builder.add(template.nodes)
      self.instructions = .copying(builder.instructions)
      self.lines = .copying(builder.lines)
      self.text = .copying(builder.text)
      self.custom = .copying(builder.custom)
      self.code = ExpressionCode(builder.code)
      self.localCount = template.localCount
      self.escaping = options.escaping.kind
      self.log = options.log
   }

   deinit {
      instructions.release()
      lines.release()
      text.release()
      custom.release()
   }

   // MARK: Running

   /// A loop in progress.
   private struct Loop {
      let items: [TemplateValue]
      var index: Int
   }

   /// Renders into `output`.
   func run(_ context: TemplateValue, features: RenderFeatures, into output: inout [UInt8]) {
      run(context, features: features, into: &output, flushingAt: .max) { _ in }
   }

   /// Renders into `output`. When `output` reaches `limit` bytes, `flush` is
   /// called to take what's there, so long output can stream.
   func run(_ context: TemplateValue, features: RenderFeatures, into output: inout [UInt8], flushingAt limit: Int, _ flush: (inout [UInt8]) throws -> Void) rethrows {
      let interpreter = code.interpreter
      var scope = ExpressionScope(root: context, features: features, localCount: localCount)
      let missingKeys = features.contains(.strict) ? MissingKeys() : nil
      var loops: [Loop] = []
      output.reserveCapacity(min(text.count * 3 / 2, limit))

      var pc = 0
      var reported: Set<String> = []

      func evaluate(_ expression: ExpressionRef) -> TemplateValue {
         switch expression {
         case .native(let operation):
            if let missingKeys {
               interpreter.findMissingKeys(operation, in: scope, into: missingKeys)
               report(missingKeys, line: lines[pc], &reported)
            }
            return interpreter.evaluate(operation, in: scope)
         case .custom(let index):
            return custom[Int(index)].evaluate(in: scope)
         }
      }

      while pc < instructions.count {
         switch instructions[pc] {
         case .text(let span):
            output.append(contentsOf: UnsafeBufferPointer(rebasing: text[span.range]))
            if output.count >= limit { try flush(&output) }
            pc += 1

         case .value(let expression, let raw):
            write(evaluate(expression), raw: raw, to: &output)
            if output.count >= limit { try flush(&output) }
            pc += 1

         case .branch(let condition, let otherwise):
            pc = evaluate(condition).isTruthy ? pc + 1 : Int(otherwise)

         case .jump(let target):
            pc = Int(target)

         case .loop(let sequence, let slot, let exit):
            let items: [TemplateValue]
            switch evaluate(sequence).resolved {
            case .array(let elements):
               items = elements
            case .dictionary(let entries):
               // Each entry as `key` and `value`, in key order.
               items = entries.sorted { $0.key < $1.key }.map { .dictionary(["key": .string($0.key), "value": $0.value]) }
            default:
               items = []
            }
            guard !items.isEmpty else {
               pc = Int(exit)
               break
            }
            let slot = Int(slot)
            scope.locals[slot] = items[0]
            scope.locals[slot + 1] = .int(0)
            scope.locals[slot + 2] = .bool(true)
            scope.locals[slot + 3] = .bool(items.count == 1)
            loops.append(Loop(items: items, index: 0))
            pc += 1

         case .next(let slot, let body):
            let current = loops.count - 1
            loops[current].index += 1
            let index = loops[current].index
            if index < loops[current].items.count {
               let slot = Int(slot)
               scope.locals[slot] = loops[current].items[index]
               scope.locals[slot + 1] = .int(index)
               scope.locals[slot + 2] = .bool(false)
               scope.locals[slot + 3] = .bool(index == loops[current].items.count - 1)
               pc = Int(body)
            }
            else {
               loops.removeLast()
               pc += 1
            }

         case .log(let expression):
            if features.contains(.log) {
               let value = evaluate(expression)
               log(value == .null ? "nil" : value.renderedString)
            }
            pc += 1

         case .set(let expression, let slot):
            scope.locals[Int(slot)] = evaluate(expression)
            pc += 1
         }
      }
   }

   /// Logs the keys an expression found missing, each once per tag rather
   /// than once per time around a loop.
   private func report(_ missing: MissingKeys, line: Int32, _ reported: inout Set<String>) {
      guard !missing.messages.isEmpty else { return }
      for message in missing.messages {
         let message = "line \(line): \(message)"
         if reported.insert(message).inserted {
            log(message)
         }
      }
      missing.removeAll()
   }

   /// Writes a value tag's value, escaped as the options ask.
   private func write(_ value: TemplateValue, raw: Bool, to output: inout [UInt8]) {
      // Strings and whole numbers, the most common values, skip
      // `renderedString`.
      let text: String
      switch value {
      case .null:
         return
      case .int(let v):
         output.append(contentsOf: String(v).utf8)
         return
      case .bool, .double, .decimal:
         // Nothing in a number needs escaping.
         output.append(contentsOf: value.renderedString.utf8)
         return
      case .string(let v):
         text = v
      default:
         text = value.renderedString
      }
      switch raw ? .none : escaping {
      case .none:
         output.append(contentsOf: text.utf8)
      case .html:
         appendEscapingHTML(text, to: &output)
      case .custom(let transform):
         output.append(contentsOf: transform(text).utf8)
      }
   }

   // MARK: Building

   /// Compiles template nodes into instructions.
   private struct Builder {
      let options: TemplateOptions
      var instructions: [Instruction] = []
      var lines: [Int32] = []
      var text: [UInt8] = []
      var custom: [any CompiledExpression] = []
      var code = ExpressionCode.Builder()

      init(options: TemplateOptions) {
         self.options = options
      }

      /// The index the next instruction will get.
      private var next: Int32 { Int32(instructions.count) }

      private mutating func emit(_ instruction: Instruction, line: Int = 0) {
         instructions.append(instruction)
         lines.append(Int32(clamping: line))
      }

      mutating func add(_ nodes: [Node]) {
         for node in nodes {
            add(node)
         }
      }

      private mutating func add(_ node: Node) {
         switch node {
         case .text(let string):
            emit(.text(Span(start: text.count, count: string.utf8.count)))
            text.append(contentsOf: string.utf8)

         case .value(let expression):
            emit(.value(add(expression), raw: Self.isRaw(expression)), line: expression.line)

         case .conditional(let branches, let otherwise):
            // Each branch tests its condition and skips to the next branch when
            // false; a branch that runs jumps past the rest when done.
            // The last branch has nothing to skip when there's no else.
            var exits: [Int] = []
            for (number, branch) in branches.enumerated() {
               let condition = add(branch.condition)
               let test = instructions.count
               emit(.branch(condition, otherwise: -1), line: branch.condition.line)
               add(branch.body)
               if otherwise != nil || number < branches.count - 1 {
                  exits.append(instructions.count)
                  emit(.jump(-1))
               }
               instructions[test] = .branch(condition, otherwise: next)
            }
            if let otherwise {
               add(otherwise)
            }
            for exit in exits {
               instructions[exit] = .jump(next)
            }

         case .loop(let slot, let sequence, let body, let otherwise):
            // With an else, an empty sequence exits to it, and a finished loop
            // jumps past it.
            let expression = add(sequence)
            let start = instructions.count
            emit(.loop(expression, slot: Int32(slot), exit: -1), line: sequence.line)
            add(body)
            emit(.next(slot: Int32(slot), body: Int32(start + 1)))
            if let otherwise {
               let skip = instructions.count
               emit(.jump(-1))
               instructions[start] = .loop(expression, slot: Int32(slot), exit: next)
               add(otherwise)
               instructions[skip] = .jump(next)
            }
            else {
               instructions[start] = .loop(expression, slot: Int32(slot), exit: next)
            }

         case .log(let expression):
            emit(.log(add(expression)), line: expression.line)

         case .set(let slot, let expression):
            emit(.set(add(expression), slot: Int32(slot)), line: expression.line)
         }
      }

      /// Whether a value tag ends by calling `raw` or `escape`, so its
      /// output isn't escaped (again).
      private static func isRaw(_ expression: TagExpression) -> Bool {
         if case .native(.function(_, let name, _, _)) = expression.kind {
            return name == "raw" || name == "escape"
         }
         return false
      }

      private mutating func add(_ expression: TagExpression) -> ExpressionRef {
         switch expression.kind {
         case .native(let syntax):
            return .native(code.add(syntax))
         case .custom(let compiled):
            custom.append(compiled)
            return .custom(Int32(custom.count - 1))
         }
      }
   }
}

/// Appends `text` with `&`, `<`, `>`, `"` and `'` written as HTML entities.
private func appendEscapingHTML(_ text: String, to output: inout [UInt8]) {
   let needsEscaping = text.utf8.contains { byte in
      byte == UInt8(ascii: "&") || byte == UInt8(ascii: "<") || byte == UInt8(ascii: ">") || byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'")
   }
   guard needsEscaping else {
      output.append(contentsOf: text.utf8)
      return
   }
   for byte in text.utf8 {
      switch byte {
      case UInt8(ascii: "&"): output.append(contentsOf: "&amp;".utf8)
      case UInt8(ascii: "<"): output.append(contentsOf: "&lt;".utf8)
      case UInt8(ascii: ">"): output.append(contentsOf: "&gt;".utf8)
      case UInt8(ascii: "\""): output.append(contentsOf: "&quot;".utf8)
      case UInt8(ascii: "'"): output.append(contentsOf: "&#39;".utf8)
      default: output.append(byte)
      }
   }
}

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
      /// Writes an expression's value.
      case value(ExpressionRef)
      /// Continues if the expression is truthy, otherwise jumps to `otherwise`.
      case branch(ExpressionRef, otherwise: Int32)
      case jump(Int32)
      /// Starts looping over the expression's elements, or jumps to `exit`
      /// when there are none.
      case loop(ExpressionRef, slot: Int32, exit: Int32)
      /// Moves to the loop's next element and jumps back to `body`, or falls
      /// through when done.
      case next(slot: Int32, body: Int32)
      case log(ExpressionRef)
   }

   /// Where an instruction's expression lives.
   enum ExpressionRef {
      /// An operation in `code`.
      case native(Int32)
      /// An expression from a custom compiler, in `custom`.
      case custom(Int32)
   }

   private let instructions: UnsafeMutableBufferPointer<Instruction>
   private let text: UnsafeMutableBufferPointer<UInt8>
   private let custom: UnsafeMutableBufferPointer<any CompiledExpression>
   private let code: ExpressionCode
   private let localCount: Int
   private let log: @Sendable (String) -> Void

   init(_ template: ParsedTemplate, options: TemplateOptions) {
      var builder = Builder(options: options)
      builder.add(template.nodes)
      self.instructions = .copying(builder.instructions)
      self.text = .copying(builder.text)
      self.custom = .copying(builder.custom)
      self.code = ExpressionCode(builder.code)
      self.localCount = template.localCount
      self.log = options.log
   }

   deinit {
      instructions.release()
      text.release()
      custom.release()
   }

   // MARK: Running

   /// A loop in progress.
   private struct Loop {
      let items: [TemplateValue]
      var index: Int
   }

   func run(_ context: TemplateValue, features: RenderFeatures) -> String {
      let interpreter = code.interpreter
      var scope = ExpressionScope(root: context, features: features, localCount: localCount)
      var loops: [Loop] = []
      var output: [UInt8] = []
      output.reserveCapacity(text.count * 3 / 2)

      func evaluate(_ expression: ExpressionRef) -> TemplateValue {
         switch expression {
         case .native(let operation): return interpreter.evaluate(operation, in: scope)
         case .custom(let index): return custom[Int(index)].evaluate(in: scope)
         }
      }

      var pc = 0
      while pc < instructions.count {
         switch instructions[pc] {
         case .text(let span):
            output.append(contentsOf: UnsafeBufferPointer(rebasing: text[span.range]))
            pc += 1

         case .value(let expression):
            let value = evaluate(expression)
            if value != .null {
               output.append(contentsOf: value.renderedString.utf8)
            }
            pc += 1

         case .branch(let condition, let otherwise):
            pc = evaluate(condition).isTruthy ? pc + 1 : Int(otherwise)

         case .jump(let target):
            pc = Int(target)

         case .loop(let sequence, let slot, let exit):
            guard case .array(let items) = evaluate(sequence), !items.isEmpty else {
               pc = Int(exit)
               break
            }
            scope.locals[Int(slot)] = items[0]
            scope.locals[Int(slot) + 1] = .int(0)
            loops.append(Loop(items: items, index: 0))
            pc += 1

         case .next(let slot, let body):
            let current = loops.count - 1
            loops[current].index += 1
            let index = loops[current].index
            if index < loops[current].items.count {
               scope.locals[Int(slot)] = loops[current].items[index]
               scope.locals[Int(slot) + 1] = .int(index)
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
         }
      }

      return String(decoding: output, as: UTF8.self)
   }

   // MARK: Building

   /// Compiles template nodes into instructions.
   private struct Builder {
      let options: TemplateOptions
      var instructions: [Instruction] = []
      var text: [UInt8] = []
      var custom: [any CompiledExpression] = []
      var code = ExpressionCode.Builder()

      init(options: TemplateOptions) {
         self.options = options
      }

      /// The index the next instruction will get.
      private var next: Int32 { Int32(instructions.count) }

      mutating func add(_ nodes: [Node]) {
         for node in nodes {
            add(node)
         }
      }

      private mutating func add(_ node: Node) {
         switch node {
         case .text(let string):
            instructions.append(.text(Span(start: text.count, count: string.utf8.count)))
            text.append(contentsOf: string.utf8)

         case .value(let expression):
            instructions.append(.value(add(expression)))

         case .conditional(let branches, let otherwise):
            // Each branch tests its condition and skips to the next branch when
            // false; a branch that runs jumps past the rest when done.
            // The last branch has nothing to skip when there's no else.
            var exits: [Int] = []
            for (number, branch) in branches.enumerated() {
               let condition = add(branch.condition)
               let test = instructions.count
               instructions.append(.branch(condition, otherwise: -1))
               add(branch.body)
               if otherwise != nil || number < branches.count - 1 {
                  exits.append(instructions.count)
                  instructions.append(.jump(-1))
               }
               instructions[test] = .branch(condition, otherwise: next)
            }
            if let otherwise {
               add(otherwise)
            }
            for exit in exits {
               instructions[exit] = .jump(next)
            }

         case .loop(let slot, let sequence, let body):
            let expression = add(sequence)
            let start = instructions.count
            instructions.append(.loop(expression, slot: Int32(slot), exit: -1))
            add(body)
            instructions.append(.next(slot: Int32(slot), body: Int32(start + 1)))
            instructions[start] = .loop(expression, slot: Int32(slot), exit: next)

         case .log(let expression):
            instructions.append(.log(add(expression)))
         }
      }

      private mutating func add(_ expression: TagExpression) -> ExpressionRef {
         switch expression {
         case .native(let syntax):
            return .native(code.add(syntax))
         case .custom(let compiled):
            custom.append(compiled)
            return .custom(Int32(custom.count - 1))
         }
      }
   }
}

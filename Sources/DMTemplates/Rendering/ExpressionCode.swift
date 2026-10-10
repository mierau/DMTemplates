// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

/// Compiled expressions, stored as flat buffers of plain values.
///
/// A syntax tree of `indirect` enums would work, but every node visit retains
/// and releases a heap box. When many threads render the same template, they
/// all hit the same boxes, and contention on those reference counts made
/// rendering on four cores slower than on one. Operations here refer to each
/// other by index instead, so evaluating them never touches a reference count
/// the template owns.
///
/// The buffers are written once, in `init`, and only read afterward, which is
/// what makes sharing an `ExpressionCode` across threads safe.
final class ExpressionCode: @unchecked Sendable {
   /// One operation. Operands are indexes into `operations`.
   enum Operation {
      case literal(value: Int32)
      case root
      case local(slot: Int32)
      /// An array literal; elements are operations listed in `operands`.
      case list(Span)
      case path(base: Int32, steps: Span)
      case negate(Int32)
      case not(Int32)
      case and(Int32, Int32)
      case or(Int32, Int32)
      case arithmetic(ArithmeticOperator, Int32, Int32)
      case comparison(ComparisonOperator, StringOptions, Int32, Int32)
      /// MATCHES against a pattern compiled ahead of time, from `regexes`.
      case match(regex: Int32, StringOptions, Int32)
      /// The receiver followed by the arguments, listed in `operands`.
      case function(Int32, Span)
   }

   enum Step {
      case key(string: Int32)
      case index(Int32)
      case first, last, size
      case aggregate(Aggregate)
   }

   let operations: UnsafeMutableBufferPointer<Operation>
   let steps: UnsafeMutableBufferPointer<Step>
   let operands: UnsafeMutableBufferPointer<Int32>
   let strings: UnsafeMutableBufferPointer<String>
   let values: UnsafeMutableBufferPointer<TemplateValue>
   let functions: UnsafeMutableBufferPointer<Functions.Function>
   let regexes: UnsafeMutableBufferPointer<NSRegularExpression>

   init(_ builder: Builder) {
      operations = .copying(builder.operations)
      steps = .copying(builder.steps)
      operands = .copying(builder.operands)
      strings = .copying(builder.strings)
      values = .copying(builder.values)
      functions = .copying(builder.functions)
      regexes = .copying(builder.regexes)
   }

   deinit {
      operations.release()
      steps.release()
      operands.release()
      strings.release()
      values.release()
      functions.release()
      regexes.release()
   }

   /// Evaluates this code. Valid only while this object is alive.
   var interpreter: Interpreter {
      Interpreter(operations: UnsafeBufferPointer(operations), steps: UnsafeBufferPointer(steps), operands: UnsafeBufferPointer(operands), strings: UnsafeBufferPointer(strings), values: UnsafeBufferPointer(values), functions: UnsafeBufferPointer(functions), regexes: UnsafeBufferPointer(regexes))
   }
}

// MARK: - Building

extension ExpressionCode {
   /// Collects compiled expressions before they're frozen into an `ExpressionCode`.
   struct Builder {
      private(set) var operations: [Operation] = []
      private(set) var steps: [Step] = []
      private(set) var operands: [Int32] = []
      private(set) var strings: [String] = []
      private(set) var values: [TemplateValue] = []
      private(set) var functions: [Functions.Function] = []
      private(set) var regexes: [NSRegularExpression] = []

      /// Compiles `expr` and returns the index of the operation that evaluates it.
      mutating func add(_ expr: Expr) -> Int32 {
         switch expr {
         case .literal(let value):
            return append(.literal(value: Self.append(value, to: &values)))
         case .root:
            return append(.root)
         case .local(let slot):
            return append(.local(slot: Int32(slot)))
         case .list(let elements):
            return append(.list(addOperands(elements)))
         case .path(let base, let pathSteps):
            let baseOperation = add(base)
            // Compile index expressions first so the path's steps stay contiguous.
            let compiled = pathSteps.map { add($0) }
            let span = Span(start: steps.count, count: compiled.count)
            steps.append(contentsOf: compiled)
            return append(.path(base: baseOperation, steps: span))
         case .negate(let operand):
            return append(.negate(add(operand)))
         case .not(let operand):
            return append(.not(add(operand)))
         case .and(let lhs, let rhs):
            let l = add(lhs)
            return append(.and(l, add(rhs)))
         case .or(let lhs, let rhs):
            let l = add(lhs)
            return append(.or(l, add(rhs)))
         case .arithmetic(let op, let lhs, let rhs):
            let l = add(lhs)
            return append(.arithmetic(op, l, add(rhs)))
         case .comparison(let op, let options, let lhs, let rhs):
            let l = add(lhs)
            // Compile a literal MATCHES pattern once. NSRegularExpression is
            // safe to share between threads, so it serves every render.
            if op == .matches, case .literal(.string(let pattern)) = rhs,
               let regex = wholeStringRegex(pattern, options) {
               return append(.match(regex: Self.append(regex, to: &regexes), options, l))
            }
            return append(.comparison(op, options, l, add(rhs)))
         case .function(let function, let receiver, let arguments):
            let span = addOperands([receiver] + arguments)
            return append(.function(Self.append(function, to: &functions), span))
         }
      }

      private mutating func add(_ step: PathStep) -> Step {
         switch step {
         case .key(let key): return .key(string: Self.append(key, to: &strings))
         case .index(let index): return .index(add(index))
         case .first: return .first
         case .last: return .last
         case .size: return .size
         case .aggregate(let op): return .aggregate(op)
         }
      }

      private mutating func addOperands(_ exprs: [Expr]) -> Span {
         let compiled = exprs.map { add($0) }
         let span = Span(start: operands.count, count: compiled.count)
         operands.append(contentsOf: compiled)
         return span
      }

      private mutating func append(_ operation: Operation) -> Int32 {
         Self.append(operation, to: &operations)
      }

      // Static on purpose: calling an instance method while passing one of
      // self's arrays inout makes Swift copy self, so the array is no longer
      // uniquely referenced and every append copies it.
      private static func append<T>(_ element: T, to array: inout [T]) -> Int32 {
         array.append(element)
         return Int32(array.count - 1)
      }
   }
}

// MARK: - Evaluating

/// Reads an `ExpressionCode`'s buffers. Holds no references, so copying it
/// around is free.
struct Interpreter {
   let operations: UnsafeBufferPointer<ExpressionCode.Operation>
   let steps: UnsafeBufferPointer<ExpressionCode.Step>
   let operands: UnsafeBufferPointer<Int32>
   let strings: UnsafeBufferPointer<String>
   let values: UnsafeBufferPointer<TemplateValue>
   let functions: UnsafeBufferPointer<Functions.Function>
   let regexes: UnsafeBufferPointer<NSRegularExpression>

   func evaluate(_ index: Int32, in scope: ExpressionScope) -> TemplateValue {
      switch operations[Int(index)] {
      case .literal(let value):
         return values[Int(value)]

      case .root:
         return scope.root

      case .local(let slot):
         return scope.locals[Int(slot)]

      case .list(let elements):
         return .array(elements.range.map { evaluate(operands[$0], in: scope) })

      case .path(let base, let pathSteps):
         return walk(evaluate(base, in: scope), pathSteps.range, in: scope)

      case .negate(let operand):
         return evaluate(operand, in: scope).negated

      case .not(let operand):
         return .bool(!evaluate(operand, in: scope).isTruthy)

      case .and(let lhs, let rhs):
         return .bool(evaluate(lhs, in: scope).isTruthy && evaluate(rhs, in: scope).isTruthy)

      case .or(let lhs, let rhs):
         return .bool(evaluate(lhs, in: scope).isTruthy || evaluate(rhs, in: scope).isTruthy)

      case .arithmetic(let op, let lhs, let rhs):
         return op.apply(evaluate(lhs, in: scope), evaluate(rhs, in: scope))

      case .comparison(let op, let options, let lhs, let rhs):
         return .bool(op.apply(evaluate(lhs, in: scope), evaluate(rhs, in: scope), options: options))

      case .match(let regex, let options, let lhs):
         return .bool(regexMatch(regexes[Int(regex)], evaluate(lhs, in: scope), options))

      case .function(let function, let span):
         let values = span.range.map { evaluate(operands[$0], in: scope) }
         return functions[Int(function)](values[0], Array(values.dropFirst()))
      }
   }

   /// Applies key path steps to `value`, left to right.
   private func walk(_ value: TemplateValue, _ range: Range<Int>, in scope: ExpressionScope) -> TemplateValue {
      var value = value
      for index in range {
         switch steps[index] {
         case .key(let string):
            value = value.member(strings[Int(string)])
         case .index(let operation):
            value = value.element(at: evaluate(operation, in: scope))
         case .first:
            value = value.firstElement
         case .last:
            value = value.lastElement
         case .size, .aggregate(.count):
            value = value.elementCount
         case .aggregate(let op):
            // Like KVC, `people.@avg.age` applies the rest of the path to each
            // element, then aggregates the results.
            guard case .array(let items) = value else {
               return .null
            }
            let rest = (index + 1)..<range.upperBound
            return op.apply(to: items.map { walk($0, rest, in: scope) })
         }
      }
      return value
   }
}

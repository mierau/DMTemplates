// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

// What the expression language's operations mean for template values. Values
// convert the way KVC and NSPredicate convert them: numeric strings and
// booleans act as numbers, and anything that doesn't apply yields nil (`.null`)
// rather than an error, so a missing key renders as nothing.

// MARK: - Key paths

extension TemplateValue {
   /// The value for `key`. Arrays collect the key from every element, like KVC.
   func member(_ key: String) -> TemplateValue {
      switch self {
      case .dictionary(let items):
         return items[key] ?? .null
      case .array(let items):
         return .array(items.map { $0.member(key) })
      default:
         return .null
      }
   }

   /// `value[index]`: an array element by position, or a dictionary value by key.
   func element(at index: TemplateValue) -> TemplateValue {
      switch (self, index) {
      case (.array(let items), _):
         guard case .int(let i)? = index.number, items.indices.contains(i) else {
            return .null
         }
         return items[i]
      case (.dictionary, _), (.string, _):
         return member(index.renderedString)
      default:
         return .null
      }
   }

   var firstElement: TemplateValue {
      if case .array(let items) = self, let first = items.first { first } else { .null }
   }

   var lastElement: TemplateValue {
      if case .array(let items) = self, let last = items.last { last } else { .null }
   }

   /// `@count`: the number of elements, entries or characters.
   var elementCount: TemplateValue {
      switch self {
      case .array(let items): return .int(items.count)
      case .dictionary(let items): return .int(items.count)
      case .string(let text): return .int(text.count)
      default: return .null
      }
   }
}

extension Aggregate {
   /// Combines the values a collection operator collected. Values that aren't
   /// numbers are skipped by `@sum` and `@avg`.
   func apply(to values: [TemplateValue]) -> TemplateValue {
      switch self {
      case .count:
         return .int(values.count)

      case .sum, .avg:
         let numbers = values.compactMap(\.number)
         let total = numbers.reduce(0.0) { $0 + $1.double }
         if self == .avg {
            return .double(numbers.isEmpty ? 0 : total / Double(numbers.count))
         }
         // Keep whole-number sums exact unless they overflow.
         var intTotal = 0
         for number in numbers {
            guard case .int(let value) = number else { return .double(total) }
            let (sum, overflow) = intTotal.addingReportingOverflow(value)
            if overflow { return .double(total) }
            intTotal = sum
         }
         return .int(intTotal)

      case .min, .max:
         var best: TemplateValue?
         for value in values where value != .null {
            guard let current = best else {
               best = value
               continue
            }
            if let order = compareValues(value, current, []), self == .min ? order < 0 : order > 0 {
               best = value
            }
         }
         return best ?? .null
      }
   }
}

// MARK: - Arithmetic

extension TemplateValue {
   var negated: TemplateValue {
      switch number {
      case .int(let v)?: return v == .min ? .double(-Double(v)) : .int(-v)
      case .double(let v)?: return .double(-v)
      case nil: return .null
      }
   }
}

extension ArithmeticOperator {
   /// Whole numbers stay whole unless they overflow; `/` always gives a real
   /// number, like NSExpression. Dividing by zero gives nil.
   func apply(_ lhs: TemplateValue, _ rhs: TemplateValue) -> TemplateValue {
      guard let a = lhs.number, let b = rhs.number else {
         return .null
      }

      if case .int(let x) = a, case .int(let y) = b, let result = wholeResult(x, y) {
         return .int(result)
      }

      let x = a.double
      let y = b.double
      switch self {
      case .add: return .double(x + y)
      case .subtract: return .double(x - y)
      case .multiply: return .double(x * y)
      case .divide: return y == 0 ? .null : .double(x / y)
      case .modulo: return y == 0 ? .null : .double(x.truncatingRemainder(dividingBy: y))
      }
   }

   /// The result for two whole numbers, or nil when it isn't a whole number
   /// that fits.
   private func wholeResult(_ x: Int, _ y: Int) -> Int? {
      let result: (partialValue: Int, overflow: Bool)
      switch self {
      case .add: result = x.addingReportingOverflow(y)
      case .subtract: result = x.subtractingReportingOverflow(y)
      case .multiply: result = x.multipliedReportingOverflow(by: y)
      case .modulo: result = y == 0 ? (0, true) : x.remainderReportingOverflow(dividingBy: y)
      case .divide: return nil
      }
      return result.overflow ? nil : result.partialValue
   }
}

// MARK: - Comparison

extension ComparisonOperator {
   func apply(_ lhs: TemplateValue, _ rhs: TemplateValue, options: StringOptions) -> Bool {
      switch self {
      case .equal:
         return valuesEqual(lhs, rhs, options)
      case .notEqual:
         return !valuesEqual(lhs, rhs, options)
      case .less:
         return compareValues(lhs, rhs, options).map { $0 < 0 } ?? false
      case .lessOrEqual:
         return compareValues(lhs, rhs, options).map { $0 <= 0 } ?? false
      case .greater:
         return compareValues(lhs, rhs, options).map { $0 > 0 } ?? false
      case .greaterOrEqual:
         return compareValues(lhs, rhs, options).map { $0 >= 0 } ?? false

      case .between:
         guard case .array(let bounds) = rhs, bounds.count == 2,
               let low = compareValues(lhs, bounds[0], options),
               let high = compareValues(lhs, bounds[1], options) else {
            return false
         }
         return low >= 0 && high <= 0

      case .in:
         return collection(rhs, contains: lhs, options)
      case .contains:
         return collection(lhs, contains: rhs, options)

      case .beginsWith, .endsWith:
         guard case .string(let text) = lhs, case .string(let affix) = rhs else {
            return false
         }
         let x = fold(text, options)
         let y = fold(affix, options)
         return self == .beginsWith ? x.hasPrefix(y) : x.hasSuffix(y)

      case .like:
         guard case .string(let text) = lhs, case .string(let pattern) = rhs else {
            return false
         }
         return wildcardMatch(fold(text, options), fold(pattern, options))

      case .matches:
         // Templates compile a literal pattern ahead of time; this handles one
         // computed while rendering.
         guard case .string(let pattern) = rhs, let regex = wholeStringRegex(pattern, options) else {
            return false
         }
         return regexMatch(regex, lhs, options)
      }
   }
}

/// Orders two values: -1, 0 or 1. Two strings compare as strings and two dates
/// as dates; otherwise both must read as numbers. Nil when the values can't be
/// ordered.
private func compareValues(_ lhs: TemplateValue, _ rhs: TemplateValue, _ options: StringOptions) -> Int? {
   switch (lhs, rhs) {
   case (.string(let a), .string(let b)):
      let x = fold(a, options)
      let y = fold(b, options)
      return x == y ? 0 : (x < y ? -1 : 1)
   case (.date(let a), .date(let b)):
      return a == b ? 0 : (a < b ? -1 : 1)
   default:
      break
   }

   switch (lhs.number, rhs.number) {
   case (.int(let a)?, .int(let b)?):
      return a == b ? 0 : (a < b ? -1 : 1)
   case (let a?, let b?):
      let x = a.double
      let y = b.double
      if x.isNaN || y.isNaN { return nil }
      return x == y ? 0 : (x < y ? -1 : 1)
   default:
      return nil
   }
}

private func valuesEqual(_ lhs: TemplateValue, _ rhs: TemplateValue, _ options: StringOptions) -> Bool {
   switch (lhs, rhs) {
   case (.null, .null):
      return true
   case (.null, _), (_, .null):
      return false
   case (.array(let a), .array(let b)):
      return a.count == b.count && zip(a, b).allSatisfy { valuesEqual($0, $1, options) }
   case (.dictionary, .dictionary):
      return lhs == rhs
   default:
      return compareValues(lhs, rhs, options) == 0
   }
}

/// Whether an array holds `element`, a dictionary has it as a key, or a string
/// contains it.
private func collection(_ collection: TemplateValue, contains element: TemplateValue, _ options: StringOptions) -> Bool {
   switch (collection, element) {
   case (.array(let items), _):
      return items.contains { valuesEqual($0, element, options) }
   case (.dictionary(let items), .string(let key)):
      return items[key] != nil
   case (.string(let text), .string(let part)):
      return fold(text, options).contains(fold(part, options))
   default:
      return false
   }
}

/// NSPredicate's LIKE: `*` matches any run of characters, `?` matches exactly
/// one, and a backslash makes the character after it literal. The pattern has
/// to cover the whole string.
private func wildcardMatch(_ text: String, _ pattern: String) -> Bool {
   enum Token: Equatable {
      case any, one, character(Character)
   }

   var tokens: [Token] = []
   var escaped = false
   for c in pattern {
      if escaped { tokens.append(.character(c)); escaped = false }
      else if c == "\\" { escaped = true }
      else if c == "*" { tokens.append(.any) }
      else if c == "?" { tokens.append(.one) }
      else { tokens.append(.character(c)) }
   }
   if escaped { tokens.append(.character("\\")) }

   // Match greedily, and on a mismatch let the last `*` take one more
   // character and try again from there.
   let text = Array(text)
   var t = 0
   var p = 0
   var lastAny: (token: Int, text: Int)?
   while t < text.count {
      if p < tokens.count, tokens[p] == .one || tokens[p] == .character(text[t]) {
         t += 1
         p += 1
      }
      else if p < tokens.count, tokens[p] == .any {
         lastAny = (p, t)
         p += 1
      }
      else if let any = lastAny {
         lastAny = (any.token, any.text + 1)
         p = any.token + 1
         t = any.text + 1
      }
      else {
         return false
      }
   }
   while p < tokens.count, tokens[p] == .any {
      p += 1
   }
   return p == tokens.count
}

/// A regular expression that, like NSPredicate's MATCHES, has to match the
/// whole string. Nil when `pattern` isn't a valid regular expression.
func wholeStringRegex(_ pattern: String, _ options: StringOptions) -> NSRegularExpression? {
   var regexOptions: NSRegularExpression.Options = []
   if options.contains(.caseInsensitive) { regexOptions.insert(.caseInsensitive) }
   let pattern = fold(pattern, options.subtracting(.caseInsensitive))
   // Check the pattern on its own first: wrapping it could balance a stray
   // parenthesis and hide the mistake.
   guard (try? NSRegularExpression(pattern: pattern, options: regexOptions)) != nil else {
      return nil
   }
   return try? NSRegularExpression(pattern: "\\A(?:" + pattern + ")\\z", options: regexOptions)
}

/// Whether `value` is a string `regex` matches. The regex handles `[c]`;
/// `[d]` folds the text the same way `wholeStringRegex` folded the pattern.
func regexMatch(_ regex: NSRegularExpression, _ value: TemplateValue, _ options: StringOptions) -> Bool {
   guard case .string(let text) = value else {
      return false
   }
   let folded = fold(text, options.subtracting(.caseInsensitive))
   let range = NSRange(folded.startIndex..<folded.endIndex, in: folded)
   return regex.firstMatch(in: folded, options: [], range: range) != nil
}

/// Applies `[c]` and `[d]` by folding case and diacritics away.
private func fold(_ text: String, _ options: StringOptions) -> String {
   if options.isEmpty {
      return text
   }
   var compareOptions: String.CompareOptions = []
   if options.contains(.caseInsensitive) { compareOptions.insert(.caseInsensitive) }
   if options.contains(.diacriticInsensitive) { compareOptions.insert(.diacriticInsensitive) }
   return text.folding(options: compareOptions, locale: nil)
}

// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

/// Template functions that show dates and numbers for people, in the
/// template's locale, time zone and currency. Made once, when the template is
/// parsed, and shared by every render.
extension Functions {
   static func formatting(_ options: TemplateOptions) -> Functions {
      var functions = Functions()
      let styles: [(String, Format)] = [
         ("date", .date), ("time", .time), ("dateTime", .dateTime), ("iso8601", .iso8601), ("relative", .relative),
         ("number", .number), ("percent", .percent), ("currency", .currency),
      ]
      for (name, format) in styles {
         let formatter = ValueFormatter(format, options: options)
         functions[name] = { receiver, _ in formatter.apply(to: receiver) }
      }

      let patterns = PatternFormatters(options: options)
      functions["format"] = { receiver, arguments in
         guard let first = arguments.first, let pattern = string(first), !pattern.isEmpty else {
            return receiver
         }
         return patterns.formatter(for: pattern).apply(to: receiver)
      }
      return functions
   }
}

/// Formatters for `format(pattern)`, made the first time each pattern is used.
/// Foundation's formatters are slow to create.
private final class PatternFormatters: @unchecked Sendable {
   private let options: TemplateOptions
   private var formatters: [String: ValueFormatter] = [:]
   private let lock = NSLock()

   init(options: TemplateOptions) {
      self.options = options
   }

   func formatter(for pattern: String) -> ValueFormatter {
      lock.lock()
      defer { lock.unlock() }
      if let formatter = formatters[pattern] {
         return formatter
      }
      let formatter = ValueFormatter(Format.isNumberPattern(pattern) ? .numberPattern(pattern) : .datePattern(pattern), options: options)
      formatters[pattern] = formatter
      return formatter
   }
}

/// A way to show a date or number.
enum Format: Hashable {
   case date, time, dateTime, iso8601, relative
   case number, percent, currency
   case datePattern(String)
   case numberPattern(String)

   /// Number patterns, like "#,##0.00", use 0 or # and no letters outside
   /// quoted text except E, for an exponent. Anything else is a date pattern,
   /// like "MMM d, yyyy".
   static func isNumberPattern(_ pattern: String) -> Bool {
      var quoted = false
      var hasDigits = false
      for character in pattern {
         if character == "'" {
            quoted.toggle()
         }
         else if quoted {
            continue
         }
         else if character == "0" || character == "#" {
            hasDigits = true
         }
         else if character.isLetter && character != "E" {
            return false
         }
      }
      return hasDigits
   }
}

/// Shows values the way one `Format` asks, in a template's locale and time
/// zone.
struct ValueFormatter: Sendable {
   private let body: @Sendable (TemplateValue) -> String?

   init(_ format: Format, options: TemplateOptions) {
      let locale = options.locale
      let timeZone = options.timeZone

      switch format {
      case .date:
         body = Self.dates(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone), in: timeZone)
      case .time:
         body = Self.dates(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone), in: timeZone)
      case .dateTime:
         body = Self.dates(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone), in: timeZone)
      case .iso8601:
         body = Self.dates(Date.ISO8601FormatStyle(), in: timeZone)
      case .relative:
         body = Self.dates(Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide, locale: locale), in: timeZone)

      case .number:
         body = Self.numbers(FloatingPointFormatStyle<Double>(locale: locale))
      case .percent:
         body = Self.numbers(FloatingPointFormatStyle<Double>.Percent(locale: locale))
      case .currency:
         let code = options.currencyCode ?? locale.currency?.identifier ?? "USD"
         body = Self.numbers(FloatingPointFormatStyle<Double>.Currency(code: code, locale: locale))

      case .datePattern(let pattern):
         let formatter = DateFormatter()
         formatter.locale = locale
         formatter.timeZone = timeZone
         formatter.dateFormat = pattern
         let shared = Locked(formatter)
         body = { value in
            value.date(in: timeZone).map { date in shared.withLock { $0.string(from: date) } }
         }
      case .numberPattern(let pattern):
         let formatter = NumberFormatter()
         formatter.locale = locale
         formatter.positiveFormat = pattern
         let shared = Locked(formatter)
         body = { value in
            value.doubleValue.flatMap { number in shared.withLock { $0.string(from: NSNumber(value: number)) } }
         }
      }
   }

   /// The formatted value, or nil when it isn't the kind of value the format
   /// shows, such as a name formatted as a date.
   func format(_ value: TemplateValue) -> String? {
      body(value)
   }

   /// The formatted value as a function returns it. Lists format each
   /// element, and a value the format doesn't fit comes back unchanged.
   func apply(to value: TemplateValue) -> TemplateValue {
      if case .array(let items) = value {
         return .array(items.map { apply(to: $0) })
      }
      return format(value).map { .string($0) } ?? value
   }

   private static func dates<Style: FormatStyle & Sendable>(_ style: Style, in timeZone: TimeZone) -> @Sendable (TemplateValue) -> String? where Style.FormatInput == Date, Style.FormatOutput == String {
      { value in value.date(in: timeZone).map { style.format($0) } }
   }

   private static func numbers<Style: FormatStyle & Sendable>(_ style: Style) -> @Sendable (TemplateValue) -> String? where Style.FormatInput == Double, Style.FormatOutput == String {
      { value in value.doubleValue.map { style.format($0) } }
   }
}

/// A Foundation formatter shared under a lock. DateFormatter and
/// NumberFormatter aren't documented as safe to use from several threads at
/// once on every platform this runs on.
private final class Locked<Value>: @unchecked Sendable {
   private let value: Value
   private let lock = NSLock()

   init(_ value: Value) {
      self.value = value
   }

   func withLock<Result>(_ body: (Value) -> Result) -> Result {
      lock.lock()
      defer { lock.unlock() }
      return body(value)
   }
}

// MARK: - Coercion

extension TemplateValue {
   /// The value as a date: a date, an ISO 8601 string such as
   /// "2025-10-09T08:53:20Z" or "2025-10-09", or a number of seconds since 1970.
   /// A day without a time, like "2025-10-09", starts at midnight in
   /// `timeZone`, so it shows as that same day.
   func date(in timeZone: TimeZone) -> Date? {
      switch self {
      case .date(let date):
         return date
      case .string(let text):
         return (try? Date.ISO8601FormatStyle().parse(text))
            ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().parse(text))
      case .int, .double:
         return number.map { Date(timeIntervalSince1970: $0.double) }
      default:
         return nil
      }
   }

   /// The value as a number, reading numeric strings the way arithmetic does.
   var doubleValue: Double? {
      number?.double
   }
}

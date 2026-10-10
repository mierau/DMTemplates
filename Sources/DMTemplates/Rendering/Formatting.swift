// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

/// Template functions that show dates and numbers for people, in the
/// template's locale, time zone and currency. Foundation's formatters are slow
/// to create and most templates use few or none, so each is made the first time
/// a render uses it, then shared by every template with the same settings.
extension Functions {
   /// The formatting functions for `options`' locale, time zone and currency.
   static func formatting(for options: TemplateOptions) -> Functions {
      let key = FormattingSettings(locale: options.locale, timeZone: options.timeZone, currencyCode: options.currencyCode)
      return formattingCache.withLock { cache in
         if let functions = cache[key] {
            return functions
         }
         // Many distinct settings, such as a time zone per user, start over
         // rather than grow without end.
         if cache.count >= 64 {
            cache.removeAll()
         }
         var settings = TemplateOptions()
         settings.locale = key.locale
         settings.timeZone = key.timeZone
         settings.currencyCode = key.currencyCode
         let functions = formatting(settings)
         cache[key] = functions
         return functions
      }
   }

   private static let formattingCache = Locked<[FormattingSettings: Functions]>([:])

   private static func formatting(_ options: TemplateOptions) -> Functions {
      var functions = Functions()
      let styles: [(String, Format)] = [
         ("date", .date), ("time", .time), ("dateTime", .dateTime), ("iso8601", .iso8601), ("relative", .relative),
         ("number", .number), ("percent", .percent), ("currency", .currency),
      ]
      for (name, format) in styles {
         let formatter = Locked<ValueFormatter?>(nil)
         functions[name] = { receiver, _ in
            let made = formatter.withLock { cached in
               if let cached { return cached }
               let made = ValueFormatter(format, options: options)
               cached = made
               return made
            }
            return made.apply(to: receiver)
         }
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

private struct FormattingSettings: Hashable {
   let locale: Locale
   let timeZone: TimeZone
   let currencyCode: String?
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
         body = Self.numbers(FloatingPointFormatStyle<Double>(locale: locale), Decimal.FormatStyle(locale: locale))
      case .percent:
         body = Self.numbers(FloatingPointFormatStyle<Double>.Percent(locale: locale), Decimal.FormatStyle.Percent(locale: locale))
      case .currency:
         let code = options.currencyCode ?? locale.currency?.identifier ?? "USD"
         body = Self.numbers(FloatingPointFormatStyle<Double>.Currency(code: code, locale: locale), Decimal.FormatStyle.Currency(code: code, locale: locale))

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
            let number: NSNumber? = if case .decimal(let v) = value { NSDecimalNumber(decimal: v) } else { value.doubleValue.map { NSNumber(value: $0) } }
            return number.flatMap { number in shared.withLock { $0.string(from: number) } }
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

   /// Formats decimals with `decimalStyle`, so they stay exact, and other
   /// numbers with `style`.
   private static func numbers<Style: FormatStyle & Sendable, DecimalStyle: FormatStyle & Sendable>(_ style: Style, _ decimalStyle: DecimalStyle) -> @Sendable (TemplateValue) -> String? where Style.FormatInput == Double, Style.FormatOutput == String, DecimalStyle.FormatInput == Decimal, DecimalStyle.FormatOutput == String {
      { value in
         if case .decimal(let v) = value {
            return decimalStyle.format(v)
         }
         return value.doubleValue.map { style.format($0) }
      }
   }
}

/// A Foundation formatter shared under a lock. DateFormatter and
/// NumberFormatter aren't documented as safe to use from several threads at
/// once on every platform this runs on.
private final class Locked<Value>: @unchecked Sendable {
   private var value: Value
   private let lock = NSLock()

   init(_ value: Value) {
      self.value = value
   }

   func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
      lock.lock()
      defer { lock.unlock() }
      return body(&value)
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
         // A failed parse is slow, so only try the forms the text could be in.
         guard text.utf8.first?.isDigit == true else {
            return nil
         }
         guard text.contains("T") else {
            return try? Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().parse(text)
         }
         if text.contains(".") {
            return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
               ?? (try? Date.ISO8601FormatStyle().parse(text))
         }
         return (try? Date.ISO8601FormatStyle().parse(text))
            ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
      case .int, .double, .decimal:
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

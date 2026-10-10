# Functions and Formatting

Transform and format values with functions.

## Calling Functions

Pass a value through functions with a pipe, or call them the way you'd call a method in Swift. These all mean the same thing:

```
{% person.firstName | prefix(1) | uppercase %}
{% person.firstName.prefix(1).uppercase() %}
{% uppercase(prefix(person.firstName, 1)) %}
```

A pipe binds as tightly as `.`, so it works inside conditions, and parentheses pipe a whole expression, as in `{% (item.price * item.quantity) | currency %}`.

## Standard Functions

- Text: `uppercase`, `lowercase`, `capitalize`, `trim`, `prefix(n)`, `suffix(n)`, `dropFirst(n)`, `dropLast(n)`, `replace(old, new)` and `truncate(n, ending)`.
- Counts: `pluralize(singular, plural)`, as in `3 | pluralize("comment")` for `3 comments`.
- Output: `raw`, `escape`, `urlEncode` and `bytes`.
- Lists: `first`, `last`, `count`, `reverse`, `unique`, `sort(key)`, `where(key, value)` and `join(separator)`.
- Numbers: `round(places)`, `floor`, `ceil` and `abs`.
- `path(components...)` and `default(fallback)`.

Text functions applied to a list apply to each element.

## Formatting

Formatting functions show dates and numbers for people, following ``TemplateOptions/locale``, ``TemplateOptions/timeZone`` and ``TemplateOptions/currencyCode``:

- `date`, `time` and `dateTime`, as in `Oct 9, 2025` and `1:53 AM`.
- `relative`, as in `2 days ago`.
- `iso8601`, as in `2025-10-09T08:53:20Z`.
- `number`, `percent` and `currency`, as in `1,234.5`, `25%` and `$1,234.50`.
- `format(pattern)`, with a date pattern like `"MMM d, yyyy"` or a number pattern like `"#,##0.00"`.

Dates can be `Date` values, ISO 8601 strings, or numbers of seconds since 1970. A value a format doesn't fit passes through unchanged.

## Custom Functions

Register your own in ``TemplateOptions/functions``. ``Functions/text(_:)`` makes one from a transform of text, and a full ``Functions/Function`` gets the value it's called on and its arguments:

```swift
var options = TemplateOptions()
options.functions["shout"] = Functions.text { $0.uppercased() + "!" }
options.functions["initials"] = { receiver, _ in
   .string(receiver.renderedString.split(separator: " ").compactMap(\.first).map(String.init).joined())
}
```

A function you register replaces a standard one with the same name. Calling a function that isn't registered is an error when the template is created.

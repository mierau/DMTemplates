# DMTemplates
[![Test](https://github.com/mierau/DMTemplates/actions/workflows/test.yml/badge.svg)](https://github.com/mierau/DMTemplates/actions/workflows/test.yml)

A small Swift templating engine with enough features for the cases developers commonly face: values, conditions, loops, modifiers and logging.

A template is parsed once into an immutable, `Sendable` value, with every tag's expression compiled up front. Rendering is a pure function of the template and a context, so one template can render on many threads at once. It runs anywhere Swift 6 does, including Linux.

## Installation
Add DMTemplates to your `Package.swift`:

    dependencies: [
       .package(url: "https://github.com/mierau/DMTemplates", from: "2.0.0"),
    ],

Then add `"DMTemplates"` to your target's dependencies. In Xcode, choose File › Add Package Dependencies and enter the same URL.

DMTemplates needs Swift 6 and runs on macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1 and Linux.

## Use
Create a template and render it against a context:

    import DMTemplates

    let template = try Template("Hello, my name is {% firstName %}.")
    let rendered = template.render(["firstName": "Dustin"])

**Rendered**: Hello, my name is Dustin.

A context is a `TemplateValue`, which you can write as a literal, as above. You can also render against Foundation or Swift values, such as a dictionary read from JSON or a property list, with `render(object:)`, or against any `Encodable` value with `render(encoding:)`.

Mistakes in a template, such as an unclosed `if` or a typo in an expression, throw a `TemplateError` with a line and column when the template is created, rather than surfacing while it renders.

To load a template from a file, use `Template(contentsOf:)`. Tags are written between `{%` and `%}` by default; `TemplateOptions.beginDelimiter` and `endDelimiter` change them.

## Expressions
Value tags, conditions and loops all take expressions, written in a syntax modeled on NSPredicate's:

* Key paths: `person.name`, `people[0]`, `person["first name"]`, `people[FIRST]`, `people[LAST]`, `people[SIZE]`. A key path through an array collects the key from every element, so `files.name` is an array of names.
* Collection operators: `@count`, `@sum`, `@avg`, `@min` and `@max`, as in `people.@avg.age`.
* Arithmetic: `+ - * / %`.
* Comparisons: `== = != <> < <= > >=`, `BETWEEN`, `IN`, `CONTAINS`, `BEGINSWITH` and `ENDSWITH`, with `[c]`, `[d]` or `[cd]` to ignore case or diacritics.
* Logic: `AND`, `OR` and `NOT`, or `&&`, `||` and `!`.
* Literals: strings, numbers, `true`/`false`/`YES`/`NO`, `nil`, and arrays written `{1, 2}` or `[1, 2]`.
* Function calls: `name.uppercased()`, `name | prefix(3)`, `path("~", name)`. See [Functions](#functions).

`LIKE`, `MATCHES`, `ANY`, `ALL`, `SOME`, `NONE`, `SUBQUERY`, `CAST` and `TERNARY` are not supported and are reported as errors.

## Conditions
Templates support **if**, **elseif** and **else**, closed by **endif**. `else if` and a bare `end` work too.

    {% if(person.contacts.@count == 0) %}
      Please add some contacts.
    {% elseif(person.contacts.@count < 3) %}
      Add some more contacts.
    {% else %}
      You have enough contacts.
    {% endif %}

A control tag swallows the line break that follows it, so tags on lines of their own don't leave blank lines behind.

## Loops
A **foreach** loop runs over an array, which can come from a key path, an expression or an inline array.

    {% foreach(contact in person.contacts) %}
      Contact name: {% contact.firstName %} {% contact.lastName %}
    {% endforeach %}

    {% foreach(contactName in {"Dustin", "Mary Ann", "Ollie"}) %}
      Contact: {% contactName %}
    {% endforeach %}

    {% foreach(filename in files.name | lowercased) %}
      Lowercase file name: {% filename %}
    {% endforeach %}

Inside a loop, the current index is available as the loop variable's name followed by `Index`:

    {% foreach(contact in person.contacts) %}
      Contact {% contactIndex + 1 %}: {% contact.firstName %}
    {% endforeach %}

## Formatting
Add `as` and a format to a value tag to show a date or number for people:

    Posted {% post.date as date %} at {% post.date as time %}
    Updated {% post.updated as relative %}
    Total: {% order.total as currency %}

The named formats are:

* `date`, `time` and `datetime`, as in `Oct 9, 2025` and `1:53 AM`.
* `relative`, as in `2 days ago`.
* `iso8601`, as in `2025-10-09T08:53:20Z`, which is also how dates render without a format.
* `number`, `percent` and `currency`, as in `1,234.5`, `25%` and `$1,234.50`.

For anything else, give a pattern in quotes: a date pattern like `"MMM d, yyyy"` or a number pattern like `"#,##0.00"`, written the way DateFormatter and NumberFormatter take them.

    {% post.date as "EEEE, MMMM d" %}
    {% item.weight as "0.0" %} kg

Formats follow `TemplateOptions.locale`, `timeZone` and `currencyCode`, which default to the current locale, the current time zone and the locale's currency:

    var options = TemplateOptions()
    options.locale = Locale(identifier: "fr_FR")
    options.currencyCode = "EUR"

Dates can be `Date` values, ISO 8601 strings such as `"2025-10-09T08:53:20Z"` or `"2025-10-09"`, or numbers of seconds since 1970, so dates in JSON work too. They also compare with `<`, `>` and the rest, and work with `@min` and `@max`. A value a format doesn't fit, such as a name formatted `as date`, renders as usual. Modifiers apply after formatting.

## Modifiers
Modifiers process a value before it's rendered. List them by character in square brackets at the start of a value tag; they apply in order.

    {%[e] person.firstName %}
    http://www.website.com/profile?id={%[u] person.id %}
    The file size is: {%[b] file.fileSize %}

The built-in modifiers are:

* `e` escapes XML entities.
* `u` percent-encodes everything except letters, digits and `-._~`.
* `b` formats a byte count for people, as in `1.9 MB`.

You can add your own through `TemplateOptions`:

    var options = TemplateOptions()
    options.modifiers["w"] = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    let template = try Template("First name is {%[we] firstName %}.", options: options)

## Functions
Call a function on a value the way you'd call a method in Swift, or pass the value along with a pipe. These all mean the same thing:

    {% person.firstName.prefix(1).uppercased() %}
    {% person.firstName | prefix(1) | uppercased %}
    {% uppercased(prefix(person.firstName, 1)) %}

A pipe needs no parentheses when there are no arguments, and binds as tightly as `.`, so it works inside conditions:

    {% if(post.title | lowercased BEGINSWITH "draft") %}(unpublished){% endif %}
    {% (item.price * item.quantity) | default(0) as currency %}

The standard functions are named after their Swift counterparts:

* `uppercased`, `lowercased`, `capitalized` and `trimmed`.
* `prefix(n)`, `suffix(n)`, `dropFirst(n)` and `dropLast(n)`, where `n` defaults to 1 for the `drop` functions.
* `replacing(old, new)`.
* `reversed`, for text or a list, and `joined(separator)` to join a list into text.
* `path(components...)`, as in `path("/avatars", person.id, "photo.jpg")`.
* `default(fallback)`, which stands in for nil or empty values, as in `person.nickname | default(person.firstName)`.

Text functions applied to a list apply to each element, so `files.name | lowercased | joined(", ")` lists every name in lowercase.

Register your own in `TemplateOptions.functions`. A function gets the value it's called on and its arguments:

    options.functions["initials"] = { receiver, _ in
       .string(receiver.renderedString.split(separator: " ").compactMap(\.first).map(String.init).joined())
    }

    {% person.name | initials %}

Any name works, even one like `function` or `all`. Calling a function that isn't registered is an error when the template is created. A render can turn calls off by leaving `.functions` out of its features, and they render as nothing:

    template.render(context, features: [.log])

## Logging
To help debug a template, a **log** tag writes an expression's value to `TemplateOptions.log`, which prints to standard error by default. Log tags render nothing, and a render can switch them off by leaving `.log` out of its features.

    {% log(person.firstName) %}

## Custom expressions
Expressions are compiled through the `ExpressionCompiler` protocol, and `TemplateOptions.expressionCompiler` can replace the built-in `NativeExpressionCompiler` with your own.

## Benchmarks
`Benchmarks/run.sh` measures parsing and rendering the templates in `Benchmarks/Fixtures`, including rendering one template from every core at once.

## License
DMTemplates is available under the MIT license. See [LICENSE](LICENSE).

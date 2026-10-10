# DMTemplates
[![Test](https://github.com/mierau/DMTemplates/actions/workflows/test.yml/badge.svg)](https://github.com/mierau/DMTemplates/actions/workflows/test.yml)

A small Swift templating engine with enough features for the cases developers commonly face: values, conditions, loops, functions and logging.

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
* Arithmetic: `+ - * / %`. `+` also joins text, as in `"Hi " + person.name`, whenever either side is text that isn't a number.
* Comparisons: `== = != <> < <= > >=`, `BETWEEN`, `IN`, `CONTAINS`, `BEGINSWITH`, `ENDSWITH`, `LIKE` and `MATCHES`, with `[c]`, `[d]` or `[cd]` to ignore case or diacritics.
* Pattern matching: `LIKE` matches the whole string against a pattern where `*` stands for any run of characters and `?` for exactly one, so `file LIKE[c] "*.png"`. `MATCHES` takes a regular expression that has to match the whole string, as in `code MATCHES "[A-Z]{3}-[0-9]+"`. A pattern written in the template is checked when the template is created.
* Logic: `AND`, `OR` and `NOT`, or `&&`, `||` and `!`.
* Literals: strings, numbers, `true`/`false`/`YES`/`NO`, `nil`, and arrays written `{1, 2}` or `[1, 2]`.
* Function calls: `name.uppercase()`, `name | prefix(3)`, `path("~", name)`. See [Functions](#functions).

`ANY`, `ALL`, `SOME`, `NONE`, `SUBQUERY`, `CAST` and `TERNARY` are not supported and are reported as errors.

## Conditions
Templates support **if**, **elseif** and **else**, closed by **endif**. `else if` and a bare `end` work too.

    {% if(person.contacts.@count == 0) %}
      Please add some contacts.
    {% elseif(person.contacts.@count < 3) %}
      Add some more contacts.
    {% else %}
      You have enough contacts.
    {% endif %}

The parentheses are optional, so `{% if count > 2 %}` and `{% foreach contact in person.contacts %}` work too.

A control tag swallows the line break that follows it, so tags on lines of their own don't leave blank lines behind.

## Loops
A **foreach** loop runs over an array, which can come from a key path, an expression or an inline array.

    {% foreach(contact in person.contacts) %}
      Contact name: {% contact.firstName %} {% contact.lastName %}
    {% endforeach %}

    {% foreach(contactName in {"Dustin", "Mary Ann", "Ollie"}) %}
      Contact: {% contactName %}
    {% endforeach %}

    {% foreach(filename in files.name | lowercase) %}
      Lowercase file name: {% filename %}
    {% endforeach %}

Inside a loop, the current index is available as the loop variable's name followed by `Index`:

    {% foreach(contact in person.contacts) %}
      Contact {% contactIndex + 1 %}: {% contact.firstName %}
    {% endforeach %}

## Functions
Functions transform a value before it's shown. Pass a value through them with a pipe, or call them the way you'd call a method in Swift. These all mean the same thing:

    {% person.firstName | prefix(1) | uppercase %}
    {% person.firstName.prefix(1).uppercase() %}
    {% uppercase(prefix(person.firstName, 1)) %}

Pipes apply left to right and need no parentheses when there are no arguments. A pipe binds as tightly as `.`, so it works inside conditions, and parentheses pipe a whole expression:

    {% person.bio | trim | escape %}
    {% if(post.title | lowercase BEGINSWITH "draft") %}(unpublished){% endif %}
    {% (item.price * item.quantity) | currency %}

The standard functions are:

* Text: `uppercase`, `lowercase`, `capitalize`, `trim`, `prefix(n)`, `suffix(n)`, `dropFirst(n)`, `dropLast(n)` (where `n` defaults to 1), `replace(old, new)` and `truncate(n)`, which shortens text to `n` characters ending in "…" (or `truncate(n, "...")` for another ending).
* Counts: `pluralize(singular, plural)`, as in `post.comments.@count | pluralize("comment")` for `3 comments`; `plural` defaults to the singular plus "s".
* Output: `escape` escapes text for HTML and XML, `urlEncode` percent-encodes everything except letters, digits and `-._~`, and `bytes` shows a byte count for people, as in `1.9 MB`.
* Lists: `first`, `last`, `count`, `reverse`, `unique`, `sort` or `sort(key)`, `where(key, value)` (or `where(key)` for elements whose key is true), and `join(separator)` to join a list into text. They chain, as in `people | where("admin") | sort("name") | first`.
* Numbers: `round` or `round(places)`, `floor`, `ceil` and `abs`.
* `path(components...)`, as in `path("/avatars", person.id, "photo.jpg")`.
* `default(fallback)`, which stands in for nil or empty values, as in `person.nickname | default(person.firstName)`.

Text functions applied to a list apply to each element, so `files.name | lowercase | join(", ")` lists every name in lowercase.

## Formatting
Formatting functions show dates and numbers for people:

    Posted {% post.date | date %} at {% post.date | time %}
    Updated {% post.updated | relative %}
    Total: {% order.total | currency %}

They are:

* `date`, `time` and `dateTime`, as in `Oct 9, 2025` and `1:53 AM`.
* `relative`, as in `2 days ago`.
* `iso8601`, as in `2025-10-09T08:53:20Z`, which is also how dates render without a format.
* `number`, `percent` and `currency`, as in `1,234.5`, `25%` and `$1,234.50`.

For anything else, use `format` with a date pattern like `"MMM d, yyyy"` or a number pattern like `"#,##0.00"`, written the way DateFormatter and NumberFormatter take them.

    {% post.date | format("EEEE, MMMM d") %}
    {% item.weight | format("0.0") %} kg

Formats follow `TemplateOptions.locale`, `timeZone` and `currencyCode`, which default to the current locale, the current time zone and the locale's currency:

    var options = TemplateOptions()
    options.locale = Locale(identifier: "fr_FR")
    options.currencyCode = "EUR"

Dates can be `Date` values, ISO 8601 strings such as `"2025-10-09T08:53:20Z"` or `"2025-10-09"`, or numbers of seconds since 1970, so dates in JSON work too. They also compare with `<`, `>` and the rest, and work with `@min` and `@max`. A value a format doesn't fit, such as a name formatted as a date, passes through unchanged.

## Custom functions
Register your own in `TemplateOptions.functions`. `Functions.text` makes one from a transform of text:

    var options = TemplateOptions()
    options.functions["shout"] = Functions.text { $0.uppercased() + "!" }

A full function gets the value it's called on and its arguments:

    options.functions["initials"] = { receiver, _ in
       .string(receiver.renderedString.split(separator: " ").compactMap(\.first).map(String.init).joined())
    }

    {% person.name | shout %} {% person.name | initials %}

Any name works, even one like `function` or `all`, and a function you register replaces a standard one with the same name. Calling a function that isn't registered is an error when the template is created.

## Logging
To help debug a template, a **log** tag writes an expression's value to `TemplateOptions.log`, which prints to standard error by default. Log tags render nothing, and a render can switch them off by leaving `.log` out of its features.

    {% log(person.firstName) %}

## Custom expressions
Expressions are compiled through the `ExpressionCompiler` protocol, and `TemplateOptions.expressionCompiler` can replace the built-in `NativeExpressionCompiler` with your own.

## Benchmarks
`Benchmarks/run.sh` measures parsing and rendering the templates in `Benchmarks/Fixtures`, including rendering one template from every core at once.

## License
DMTemplates is available under the MIT license. See [LICENSE](LICENSE).

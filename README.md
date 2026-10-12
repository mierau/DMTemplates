# StringCheese
[![Test](https://github.com/mierau/string-cheese/actions/workflows/test.yml/badge.svg)](https://github.com/mierau/string-cheese/actions/workflows/test.yml)

A small Swift templating engine with enough features for the cases developers commonly face: values, conditions, loops, functions and logging.

A template is parsed once into an immutable, `Sendable` value, with every tag's expression compiled up front. Rendering is a pure function of the template and a context, so one template can render on many threads at once. It runs anywhere Swift 6 does, including Linux.

## Installation
Add StringCheese to your `Package.swift`:

    dependencies: [
       .package(url: "https://github.com/mierau/string-cheese", from: "3.0.0"),
    ],

Then add `"StringCheese"` to your target's dependencies. In Xcode, choose File › Add Package Dependencies and enter the same URL.

StringCheese needs Swift 6 and runs on macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1 and Linux.

StringCheese was called DMTemplates through 2.x. To move to 3.0, point the dependency at the URL above, depend on the `StringCheese` product, and change `import DMTemplates` to `import StringCheese`. Nothing else in the API changed.

## Use
Create a template and render it against a context:

    import StringCheese

    let template = try Template("Hello, my name is {% firstName %}.")
    let rendered = template.render(["firstName": "Dustin"])

**Rendered**: Hello, my name is Dustin.

A context is a `TemplateValue`, which you can write as a literal, as above. You can also render against Foundation or Swift values, such as a dictionary read from JSON or a property list, with `render(object:)`, or against any `Encodable` value with `render(encoding:)`. For large or expensive values a template only reads part of, see [Objects](#objects).

Mistakes in a template, such as an unclosed `if` or a typo in an expression, throw a `TemplateError` with a line and column when the template is created, rather than surfacing while it renders.

To load a template from a file, use `Template(contentsOf:)`. Tags are written between `{%` and `%}` by default; `TemplateOptions.beginDelimiter` and `endDelimiter` change them.

For long output, such as a large page or a file, `render(_:into:)` writes to any `TextOutputStream` in pieces as it goes, rather than building the whole result as one string first:

    var page = ""
    template.render(context, into: &page)

Servers and files that take bytes can have the UTF-8 handed straight to them instead, with no `String` in between:

    try template.render(context) { bytes in
       try handle.write(contentsOf: bytes)
    }

## Escaping
Templates don't assume they're HTML, so values are written as they are unless you ask for escaping. For HTML or XML templates, turn it on with `TemplateOptions.escaping`:

    var options = TemplateOptions()
    options.escaping = .html
    let page = try Template("<h1>{% post.title %}</h1>{% post.body | raw %}", options: options)

Every value tag then escapes `&`, `<`, `>`, `"` and `'`. A value tag ending in `| raw` is written as it is, for HTML you trust, and one ending in `| escape` isn't escaped twice. Template text and `log` tags are never escaped. `Escaping { ... }` takes your own transform for other formats.

## Expressions
Value tags, conditions and loops all take expressions, written in a syntax modeled on NSPredicate's:

* Key paths: `person.name`, `people[0]`, `person["first name"]`, `people[FIRST]`, `people[LAST]`, `people[SIZE]`. A key path through an array collects the key from every element, so `files.name` is an array of names. Indexing text gives a character, so `name[0]` is the first letter.
* Collection operators: `@count`, `@sum`, `@avg`, `@min` and `@max`, as in `people.@avg.age`.
* Arithmetic: `+ - * / %`. `+` also joins text, as in `"Hi " + person.name`, whenever either side is text that isn't a number.
* Comparisons: `== = != <> < <= > >=`, `BETWEEN`, `IN`, `CONTAINS`, `BEGINSWITH`, `ENDSWITH`, `LIKE` and `MATCHES`, with `[c]`, `[d]` or `[cd]` to ignore case or diacritics.
* Pattern matching: `LIKE` matches the whole string against a pattern where `*` stands for any run of characters and `?` for exactly one, so `file LIKE[c] "*.png"`. `MATCHES` takes a regular expression that has to match the whole string, as in `code MATCHES "[A-Z]{3}-[0-9]+"`. A pattern written in the template is checked when the template is created.
* Logic: `AND`, `OR` and `NOT`, or `&&`, `||` and `!`.
* Conditionals: `condition ? then : otherwise`, as in `{% done ? "✓" : "–" %}`. Only the side the condition picks is evaluated.
* Literals: strings, numbers, `true`/`false`/`YES`/`NO`, `nil`, and arrays written `{1, 2}` or `[1, 2]`.
* Exact decimals: `Decimal` values, such as prices, stay exact through arithmetic with whole numbers and other decimals, `@sum`, `@avg`, rounding and formatting.
* Function calls: `name.uppercase()`, `name | prefix(3)`, `path("~", name)`. See [Functions](#functions).

`ANY`, `ALL`, `SOME`, `NONE`, `SUBQUERY`, `CAST` and `TERNARY` are not supported and are reported as errors. Use `? :` in place of `TERNARY`.

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

## Whitespace
A `-` just inside a tag's delimiter trims the whitespace on that side of the tag, line breaks included. `{%-` trims before the tag and `-%}` after it:

    <ul>
      {%- foreach item in items -%}
      <li>{% item %}</li>
      {%- endforeach -%}
    </ul>

**Rendered**: `<ul><li>a</li><li>b</li></ul>`

Because `{%-` trims, write a negative number at the start of a tag with a space before it, as in `{% -1 %}`.

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

Inside a loop, the current index is available as the loop variable's name followed by `Index`, and whether it's the first or last element as the name followed by `IsFirst` and `IsLast`:

    {% foreach(contact in person.contacts) %}
      Contact {% contactIndex + 1 %}: {% contact.firstName %}
    {% endforeach %}

    {% foreach name in names %}{% if !nameIsFirst %}{% nameIsLast ? " and " : ", " %}{% endif %}{% name %}{% end %}

**Rendered**: Dustin, Mary Ann and Ollie

An **else** inside a loop runs when there's nothing to loop over:

    {% foreach contact in person.contacts %}
      {% contact.firstName %}
    {% else %}
      No contacts yet.
    {% endforeach %}

A loop over a dictionary gets each entry as `key` and `value`, in key order:

    {% foreach price in prices %}
      {% price.key %}: {% price.value | currency %}
    {% endforeach %}

## Variables
A **set** tag stores a value under a name, for the tags after it to use:

    {% set total = order.items.@sum.price %}
    Subtotal: {% total | currency %}
    With tax: {% (total * 1.08) | currency %}

A variable hides a key of the same name in the context. Setting a variable that's already set changes it, so a loop can add to a total set before the loop:

    {% set count = 0 %}
    {% foreach item in order.items %}{% set count = count + item.quantity %}{% endforeach %}
    {% count | pluralize("item") %}

A variable first set inside a loop belongs to that loop and is gone after it. One set inside an `if` stays in scope after the `endif`, so a condition can pick it:

    {% if order.isGift %}{% set greeting = "Enjoy your gift" %}{% else %}{% set greeting = "Thanks for your order" %}{% endif %}

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
* Output: `raw` leaves a value as it is (see [Escaping](#escaping)), `escape` escapes text for HTML and XML, `urlEncode` percent-encodes everything except letters, digits and `-._~`, and `bytes` shows a byte count for people, as in `1.9 MB`.
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

A misspelled key renders as nothing. To find typos like that, render with the `.strict` feature, which reports every key a tag asks for that the context doesn't have, with its line, to `TemplateOptions.log`. A key that's there with a `nil` value isn't reported.

    template.render(context, features: [.log, .strict])
    // line 3: no value for 'naem' in person.naem

## Comments
A tag starting with `#` is a comment and renders nothing.

    {%# Shown on the account page. %}

## Objects
Rendering usually starts by converting the whole context into `TemplateValue`s. For values that are large or expensive to read, of which a template only uses a part, such as model objects backed by a database, conform to `TemplateObject` instead. The template then asks for each key as it needs it:

    struct Account: TemplateObject {
       let id: Int

       func value(forKey key: String) -> TemplateValue? {
          switch key {
          case "name": return .string(database.name(of: id))
          case "orders": return .array(database.orders(of: id).map { .object($0) })
          default: return nil
          }
       }
    }

    template.render(["account": .object(Account(id: 7))])

Return nil for a key the object doesn't have, which strict mode reports, and `.null` for one that's there with no value. Where a template uses the object as one value, such as writing it out, looping over it or passing it to a function, it uses the object's `templateValue`, which defaults to its description.

On Apple platforms, `render(object:)` reads any other `NSObject`, such as a Core Data object, the same way, through its `@objc` properties. Render a Core Data object on its context's queue.

## Custom expressions
Expressions are compiled through the `ExpressionCompiler` protocol, and `TemplateOptions.expressionCompiler` can replace the built-in `NativeExpressionCompiler` with your own.

## Benchmarks
`Benchmarks/run.sh` measures parsing and rendering the templates in `Benchmarks/Fixtures`, including rendering one template from every core at once.

## License
StringCheese is available under the MIT license. See [LICENSE](LICENSE).

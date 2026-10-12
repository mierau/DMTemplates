# String Cheese
[![Test](https://github.com/mierau/string-cheese/actions/workflows/test.yml/badge.svg)](https://github.com/mierau/string-cheese/actions/workflows/test.yml)

String Cheese is a small, fast templating engine for Swift. You write text with tags in it, such as an email, a web page, a Markdown report or a config file, and render it against your data. It has the features templates commonly need, values, conditions, loops, variables, functions, formatting and escaping, and no dependencies beyond Foundation.

```jinja
Hi {% customer.firstName %},

{% foreach item in order.items %}
{% itemIndex + 1 %}. {% item.name %}{% if item.quantity > 1 %} × {% item.quantity %}{% endif %} ... {% (item.price * item.quantity) | currency %}
{% endforeach %}

Total: {% order.total | currency %}{% if order.total >= 50 %} (free shipping){% endif %}
```

```swift
import StringCheese

let template = try Template(contentsOf: url)
let email = try template.render(encoding: order)   // any Encodable value
```

```text
Hi Mary Ann,

1. Pour-over kettle ... $39.00
2. Single-origin beans, 12 oz × 2 ... $33.00

Total: $72.00 (free shipping)
```

## Why String Cheese
* **Parse once, render many times.** A template is parsed into an immutable, `Sendable` value with every tag's expression compiled up front, so rendering does no parsing. One template can render on many threads at once. See [Benchmarks](#benchmarks) for how that compares with other Swift engines.
* **Mistakes show up early.** An unclosed `if`, a typo in an expression or a call to a function that doesn't exist throws a `TemplateError` with a line and column when the template is created, not halfway through a render.
* **Expressions that go beyond lookups.** Arithmetic, comparisons, `AND`/`OR`, `? :`, pattern matching and collection operators like `@sum` and `@count`, in a syntax modeled on NSPredicate's.
* **Built-in functions and formatting.** Text, list and number functions, pluralizing, and locale-aware dates, numbers and currency, plus your own functions.
* **Renders what you already have.** `TemplateValue` literals, Foundation objects from JSON or property lists, any `Encodable` value, or your own objects read one key at a time.
* **Any kind of text.** Templates don't assume HTML. Turn on HTML escaping when you want it, trim whitespace around tags, and change the delimiters.
* **Runs everywhere Swift 6 does**, including Linux, with output written to a `String`, any `TextOutputStream` or straight to bytes.

## Contents
[Installation](#installation) · [Use](#use) · [Escaping](#escaping) · [Expressions](#expressions) · [Conditions](#conditions) · [Whitespace](#whitespace) · [Loops](#loops) · [Variables](#variables) · [Functions](#functions) · [Formatting](#formatting) · [Custom functions](#custom-functions) · [Logging](#logging) · [Comments](#comments) · [Objects](#objects) · [Custom expressions](#custom-expressions) · [Benchmarks](#benchmarks) · [License](#license)

## Installation
Add String Cheese to your `Package.swift`:

```swift
dependencies: [
   .package(url: "https://github.com/mierau/string-cheese", from: "3.0.0"),
],
```

Then add `"StringCheese"` to your target's dependencies. In Xcode, choose File › Add Package Dependencies and enter the same URL.

String Cheese needs Swift 6 and runs on macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1 and Linux.

String Cheese was called DMTemplates through 2.x. To move to 3.0, point the dependency at the URL above, depend on the `StringCheese` product, and change `import DMTemplates` to `import StringCheese`. Nothing else in the API changed.

## Use
Create a template and render it against a context:

```swift
import StringCheese

let template = try Template("Hello, my name is {% firstName %}.")
let rendered = template.render(["firstName": "Dustin"])
```

**Rendered**: Hello, my name is Dustin.

A context is a `TemplateValue`, which you can write as a literal, as above. You can also render against Foundation or Swift values, such as a dictionary read from JSON or a property list, with `render(object:)`, or against any `Encodable` value with `render(encoding:)`. For large or expensive values a template only reads part of, see [Objects](#objects).

Mistakes in a template, such as an unclosed `if` or a typo in an expression, throw a `TemplateError` with a line and column when the template is created, rather than surfacing while it renders.

To load a template from a file, use `Template(contentsOf:)`. Tags are written between `{%` and `%}` by default; `TemplateOptions.beginDelimiter` and `endDelimiter` change them.

For long output, such as a large page or a file, `render(_:into:)` writes to any `TextOutputStream` in pieces as it goes, rather than building the whole result as one string first:

```swift
var page = ""
template.render(context, into: &page)
```

Servers and files that take bytes can have the UTF-8 handed straight to them instead, with no `String` in between:

```swift
try template.render(context) { bytes in
   try handle.write(contentsOf: bytes)
}
```

## Escaping
Templates don't assume they're HTML, so values are written as they are unless you ask for escaping. For HTML or XML templates, turn it on with `TemplateOptions.escaping`:

```swift
var options = TemplateOptions()
options.escaping = .html
let page = try Template("<h1>{% post.title %}</h1>{% post.body | raw %}", options: options)
```

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

```jinja
{% if(person.contacts.@count == 0) %}
  Please add some contacts.
{% elseif(person.contacts.@count < 3) %}
  Add some more contacts.
{% else %}
  You have enough contacts.
{% endif %}
```

The parentheses are optional, so `{% if count > 2 %}` and `{% foreach contact in person.contacts %}` work too.

A control tag swallows the line break that follows it, so tags on lines of their own don't leave blank lines behind.

## Whitespace
A `-` just inside a tag's delimiter trims the whitespace on that side of the tag, line breaks included. `{%-` trims before the tag and `-%}` after it:

```jinja
<ul>
  {%- foreach item in items -%}
  <li>{% item %}</li>
  {%- endforeach -%}
</ul>
```

**Rendered**: `<ul><li>a</li><li>b</li></ul>`

Because `{%-` trims, write a negative number at the start of a tag with a space before it, as in `{% -1 %}`.

## Loops
A **foreach** loop runs over an array, which can come from a key path, an expression or an inline array.

```jinja
{% foreach(contact in person.contacts) %}
  Contact name: {% contact.firstName %} {% contact.lastName %}
{% endforeach %}

{% foreach(contactName in {"Dustin", "Mary Ann", "Ollie"}) %}
  Contact: {% contactName %}
{% endforeach %}

{% foreach(filename in files.name | lowercase) %}
  Lowercase file name: {% filename %}
{% endforeach %}
```

Inside a loop, the current index is available as the loop variable's name followed by `Index`, and whether it's the first or last element as the name followed by `IsFirst` and `IsLast`:

```jinja
{% foreach(contact in person.contacts) %}
  Contact {% contactIndex + 1 %}: {% contact.firstName %}
{% endforeach %}

{% foreach name in names %}{% if !nameIsFirst %}{% nameIsLast ? " and " : ", " %}{% endif %}{% name %}{% end %}
```

**Rendered**: Dustin, Mary Ann and Ollie

An **else** inside a loop runs when there's nothing to loop over:

```jinja
{% foreach contact in person.contacts %}
  {% contact.firstName %}
{% else %}
  No contacts yet.
{% endforeach %}
```

A loop over a dictionary gets each entry as `key` and `value`, in key order:

```jinja
{% foreach price in prices %}
  {% price.key %}: {% price.value | currency %}
{% endforeach %}
```

## Variables
A **set** tag stores a value under a name, for the tags after it to use:

```jinja
{% set total = order.items.@sum.price %}
Subtotal: {% total | currency %}
With tax: {% (total * 1.08) | currency %}
```

A variable hides a key of the same name in the context. Setting a variable that's already set changes it, so a loop can add to a total set before the loop:

```jinja
{% set count = 0 %}
{% foreach item in order.items %}{% set count = count + item.quantity %}{% endforeach %}
{% count | pluralize("item") %}
```

A variable first set inside a loop belongs to that loop and is gone after it. One set inside an `if` stays in scope after the `endif`, so a condition can pick it:

```jinja
{% if order.isGift %}{% set greeting = "Enjoy your gift" %}{% else %}{% set greeting = "Thanks for your order" %}{% endif %}
```

## Functions
Functions transform a value before it's shown. Pass a value through them with a pipe, or call them the way you'd call a method in Swift. These all mean the same thing:

```jinja
{% person.firstName | prefix(1) | uppercase %}
{% person.firstName.prefix(1).uppercase() %}
{% uppercase(prefix(person.firstName, 1)) %}
```

Pipes apply left to right and need no parentheses when there are no arguments. A pipe binds as tightly as `.`, so it works inside conditions, and parentheses pipe a whole expression:

```jinja
{% person.bio | trim | escape %}
{% if(post.title | lowercase BEGINSWITH "draft") %}(unpublished){% endif %}
{% (item.price * item.quantity) | currency %}
```

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

```jinja
Posted {% post.date | date %} at {% post.date | time %}
Updated {% post.updated | relative %}
Total: {% order.total | currency %}
```

They are:

* `date`, `time` and `dateTime`, as in `Oct 9, 2025` and `1:53 AM`.
* `relative`, as in `2 days ago`.
* `iso8601`, as in `2025-10-09T08:53:20Z`, which is also how dates render without a format.
* `number`, `percent` and `currency`, as in `1,234.5`, `25%` and `$1,234.50`.

For anything else, use `format` with a date pattern like `"MMM d, yyyy"` or a number pattern like `"#,##0.00"`, written the way DateFormatter and NumberFormatter take them.

```jinja
{% post.date | format("EEEE, MMMM d") %}
{% item.weight | format("0.0") %} kg
```

Formats follow `TemplateOptions.locale`, `timeZone` and `currencyCode`, which default to the current locale, the current time zone and the locale's currency:

```swift
var options = TemplateOptions()
options.locale = Locale(identifier: "fr_FR")
options.currencyCode = "EUR"
```

Dates can be `Date` values, ISO 8601 strings such as `"2025-10-09T08:53:20Z"` or `"2025-10-09"`, or numbers of seconds since 1970, so dates in JSON work too. They also compare with `<`, `>` and the rest, and work with `@min` and `@max`. A value a format doesn't fit, such as a name formatted as a date, passes through unchanged.

## Custom functions
Register your own in `TemplateOptions.functions`. `Functions.text` makes one from a transform of text:

```swift
var options = TemplateOptions()
options.functions["shout"] = Functions.text { $0.uppercased() + "!" }
```

A full function gets the value it's called on and its arguments:

```swift
options.functions["initials"] = { receiver, _ in
   .string(receiver.renderedString.split(separator: " ").compactMap(\.first).map(String.init).joined())
}
```

```jinja
{% person.name | shout %} {% person.name | initials %}
```

Any name works, even one like `function` or `all`, and a function you register replaces a standard one with the same name. Calling a function that isn't registered is an error when the template is created.

## Logging
To help debug a template, a **log** tag writes an expression's value to `TemplateOptions.log`, which prints to standard error by default. Log tags render nothing, and a render can switch them off by leaving `.log` out of its features.

```jinja
{% log(person.firstName) %}
```

A misspelled key renders as nothing. To find typos like that, render with the `.strict` feature, which reports every key a tag asks for that the context doesn't have, with its line, to `TemplateOptions.log`. A key that's there with a `nil` value isn't reported.

```swift
template.render(context, features: [.log, .strict])
// line 3: no value for 'naem' in person.naem
```

## Comments
A tag starting with `#` is a comment and renders nothing.

```jinja
{%# Shown on the account page. %}
```

## Objects
Rendering usually starts by converting the whole context into `TemplateValue`s. For values that are large or expensive to read, of which a template only uses a part, such as model objects backed by a database, conform to `TemplateObject` instead. The template then asks for each key as it needs it:

```swift
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
```

Return nil for a key the object doesn't have, which strict mode reports, and `.null` for one that's there with no value. Where a template uses the object as one value, such as writing it out, looping over it or passing it to a function, it uses the object's `templateValue`, which defaults to its description.

On Apple platforms, `render(object:)` reads any other `NSObject`, such as a Core Data object, the same way, through its `@objc` properties. Render a Core Data object on its context's queue.

## Custom expressions
Expressions are compiled through the `ExpressionCompiler` protocol, and `TemplateOptions.expressionCompiler` can replace the built-in `NativeExpressionCompiler` with your own.

## Benchmarks
String Cheese parses a template once and compiles its expressions, so a render only walks the compiled template and reads the context. To see what that buys, the benchmarks render the same page with String Cheese and three other Swift template engines: [Stencil](https://github.com/stencilproject/Stencil), [Mustache](https://github.com/hummingbird-project/swift-mustache) (Hummingbird's) and [Leaf](https://github.com/vapor/leaf-kit) (Vapor's LeafKit).

The page is a heading and a list of 100 people, each with a name, a city and an `(admin)` marker shown by a condition. Every engine escapes HTML, and the benchmark checks that each one's output matches String Cheese's, ignoring whitespace, before timing it. Each engine has its own copy of the template, in [`Benchmarks/Comparison/Fixtures`](Benchmarks/Comparison/Fixtures).

BENCHMARK_RESULTS

**Render, parsed once** is the usual case for an app or server: the template is created once and rendered for each request. **Parse and render** creates the template every time. Lower is better, and the multiple compares each engine with String Cheese. A few things to know when reading them:

* String Cheese renders from a `TemplateValue` decoded from JSON once up front. Its `render(object:)` row renders from the same dictionary of Swift values Stencil and Mustache get, converting it on every render. Leaf gets its own `LeafData` values, built once up front.
* Stencil tokenizes a template when it's created but parses it on every render, so its two rows are close.
* Leaf renders through SwiftNIO futures. The benchmark runs them on an embedded event loop with the template in memory, so no time goes to threads or files. Parse and render turns Leaf's template cache off.
* These are shared GitHub Actions machines, so expect some noise from run to run. Compare engines within a row rather than across runs.

To run the comparison yourself, run `Benchmarks/Comparison/run.sh`, which takes the number of seconds to spend on each measurement, 1 by default (CI uses 2). It needs network access the first time to fetch the other engines. The [Benchmarks workflow](.github/workflows/benchmarks.yml) runs it on Linux and macOS for every pull request that touches the library or the benchmarks, and puts the table in the run's summary; you can also start it by hand from the Actions tab.

`Benchmarks/run.sh` measures String Cheese alone on the templates in [`Benchmarks/Fixtures`](Benchmarks/Fixtures): parsing, rendering, rendering from Foundation objects, and rendering one template from every core at once. It has no dependencies, so it's the one to run while working on the engine.

## License
String Cheese is available under the MIT license. See [LICENSE](LICENSE).

# Rendering Templates

Render templates safely, quickly and from many threads.

## Escaping

Templates don't assume they're HTML, so values are written as they are. For HTML or XML, turn on escaping:

```swift
var options = TemplateOptions()
options.escaping = .html
let page = try Template("<h1>{% post.title %}</h1>{% post.body | raw %}", options: options)
```

Every value tag then escapes `&`, `<`, `>`, `"` and `'`. A value tag ending in `| raw` is written as it is, and one ending in `| escape` isn't escaped twice. Template text and `log` tags are never escaped. ``Escaping/init(_:)`` takes your own transform for other formats.

## Streaming

``Template/render(_:features:into:)`` writes to any `TextOutputStream` in pieces as it goes, rather than building the whole result as one string, which keeps memory down for long output. Rendering into a `String` appends to it.

## Concurrency

A ``Template`` is an immutable, `Sendable` value. Create it once, then render it from as many threads or tasks as you like; rendering touches no shared mutable state. Formatters are made the first time a template uses them and shared by every template with the same locale, time zone and currency.

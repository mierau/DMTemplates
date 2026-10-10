# ``DMTemplates``

A small, fast templating engine for Swift 6.

## Overview

A template is text with tags between `{%` and `%}`: values, conditions, loops and logging. Creating a ``Template`` parses it and compiles every tag's expression, and throws a ``TemplateError`` with a line and column for mistakes such as an unclosed `if`. Rendering is then a pure function of the template and a context, so one template can render on many threads at once.

```swift
import DMTemplates

let template = try Template("Hello, {% person.firstName %}. You have {% messages.@count | pluralize(\"message\") %}.")
let text = template.render(["person": ["firstName": "Dustin"], "messages": [1, 2, 3]])
// "Hello, Dustin. You have 3 messages."
```

A context is a ``TemplateValue``, which you can write as a literal, as above, make from Foundation values with ``Template/render(object:features:)``, or from any `Encodable` value with ``Template/render(encoding:features:)``.

## Topics

### Essentials

- <doc:TemplateSyntax>
- <doc:FunctionsAndFormatting>
- ``Template``
- ``TemplateValue``
- ``TemplateError``

### Rendering

- <doc:RenderingTemplates>
- ``TemplateOptions``
- ``Escaping``
- ``RenderFeatures``

### Extending

- ``Functions``
- ``ExpressionCompiler``
- ``CompiledExpression``
- ``ExpressionScope``
- ``ExpressionError``
- ``NativeExpressionCompiler``
- ``NativeExpression``

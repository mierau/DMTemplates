# Template Syntax

Write values, conditions and loops in a template.

## Values

A value tag writes the value of an expression. A missing key writes nothing.

```
Hello, {% person.firstName %}.
```

## Conditions

Templates support `if`, `elseif` and `else`, closed by `endif`. `else if` and a bare `end` work too, and the parentheses are optional.

```
{% if person.contacts.@count == 0 %}
  Please add some contacts.
{% elseif(person.contacts.@count < 3) %}
  Add some more contacts.
{% else %}
  You have enough contacts.
{% endif %}
```

A control tag swallows the line break that follows it, so tags on lines of their own don't leave blank lines behind.

## Loops

A `foreach` loop runs over an array from a key path, an expression or an inline array. The current index is the loop variable's name followed by `Index`.

```
{% foreach contact in person.contacts %}
  {% contactIndex + 1 %}. {% contact.firstName %}
{% endforeach %}

{% foreach(name in {"Dustin", "Mary Ann", "Ollie"}) %}{% name %} {% end %}
```

## Expressions

Value tags, conditions and loops take expressions, written in a syntax modeled on NSPredicate's:

- Key paths: `person.name`, `people[0]`, `person["first name"]`, `people[FIRST]`, `people[LAST]`, `people[SIZE]`. A key path through an array collects the key from every element, so `files.name` is an array of names.
- Collection operators: `@count`, `@sum`, `@avg`, `@min` and `@max`, as in `people.@avg.age`.
- Arithmetic: `+ - * / %`. `+` also joins text, as in `"Hi " + person.name`, whenever either side is text that isn't a number.
- Comparisons: `== = != <> < <= > >=`, `BETWEEN`, `IN`, `CONTAINS`, `BEGINSWITH`, `ENDSWITH`, `LIKE` and `MATCHES`, with `[c]`, `[d]` or `[cd]` to ignore case or diacritics.
- Logic: `AND`, `OR` and `NOT`, or `&&`, `||` and `!`.
- Literals: strings, numbers, `true`/`false`/`YES`/`NO`, `nil`, and arrays written `{1, 2}` or `[1, 2]`.
- Function calls: `name.uppercase()`, `name | prefix(3)` or `prefix(name, 3)`. See <doc:FunctionsAndFormatting>.

Numbers read from text, such as `"41"`, act as numbers. `Decimal` values, such as prices, stay exact through arithmetic with whole numbers and other decimals.

## Logging

A `log` tag writes an expression's value to ``TemplateOptions/log`` and renders nothing. A render can switch log tags off by leaving ``RenderFeatures/log`` out of its features.

```
{% log(person.firstName) %}
```

## Delimiters

``TemplateOptions/beginDelimiter`` and ``TemplateOptions/endDelimiter`` change `{%` and `%}`.

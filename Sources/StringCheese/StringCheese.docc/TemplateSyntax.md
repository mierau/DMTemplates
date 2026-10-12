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

## Whitespace

A `-` just inside a tag's delimiter trims the whitespace on that side of the tag, line breaks included: `{%-` before the tag and `-%}` after it. Write a negative number at the start of a tag with a space before it, as in `{% -1 %}`.

```
<ul>
  {%- foreach item in items -%}
  <li>{% item %}</li>
  {%- endforeach -%}
</ul>
```

## Loops

A `foreach` loop runs over an array from a key path, an expression or an inline array. The current index is the loop variable's name followed by `Index`, and whether it's the first or last element is the name followed by `IsFirst` and `IsLast`.

```
{% foreach contact in person.contacts %}
  {% contactIndex + 1 %}. {% contact.firstName %}
{% endforeach %}

{% foreach(name in {"Dustin", "Mary Ann", "Ollie"}) %}{% name %} {% end %}

{% foreach name in names %}{% if !nameIsFirst %}{% nameIsLast ? " and " : ", " %}{% endif %}{% name %}{% end %}
```

An `else` inside a loop runs when there's nothing to loop over. A loop over a dictionary gets each entry as `key` and `value`, in key order.

```
{% foreach price in prices %}
  {% price.key %}: {% price.value | currency %}
{% else %}
  No prices yet.
{% endforeach %}
```

## Variables

A `set` tag stores a value under a name for the tags after it. A variable hides a context key of the same name, and setting one that's already set changes it, so a loop can add to a total set before it. A variable first set inside a loop is gone after the loop; one set inside an `if` stays in scope after it.

```
{% set total = 0 %}
{% foreach item in order.items %}{% set total = total + item.price * item.quantity %}{% endforeach %}
Total: {% total | currency %}
```

## Expressions

Value tags, conditions and loops take expressions, written in a syntax modeled on NSPredicate's:

- Key paths: `person.name`, `people[0]`, `person["first name"]`, `people[FIRST]`, `people[LAST]`, `people[SIZE]`. A key path through an array collects the key from every element, so `files.name` is an array of names. Indexing text gives a character, so `name[0]` is the first letter.
- Collection operators: `@count`, `@sum`, `@avg`, `@min` and `@max`, as in `people.@avg.age`.
- Arithmetic: `+ - * / %`. `+` also joins text, as in `"Hi " + person.name`, whenever either side is text that isn't a number.
- Comparisons: `== = != <> < <= > >=`, `BETWEEN`, `IN`, `CONTAINS`, `BEGINSWITH`, `ENDSWITH`, `LIKE` and `MATCHES`, with `[c]`, `[d]` or `[cd]` to ignore case or diacritics.
- Logic: `AND`, `OR` and `NOT`, or `&&`, `||` and `!`.
- Conditionals: `condition ? then : otherwise`, as in `done ? "✓" : "–"`. Only the side the condition picks is evaluated.
- Literals: strings, numbers, `true`/`false`/`YES`/`NO`, `nil`, and arrays written `{1, 2}` or `[1, 2]`.
- Function calls: `name.uppercase()`, `name | prefix(3)` or `prefix(name, 3)`. See <doc:FunctionsAndFormatting>.

Numbers read from text, such as `"41"`, act as numbers. `Decimal` values, such as prices, stay exact through arithmetic with whole numbers and other decimals.

## Logging

A `log` tag writes an expression's value to ``TemplateOptions/log`` and renders nothing. A render can switch log tags off by leaving ``RenderFeatures/log`` out of its features.

```
{% log(person.firstName) %}
```

A misspelled key renders as nothing. Rendering with ``RenderFeatures/strict`` reports every key a tag asks for that the context doesn't have, with its line, to ``TemplateOptions/log``.

## Comments

A tag starting with `#`, such as `{%# Shown on the account page. %}`, is a comment and renders nothing.

## Delimiters

``TemplateOptions/beginDelimiter`` and ``TemplateOptions/endDelimiter`` change `{%` and `%}`.

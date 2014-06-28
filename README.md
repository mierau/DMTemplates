# DMTemplates
An Objective-C templating engine designed to be easy to use (single class, simple interface) with features enough to handle the cases commonly faced by developers in need of a such a library. The engine sits on top of the advanced key-value syntax and parsing done through Apple's NSPredicate and NSExpression classes for conditions and value expressions in templates.

## Use
In most cases, you'll probably follow these steps to render a template:

1. Create a DMTemplateEngine instance.
2. Read your template from disk into an NSString.
3. Set the template string on your DMTemplateEngine instance.
4. Build an object (typically an NSDictionary) containing the data you'll be referencing in your template.
5. Render your template against this object.

Like so:

    DMTemplateEngine* engine = [DMTemplateEngine engine];
    engine.template = @"Hello, my name is <? firstName />.";
    
    NSMutableDictionary* templateData = [NSMutableDictionary dictionary];
    [templateData setObject:@"Dustin" forKey:@"firstName"];
    
    NSString* renderedTemplate = [engine renderAgainst:templateData];

**Rendered**: Hello, my name is Dustin.

## Conditions
For conditional template output, DMTemplateEngine supports **if**, **elseif**, and **else** statements. Because DMTemplateEngine makes use of Foundation's NSPredicate class, conditional statements can make use of the same advanced key-value expressions.

### Example

    <? if(person.contacts.@count == 0) />
      Please add some contacts.
    <? elseif(person.contacts.@count < 3) />
      Add some more contacts.
    <? else />
      You have enough contacts.
    <? endif />

## Loops
Along with conditions, DMTemplateEngine also supports **foreach** loops. The syntax is fairly similar to that of the fast enumeration syntax found in Objective-C, except you don't specify a type, and the specified value to enumerate over can be a simple key-value, or a key-value expression, or an inline ASCII property list.

### Example

    <? foreach(contact in person.contacts) />
      Contact name: <? contact.firstName /> <? contact.lastName />
    <? endforeach />
    
### Inline Example

    <? foreach(contactName in {"Dustin", "Mary Ann", "Ollie"}) />
      Contact: <? contactName />
    <? endforeach />
    
### Key-Value Expression Example

    <? foreach(contactFirstName in person.contacts.firstName) />
      Contact: <? contactFirstName />
    <? endforeach />
    
### Loop Index Example
Within the scope of a foreach loop, the current iteration index is made available automatically.

    <? foreach(contact in person.contacts) />
      Contact <? contactIndex+1 />: <? contact.firstName />
    <? endforeach />

## Modifiers
It's common to want to process a template value before rendering it (e.g. trim whitespace, escape xml, etc.). DMTemplateEngine makes this possible through **modifiers**. Modifiers are specified by a sequence of characters surrounded by square brackets at the beginning of a template value tag.

### Example
Assuming a modifier is defined for the character 'w'.

    <?[w] person.firstName />

### Built-in Modifiers

Escape XML modifier.

    <?[e] person.firstName />
    
Escape URL modifier.

    http://www.website.com/profile?id=<?[u] person.id />
    
Human readable byte size modifier.

    The file size is: <?[b] file.fileSize />
    
### Custom Modifier Example
Along with the built-in modifiers, you can define your own. Let's say you want to define a modifier that trims whitespace from a template value before rendering it. You do so by defining a block that takes the original template value string and outputs a modified version of it.

    DMTemplateEngine* engine = [DMTemplateEngine engine];
    [engine addModifier:'w' block:^(NSString* content) {
      return [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }];

    engine.template = @"First name is <?[w] firstName />.";
    NSString* renderedTemplate = [engine renderAgainst:templateData];

**Rendered**: First name is Dustin.

### Multiple Modifiers Example
Multiple modifiers can also be applied to a template value. Multiple modifiers are applied in the order they are defined. So, if you wanted to trim the whitespace from and then escape a template value.

    <?[we] person.firstName />

## Logging
To aid with debugging templates, you can log template expressions using the **log** method. Apple's **NSLog** method is used to output your logged template values, so expect them to appear in the same place.

    <? log(person.firstName) />

## Advanced
DMTemplateEngine makes use of Apple's NSPredicate and NSExpression classes to parse and evaluate expressions in templates run through it. As a result, you can make use of all the advanced expression features supported by both classes.

### Arrays Example
It's possible to quickly create an array of property values of another array's elements. So, if you have an array of objects each with a name property and you'd like to iterate over the lowercase version of each object's name, you'd simply write:

    <? foreach(filename in files.name.lowercaseString) />
      Lowercase file name: <? filename />
    <? endforeach />


### Invoking Methods Example
Apple's NSExpression library supports invoking methods (optionally with arguments) on values through the **function** function. This allows you to run really any code against template values. The syntax is more archaic than that of DMTemplateEngine's modifiers, but can be very useful in one-off situations.

#### Simple

    <? function(person.firstName, "substringToIndex:", 5) />

#### Arguments

    <? function(person.firstName, "substringToIndex:", 5) />

#### Nested

    <? function(function(person.firstName, "substringToIndex:", 5), "uppercaseString") />

#### Class Methods

    <? function("".class, "pathWithComponents:", {"~", "dustin", "photo.jpg"}) />

MIT License
-----------

Copyright (c) 2010 Dustin Mierau

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
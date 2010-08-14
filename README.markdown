DMTemplates
===========
An Objective-C templating engine.

Goal
----
Yes, there are other templating libraries out there, but they're either too complicated, or too slow, or too limited. The goal of DMTemplates is to create an easy to use (single class, simple interface) templating engine with features enough to handle the cases commonly faced by developers in need of a such a library.

Installation
------------
Simply copy the DMTemplateEngine header and source files into your project. They're located in the Source folder of the project.

Overview
--------
The DMTemplateEngine renders templates against objects using key-value expressions and predicates for logic.

    NSMutableDictionary* templateData = [NSMutableDictionary dictionary];
    [templateData setObject:@"Dustin" forKey:@"firstName"];

    DMTemplateEngine* engine = [DMTemplateEngine engine];
    engine.template = @"Hello, my name is <? firstName />.";

    NSString* output = [engine renderAgainst:templateData];

**Output**: Hello, my name is Dustin.

Logic
-----
The engine supports some basic logic, like foreach loops and if statements. The conditions specified in each use the exact same syntax as predicates. Check Apple's documentation on key-value coding and NSPredicate syntax for more information.

    NSMutableDictionary* templateData = [NSMutableDictionary dictionary];
    [templateData setObject:@"Dustin" forKey:@"firstName"];
    [templateData setObject:[NSArray arrayWithObjects:@"Mary Ann", @"Garry", @"Katie", @"Ollie", nil] forKey:@"friends"];
    
    DMTemplateEngine* engine = [DMTemplateEngine engine];
    engine.template = @"Hello, my name is <? firstName />.
    <? if(friends.@count > 0) />
    I have <? friends.@count /> friends:
    <? foreach(friend in friends) />
      * <? friend /> (<? friendIndex+1 /> of <? friends.@count />)
    <? endforeach />
    <? else />
    You have no friends.
    <? endif />";
    
    NSString* output = [engine renderAgainst:templateData];
    
**Output**  
Hello, my name is Dustin.  
I have 4 friends:  
* Mary Ann (1 of 4)  
* Garry (2 of 4)  
* Katie (3 of 4)  
* Ollie (4 of 4)

Modifiers
---------
It can be quite useful to run a template value through some processing before rendering it. For example, you may want to trim and escape some user generated content. DMTemplates makes this possible through modifiers. The engine has a few useful modifiers built-in, but you can easily add your own.

    NSMutableDictionary* templateData = [NSMutableDictionary dictionary];
    [templateData setObject:@"  \nDustin " forKey:@"firstName"];

    DMTemplateEngine* engine = [DMTemplateEngine engine];
    engine.template = @"First name is <?[w] firstName />.";
    [engine addModifier:'w' block:^(NSString* content) {
      return [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }];

    NSString* output = [engine renderAgainst:templateData];

**Output**: First name is Dustin.

The following modifiers are built-in:

**'e'** - Use this modifier to escape valid XML characters in a template value.

    DMTemplateEngine* engine = [DMTemplateEngine engineWithTemplate:@"Escaped: <?[e] xmlToEscape />"];
    NSString* output = [engine renderAgainst:[NSDictionary dictionaryWithObject:@"I like <xml> & <html></html>." forKey:@"xmlToEscape"]];

**Output**: Escaped: I like &lt;xml&gt; &amp; &lt;html&gt;&lt;/html&gt;.

**'u'** - Use this modifier to URL encode a template value.

    DMTemplateEngine* engine = [DMTemplateEngine engineWithTemplate:@"Search: http://www.google.com/?s=<?[u] searchQuery />"];
    NSString* output = [engine renderAgainst:[NSDictionary dictionaryWithObject:@"düstin miérau" forKey:@"searchQuery"]];

**Output**: Search: http://www.google.com/?s=d%C3%BCstin%20mi%C3%A9rau

**'b'** - Use this modifier to turn a numeric template value into a human readable byte size.

    DMTemplateEngine* engine = [DMTemplateEngine engineWithTemplate:@"The file size is <?[b] fileSize /> big."];
    NSString* output = [engine renderAgainst:[NSDictionary dictionaryWithObject:@"23423422" forKey:@"fileSize"]];

**Output**: The file size is 22.3 MB big.

Logging
-------
If you find the need to quickly log a template value to the console, you can do so with the **log** method.

    NSDictionary* templateData = [NSDictionary dictionaryWithObject:@"Dustino" forKey:@"name"];
    [[DMTemplateEngine engineWithTemplate:@"<? log(name) />"] renderAgainst:templateData];

Template values are logged using NSLog and our not rendered to the resulting string.

License (MIT)
-------------

Copyright (c) 2010 Dustin Mierau

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
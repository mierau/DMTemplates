DMTemplates
===========
A templating engine for Objective-C.

Installation
------------
Simply copy the DMTemplateEngine header and source files into your project. They're located in the Source folder of the project.

Overview
--------

The DMTemplateEngine renders templates against objects using key-value coding and predicates for logic.

    NSMutableDictionary* templateData = [NSMutableDictionary dictionary];
    [templateData setObject:@"Dustin" forKey:@"firstName"];

    DMTemplateEngine* engine = [DMTemplateEngine engine];
    engine.template = @"Hello, my name is <? firstName />.";

    NSString* output = [engine renderAgainst:templateData];

**Output**: @"Hello, my name is Dustin."

Logic
-----

The engine supports some basic logic, like foreach loops and if statements. The conditions specified in each use the exact same syntax as predicates. Check Apple's documentation on key-value coding and NSPredicate syntax for more information.

    NSMutableDictionary* templateData = [NSMutableDictionary dictionary];
    [templateData setObject:@"Dustin" forKey:@"firstName"];
    [templateData setObject:[NSArray arrayWithObjects:@"Mary Ann", @"Garry", @"Katie", @"Ollie", nil] forKey:@"friends"];
    
    DMTemplateEngine* engine = [DMTemplateEngine engine];
    engine.template = @"Hello, my name is <? firstName />.
    I have <? friends.@count /> friends:
    <? foreach(friends) />
      * <? description />
    <? endforeach />";
    
    NSString* output = [engine renderAgainst:templateData];
    
**Output**:  
Hello, my name is Dustin.  
I have 4 friends:  
* Mary Ann  
* Garry  
* Katie  
* Ollie  

Modifiers
---------

It can be useful to run a method against a template value before rendering it. For example, you may want to escape some user controlled content. DMTemplates makes this possible through modifiers. The engine has a few useful modifiers built-in, but you can easily add your own.

    NSMutableDictionary* templateData = [NSMutableDictionary dictionary];
    [templateData setObject:@"  \nDustin " forKey:@"firstName"];

    DMTemplateEngine* engine = [DMTemplateEngine engine];
    engine.template = @"First name: <?[w] firstName />";
    [engine addModifier:'w' block:^(NSString* content) {
      return [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }];

    NSString* output = [engine renderAgainst:templateData];

**Output**: @"First name: Dustin"

License - MIT
-------------

Copyright (c) 2010 Dustin Mierau

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
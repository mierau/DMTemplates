# Sauce
Templating engine in the spirit of DMTemplates written in Swift.

## Basic Usage

    let sauce = Sauce(file:"~/Desktop/example.sauce".stringByExpandingTildeInPath);
    let object = ["people": [["first": "Dustin", "last": "Mierau", "age": 32], ["first": "Garry", "last": "Mierau", "age": 56]]]
    let rendering = sauce.render(object)
    println(rendering)

**Rendered**:

    2 People: 
    
      1: Dustin MIERAU, 32 
      2: Garry MIERAU, 56 
    
    Average age is 44

## More

Check out example.sauce.
Check out DMTemplates README.
Check out NSPredicate programming guide.

MIT License
-----------

Copyright (c) 2014 Dustin Mierau

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
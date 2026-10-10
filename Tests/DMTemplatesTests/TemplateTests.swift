// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation
import Testing
@testable import DMTemplates

private func render(_ source: String, _ context: TemplateValue = nil, options: TemplateOptions = TemplateOptions()) throws -> String {
   try Template(source, options: options).render(context)
}

@Suite struct TextTests {
   @Test func emptyTemplates() throws {
      #expect(try render("") == "")
      #expect(try render("  ") == "  ")
      #expect(try render(" \n") == " \n")
      #expect(try render("\n ") == "\n ")
   }

   @Test func plainText() throws {
      #expect(try render("Hello, world.") == "Hello, world.")
      #expect(try render("100% {} done") == "100% {} done")
   }

   @Test func emptyTagsRenderNothing() throws {
      #expect(try render("a{%%}b{%  %}c") == "abc")
   }

   @Test func customDelimiters() throws {
      var options = TemplateOptions()
      options.beginDelimiter = "<<"
      options.endDelimiter = ">>"
      #expect(try render("Hi <<name>>, {% name %}", ["name": "Dustin"], options: options) == "Hi Dustin, {% name %}")
   }

   @Test func unicodeText() throws {
      #expect(try render("Düstin {% x %} 🙂", ["x": "Mîeråü"]) == "Düstin Mîeråü 🙂")
   }
}

@Suite struct ValueTests {
   let context: TemplateValue = [
      "firstName": "Dustin",
      "age": 32,
      "ratio": 0.5,
      "flag": true,
      "people": [
         ["first": "Dustin", "last": "Mierau", "age": 32],
         ["first": "Garry", "last": "Mierau", "age": 56],
      ],
      "nested": ["a": ["b": ["c": "deep"]]],
   ]

   @Test func keyPaths() throws {
      #expect(try render("{% firstName %}", context) == "Dustin")
      #expect(try render("{% nested.a.b.c %}", context) == "deep")
      #expect(try render("[{% missing %}][{% nested.nope.c %}]", context) == "[][]")
   }

   @Test func numbersAndBooleans() throws {
      #expect(try render("{% age %} {% ratio %} {% flag %}", context) == "32 0.5 true")
   }

   @Test func arithmetic() throws {
      #expect(try render("{% age + 1 %}", context) == "33")
      #expect(try render("{% age-2 %}", context) == "30")
      #expect(try render("{% age * 2 %}", context) == "64")
      #expect(try render("{% age / 64 %}", context) == "0.5")
      #expect(try render("{% age / 2 %}", context) == "16")
      #expect(try render("{% age % 5 %}", context) == "2")
      #expect(try render("{% (1 + 2) * 3 %}", context) == "9")
      #expect(try render("{% -age + 2 %}", context) == "-30")
      #expect(try render("{% 1 / 0 %}", context) == "")
   }

   @Test func numericStringsCoerce() throws {
      #expect(try render("{% size + 1 %}", ["size": "41"]) == "42")
   }

   @Test func collectionOperators() throws {
      #expect(try render("{% people.@count %}", context) == "2")
      #expect(try render("{% people.@avg.age %}", context) == "44")
      #expect(try render("{% people.@sum.age %}", context) == "88")
      #expect(try render("{% people.@min.age %} {% people.@max.age %}", context) == "32 56")
      #expect(try render("{% people.@max.first %}", context) == "Garry")
      #expect(try render("{% firstName.@count %}", context) == "6")
   }

   @Test func keyPathsMapOverArrays() throws {
      #expect(try render("{% people.first %}", context) == "Dustin, Garry")
      #expect(try render("{% people.first | uppercased %}", context) == "DUSTIN, GARRY")
   }

   @Test func subscripts() throws {
      #expect(try render("{% people[1].first %}", context) == "Garry")
      #expect(try render("{% people[0][\"last\"] %}", context) == "Mierau")
      #expect(try render("{% people[FIRST].first %} {% people[LAST].first %} {% people[SIZE] %}", context) == "Dustin Garry 2")
      #expect(try render("{% people[9].first %}", context) == "")
   }

   @Test func literals() throws {
      #expect(try render("{% \"quoted\" %} {% 'single' %} {% 2.5 %} {% {1, 2, 3} %}") == "quoted single 2.5 1, 2, 3")
      #expect(try render("{% nil %}|{% YES %}|{% false %}") == "|true|false")
   }

   @Test func stringsHaveNoProperties() throws {
      #expect(try render("{% firstName.@count %}|{% firstName.lowercaseString %}", context) == "6|")
   }
}

@Suite struct ConditionTests {
   @Test func ifElse() throws {
      let source = "{% if(count > 2) %}many{% else %}few{% endif %}"
      #expect(try render(source, ["count": 3]) == "many")
      #expect(try render(source, ["count": 1]) == "few")
   }

   @Test func elseIfChains() throws {
      let source = """
      {% if(person.contacts.@count == 0) %}
      Please add some contacts.
      {% elseif(person.contacts.@count < 3) %}
      Add some more contacts.
      {% else %}
      You have enough contacts.
      {% endif %}
      """
      #expect(try render(source, ["person": ["contacts": []]]) == "Please add some contacts.\n")
      #expect(try render(source, ["person": ["contacts": [1, 2]]]) == "Add some more contacts.\n")
      #expect(try render(source, ["person": ["contacts": [1, 2, 3]]]) == "You have enough contacts.\n")
   }

   @Test func elseIfStopsAtFirstMatch() throws {
      let source = "{% if(x == 1) %}one{% elseif(x > 0) %}positive{% elseif(x > -5) %}small{% else %}other{% endif %}"
      #expect(try render(source, ["x": 1]) == "one")
      #expect(try render(source, ["x": 2]) == "positive")
      #expect(try render(source, ["x": -1]) == "small")
      #expect(try render(source, ["x": -9]) == "other")
   }

   @Test func elseIfFalseFallsThroughToElse() throws {
      // DMTemplateEngine reads `elseif` as `else`, so this rendered "B" there.
      let source = "{% if(false) %}A{% elseif(false) %}B{% else %}C{% endif %}"
      #expect(try render(source) == "C")
   }

   @Test func sauceStyleElseIfAndEnd() throws {
      let source = "{% if(x == 1) %}one{% else if(x == 2) %}two{% end %}"
      #expect(try render(source, ["x": 2]) == "two")
   }

   @Test func nestedConditions() throws {
      let source = "{% if(a) %}A{% if(b) %}B{% else %}b{% endif %}{% else %}x{% endif %}"
      #expect(try render(source, ["a": true, "b": true]) == "AB")
      #expect(try render(source, ["a": true, "b": false]) == "Ab")
      #expect(try render(source, ["a": false, "b": true]) == "x")
   }

   @Test func operators() throws {
      let context: TemplateValue = ["name": "Dustin", "size": 50, "tags": ["swift", "objc"], "empty": ""]
      let cases: [(String, Bool)] = [
         ("size between {0, 100}", true),
         ("size BETWEEN {51, 100}", false),
         ("name == 'Dustin'", true),
         ("name = 'dustin'", false),
         ("name ==[c] 'dustin'", true),
         ("name != 'Bob'", true),
         ("name <> 'Dustin'", false),
         ("name BEGINSWITH 'Dus'", true),
         ("name ENDSWITH[c] 'TIN'", true),
         ("name CONTAINS 'sti'", true),
         ("tags CONTAINS 'swift'", true),
         ("'objc' IN tags", true),
         ("'rust' in tags", false),
         ("size >= 50 AND size <= 50", true),
         ("size > 50 OR name == 'Dustin'", true),
         ("size > 50 || size < 10", false),
         ("NOT (size > 50)", true),
         ("!empty", true),
         ("missing == nil", true),
         ("tags.@count == 2 && size => 10", true),
         ("'café' ==[cd] 'CAFE'", true),
      ]
      for (condition, expected) in cases {
         let output = try render("{% if(\(condition)) %}yes{% else %}no{% endif %}", context)
         #expect(output == (expected ? "yes" : "no"), "\(condition)")
      }
   }

   @Test func truthiness() throws {
      let source = "{% if(v) %}t{% else %}f{% endif %}"
      #expect(try render(source, ["v": 0]) == "f")
      #expect(try render(source, ["v": 2]) == "t")
      #expect(try render(source, ["v": ""]) == "f")
      #expect(try render(source, ["v": "x"]) == "t")
      #expect(try render(source, ["v": []]) == "f")
      #expect(try render(source) == "f")
   }
}

@Suite struct LoopTests {
   @Test func forEachWithIndex() throws {
      let source = "{% foreach(friend in friends) %}{% friendIndex + 1 %}.{% friend %} {% endforeach %}"
      #expect(try render(source, ["friends": ["Jill", "Bob"]]) == "1.Jill 2.Bob ")
   }

   @Test func inlineArrays() throws {
      #expect(try render("{% foreach(n in {\"Dustin\", \"Mary Ann\"}) %}[{% n %}]{% endforeach %}") == "[Dustin][Mary Ann]")
      #expect(try render("{% foreach(n in [1, 2, 3]) %}{% n * 10 %} {% endforeach %}") == "10 20 30 ")
   }

   @Test func keyPathSequences() throws {
      let context: TemplateValue = ["files": [["name": "A.TXT"], ["name": "B.JPG"]]]
      let piped = "{% foreach(filename in files.name | lowercased) %}{% filename %};{% endforeach %}"
      #expect(try render(piped, context) == "a.txt;b.jpg;")
   }

   @Test func nestedLoopsSeeOuterVariables() throws {
      let context: TemplateValue = ["groups": [["name": "a", "items": [1, 2]], ["name": "b", "items": [3]]]]
      let source = "{% foreach(group in groups) %}{% foreach(item in group.items) %}{% group.name %}{% groupIndex %}:{% item %}/{% itemIndex %} {% endforeach %}{% endforeach %}"
      #expect(try render(source, context) == "a0:1/0 a0:2/1 b1:3/0 ")
   }

   @Test func loopVariablesShadowAndRestore() throws {
      let context: TemplateValue = ["x": "root", "list": [1, 2]]
      let source = "{% x %}|{% foreach(x in list) %}{% x %}{% endforeach %}|{% x %}"
      #expect(try render(source, context) == "root|12|root")
   }

   @Test func siblingLoopsReuseSlots() throws {
      let source = "{% foreach(a in {1, 2}) %}{% a %}{% endforeach %}-{% foreach(b in {3, 4}) %}{% b %}{% aIndex %}{% endforeach %}"
      #expect(try render(source) == "12-34")
   }

   @Test func loopsInsideConditions() throws {
      let source = "{% if(list.@count > 0) %}{% foreach(i in list) %}{% if(i % 2 == 0) %}{% i %}{% endif %}{% endforeach %}{% else %}none{% endif %}"
      #expect(try render(source, ["list": [1, 2, 3, 4]]) == "24")
      #expect(try render(source, ["list": []]) == "none")
   }

   @Test func nonArraysRenderNothing() throws {
      #expect(try render("{% foreach(x in thing) %}{% x %}{% endforeach %}done", ["thing": "text"]) == "done")
   }
}

@Suite struct WhitespaceTests {
   @Test func controlTagsSwallowOneNewline() throws {
      let source = "a\n{% if(true) %}\nb\n{% endif %}\nc\n"
      #expect(try render(source) == "a\nb\nc\n")
   }

   @Test func onlyOneNewlineIsSwallowed() throws {
      #expect(try render("{% if(true) %}\n\nx{% endif %}") == "\nx")
   }

   @Test func crlfCountsAsOneNewline() throws {
      #expect(try render("{% if(true) %}\r\nx{% endif %}") == "x")
   }

   @Test func valueTagsKeepTheirNewline() throws {
      #expect(try render("{% name %}\n", ["name": "D"]) == "D\n")
   }

   @Test func exampleTemplate() throws {
      let source = """
      Hello {% firstName %} {% lastName %},

      Your have {% friends.@count %} friends:
      {% foreach(friend in friends) %}
        - {% friend %} ({% friendIndex+1 %} of {% friends.@count %})
      {% endforeach %}

      Escaped HTML: {% about | escaped %}
      URL Encoded: {% url | urlEncoded %}
      {% if(file.fileSize between {0, 100}) %}
      File size for {% file.name | escaped %} too small!
      {% else %}
      File name: {% file.name | escaped %}
      File size: {% file.fileSize | bytes %}
      {% endif %}

      """
      let context: TemplateValue = [
         "about": "My name is <b>Mike</b>",
         "file": ["fileSize": 2345234, "name": "my_picture.jpg"],
         "url": "http://facebook.com/example_asdf?blah[]=23234:234",
         "firstName": "Mike",
         "lastName": "Tacos",
         "friends": ["Jill Arnet", "Bob Blob", "Sam Bog"],
      ]
      let expected = """
      Hello Mike Tacos,

      Your have 3 friends:
        - Jill Arnet (1 of 3)
        - Bob Blob (2 of 3)
        - Sam Bog (3 of 3)

      Escaped HTML: My name is &lt;b&gt;Mike&lt;/b&gt;
      URL Encoded: http%3A%2F%2Ffacebook.com%2Fexample_asdf%3Fblah%5B%5D%3D23234%3A234
      File name: my_picture.jpg
      File size: 2.2 MB

      """
      #expect(try render(source, context) == expected)
   }
}

@Suite struct TextFunctionTests {
   @Test func byteSizes() throws {
      let source = "{% fileSize | bytes %}"
      let cases: [(String, String)] = [
         ("0", "Zero KB"),
         ("1", "1 byte"),
         ("51", "51 bytes"),
         ("2300", "2 KB"),
         ("2034421", "1.9 MB"),
         ("9824958720", "9.15 GB"),
         ("89823871822003", "81.69 TB"),
      ]
      for (size, expected) in cases {
         #expect(try render(source, ["fileSize": .string(size)]) == expected)
      }
      #expect(try render(source, ["fileSize": 2034421]) == "1.9 MB")
   }

   @Test func urlEncoding() throws {
      #expect(try render("{% name | urlEncoded %}", ["name": "Düstinø Mîeråü"]) == "D%C3%BCstin%C3%B8%20M%C3%AEer%C3%A5%C3%BC")
      #expect(try render("{% q | urlEncoded %}", ["q": "a&b=c/d"]) == "a%26b%3Dc%2Fd")
   }

   @Test func xmlEscaping() throws {
      #expect(try render("{% xml | escaped %}", ["xml": "<this>is some & \"xml\"</this>"]) == "&lt;this&gt;is some &amp; &quot;xml&quot;&lt;/this&gt;")
      #expect(try render("{% s | escaped %}", ["s": "it's\ta\n"]) == "it&apos;s&#x09;a&#x0A;")
   }

   @Test func textFunctionsRunInOrder() throws {
      var options = TemplateOptions()
      options.functions["quoted"] = Functions.text { "\"\($0)\"" }
      let context: TemplateValue = ["name": "  \nDustin "]
      #expect(try render("{% name | trimmed | reversed | quoted %}", context, options: options) == "\"nitsuD\"")
      #expect(try render("{% name | quoted | trimmed %}", context, options: options) == "\"  \nDustin \"")
   }

   @Test func textFunctionsMapOverLists() throws {
      var options = TemplateOptions()
      options.functions["shout"] = Functions.text { $0.uppercased() + "!" }
      #expect(try render("{% names | shout | joined(' ') %}", ["names": ["a", "b"]], options: options) == "A! B!")
      #expect(try render("[{% missing | shout %}]", options: options) == "[]")
   }

   @Test func missingValuesStayMissing() throws {
      #expect(try render("[{% missing | escaped %}]") == "[]")
   }
}

@Suite struct LogTests {
   final class Collector: @unchecked Sendable {
      private let lock = NSLock()
      private var storage: [String] = []

      func append(_ message: String) {
         lock.lock()
         storage.append(message)
         lock.unlock()
      }

      var messages: [String] {
         lock.lock()
         defer { lock.unlock() }
         return storage
      }
   }

   @Test func logWritesToHandlerAndNotOutput() throws {
      let collector = Collector()
      var options = TemplateOptions()
      options.log = { collector.append($0) }
      let output = try render("a\n{% log(\"hello\") %}\n{% log(person.name) %}\n{% log(missing) %}\nb", ["person": ["name": "Dustin"]], options: options)
      #expect(output == "a\nb")
      #expect(collector.messages == ["hello", "Dustin", "nil"])
   }

   @Test func logInSkippedBranchDoesNothing() throws {
      let collector = Collector()
      var options = TemplateOptions()
      options.log = { collector.append($0) }
      _ = try render("{% if(false) %}{% log('no') %}{% endif %}", options: options)
      #expect(collector.messages.isEmpty)
   }
}

@Suite struct ErrorTests {
   func error(_ source: String) -> TemplateError? {
      do {
         _ = try Template(source)
         return nil
      }
      catch let error as TemplateError {
         return error
      }
      catch {
         return nil
      }
   }

   @Test func unclosedBlocks() {
      #expect(error("{% if(x) %}a")?.message == "if is never closed")
      #expect(error("{% foreach(x in y) %}a")?.message == "foreach is never closed")
   }

   @Test func mismatchedClosers() {
      #expect(error("{% endif %}")?.message == "endif without a matching if")
      #expect(error("{% if(a) %}{% endforeach %}")?.message == "endforeach without a matching foreach")
      #expect(error("{% else %}")?.message == "else without a matching if")
      #expect(error("{% if(a) %}{% else %}{% elseif(b) %}{% endif %}")?.message == "elseif after else")
   }

   @Test func unterminatedTag() {
      #expect(error("hello {% name")?.message == "Tag is missing its closing %}")
   }

   @Test func unknownFormat() throws {
      let problem = try #require(error("one\n{% when | month %}"))
      #expect(problem.line == 2)
      #expect(problem.column == 11)
      #expect(problem.message.hasPrefix("Unknown function month()"))
   }

   @Test func oldModifierAndFormatSyntaxPointToPipes() throws {
      #expect(error("{%[e] name %}") != nil)
      #expect(try #require(error("{% when as date %}")).message.hasPrefix("Format with a pipe"))
   }

   @Test func badExpressionsReportPosition() throws {
      let problem = try #require(error("line one\nsecond {% a + %}"))
      #expect(problem.line == 2)
      #expect(problem.column == 14)
      #expect(problem.message.hasPrefix("Expected an expression") || problem.message.hasPrefix("Unexpected"))
   }

   @Test func unsupportedSyntaxFailsAtParse() {
      #expect(error("{% if(name LIKE 'D*') %}{% endif %}") != nil)
      #expect(error("{% $var %}") != nil)
      #expect(error("{% people.@distinctUnionOfObjects.name %}") != nil)
   }

   @Test func malformedForEach() {
      #expect(error("{% foreach(people) %}{% endforeach %}") != nil)
   }
}

@Suite struct FunctionTests {
   let context: TemplateValue = ["person": ["firstName": "Dustin"]]

   @Test func functionsRunInEveryRender() throws {
      let template = try Template("[{% person.firstName | uppercased %}]")
      #expect(template.render(context) == "[DUSTIN]")
      #expect(template.render(context, features: []) == "[DUSTIN]")
   }

   @Test func methodPipeAndCallSpellingsAgree() throws {
      let spellings = [
         "{% person.firstName.prefix(3).uppercased() %}",
         "{% person.firstName | prefix(3) | uppercased %}",
         "{% person.firstName | prefix(3) | uppercased() %}",
         "{% uppercased(prefix(person.firstName, 3)) %}",
      ]
      for source in spellings {
         #expect(try Template(source).render(context) == "DUS", "\(source)")
      }
   }

   @Test func pipesBindTighterThanOperators() throws {
      #expect(try Template("{% if(person.firstName | lowercased == 'dustin') %}yes{% endif %}").render(context) == "yes")
      var options = TemplateOptions()
      options.functions["double"] = { receiver, _ in .int((Int(receiver.renderedString) ?? 0) * 2) }
      #expect(try Template("{% 1 + 2 | double %}", options: options).render([:]) == "5")
      #expect(try Template("{% (1 + 2) | double %}", options: options).render([:]) == "6")
   }

   @Test func pathsContinueAfterCalls() throws {
      let template = try Template("{% people.reversed()[0].name %} {% people.name | reversed | joined(', ') %}")
      #expect(template.render(["people": [["name": "Ann"], ["name": "Ollie"]]]) == "Ollie Ollie, Ann")
   }

   @Test func standardFunctions() throws {
      let context: TemplateValue = ["name": "  Dustin Mierau ", "files": ["A.TXT", "B.jpg"], "empty": "", "id": "u-1"]
      func render(_ expression: String) throws -> String {
         try Template("{% \(expression) %}").render(context)
      }
      #expect(try render("name | trimmed") == "Dustin Mierau")
      #expect(try render("name | trimmed | lowercased | capitalized") == "Dustin Mierau")
      #expect(try render("name | trimmed | suffix(6)") == "Mierau")
      #expect(try render("name | trimmed | dropFirst") == "ustin Mierau")
      #expect(try render("name | trimmed | dropLast(7)") == "Dustin")
      #expect(try render("name | trimmed | replacing(' ', '-')") == "Dustin-Mierau")
      #expect(try render("name | trimmed | reversed") == "uareiM nitsuD")
      #expect(try render("files | lowercased | joined(', ')") == "a.txt, b.jpg")
      #expect(try render("path('/avatars', id, 'photo.jpg')") == "/avatars/u-1/photo.jpg")
      #expect(try render("path('~', files)") == "~/A.TXT/B.jpg")
      #expect(try render("empty | default('none')") == "none")
      #expect(try render("missing | default('none')") == "none")
      #expect(try render("id | default('none')") == "u-1")
   }

   @Test func unknownCallsFailAtParse() {
      #expect(throws: TemplateError.self) { try Template("{% name | shout %}") }
      #expect(throws: TemplateError.self) { try Template("{% name.shout() %}") }
      #expect(throws: TemplateError.self) { try Template("{% shout(name) %}") }
      #expect(throws: TemplateError.self) { try Template("{% name | 'x' %}") }
   }

   @Test func anyNameCanBeAFunction() throws {
      var options = TemplateOptions()
      options.functions["function"] = { receiver, _ in .string("f(\(receiver.renderedString))") }
      options.functions["all"] = { receiver, _ in .string("all \(receiver.renderedString)") }
      let template = try Template("{% function(x) %} {% x | function %} {% x.function() %} {% all(x) %}", options: options)
      #expect(template.render(["x": "a"]) == "f(a) f(a) f(a) all a")
   }

   @Test func keysNamedLikeFunctionsAreStillKeys() throws {
      let template = try Template("{% item.prefix %} {% item.prefix | uppercased %}")
      #expect(template.render(["item": ["prefix": "mr"]]) == "mr MR")
   }

   @Test func functionsWorkInConditionsAndLoops() throws {
      let template = try Template("{% foreach(n in names) %}{% if(n.@count > 3) %}{% n | lowercased %} {% endif %}{% endforeach %}")
      #expect(template.render(["names": ["Ann", "DUSTIN", "Ollie"]], ) == "dustin ollie ")
   }

   @Test func customFunctions() throws {
      var options = TemplateOptions()
      options.functions["repeat"] = { receiver, arguments in
         guard case .int(let count)? = arguments.first else { return .null }
         return .string(String(repeating: receiver.renderedString, count: count))
      }
      let template = try Template("{% x.repeat(3) %}", options: options)
      #expect(template.render(["x": "ab"], ) == "ababab")
   }

   @Test func unknownFunctionsFailAtParse() {
      #expect(throws: TemplateError.self) { try Template("{% x | deleteEverything %}") }
      #expect(throws: TemplateError.self) { try Template("{% FUNCTION(x, 'uppercased') %}") }
      var options = TemplateOptions()
      options.functions = Functions()
      #expect(throws: TemplateError.self) { try Template("{% x | uppercased %}", options: options) }
   }

   @Test func logCanBeTurnedOff() throws {
      let collector = LogTests.Collector()
      var options = TemplateOptions()
      options.log = { collector.append($0) }
      let template = try Template("{% log('a') %}x", options: options)
      #expect(template.render(nil, features: []) == "x")
      #expect(collector.messages.isEmpty)
      _ = template.render(nil)
      #expect(collector.messages == ["a"])
   }
}

@Suite struct InputTests {
   struct Person: Encodable {
      let name: String
      let age: Int
   }

   @Test func encodableContext() throws {
      let template = try Template("{% foreach(p in people) %}{% p.name %}:{% p.age %} {% endforeach %}")
      struct Context: Encodable { let people: [Person] }
      let output = try template.render(encoding: Context(people: [Person(name: "A", age: 1), Person(name: "B", age: 2)]))
      #expect(output == "A:1 B:2 ")
   }

   @Test func foundationContext() throws {
      let template = try Template("{% name %} {% count + 1 %} {% flag %} {% items.@count %} {% ratio %}")
      let object: [String: Any] = [
         "name": NSString(string: "Dustin"),
         "count": NSNumber(value: 41),
         "flag": NSNumber(value: true),
         "items": NSArray(array: [1, 2, 3]),
         "ratio": NSNumber(value: 1.5),
      ]
      #expect(template.render(object: object) == "Dustin 42 true 3 1.5")
   }

   @Test func encodableMatchesJSON() throws {
      enum Shape: Codable { case circle(radius: Double), square(side: Int) }
      enum Kind: String, Codable { case small, large }
      struct Item: Codable {
         let name: String
         let nickname: String?
         let tiny: Int8
         let huge: UInt64
         let ratio: Float
         let kind: Kind
         let shapes: [Shape]
         let scores: [Int: String]
         let tags: Set<String>
         let link: URL
         let blob: Data
      }
      let item = Item(name: "A", nickname: nil, tiny: -3, huge: .max, ratio: 0.1, kind: .large,
                      shapes: [.circle(radius: 1.5), .square(side: 2)], scores: [1: "one"], tags: ["x"],
                      link: URL(string: "https://example.com/a?b=c")!, blob: Data([1, 2, 3]))
      let viaJSON = try JSONDecoder().decode(TemplateValue.self, from: JSONEncoder().encode(item))
      #expect(try TemplateValue(encoding: item) == viaJSON)
   }

   @Test func encodableClassWithSuperclass() throws {
      class Animal: Encodable {
         let name = "Rex"
      }
      final class Dog: Animal {
         let tricks = ["sit"]
         private enum Keys: String, CodingKey { case tricks }
         override func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(tricks, forKey: .tricks)
            try super.encode(to: container.superEncoder())
         }
      }
      let template = try Template("{% super.name %} {% tricks[0] %}")
      #expect(try template.render(encoding: Dog()) == "Rex sit")
   }

   @Test func datesStayDates() throws {
      struct Post: Encodable { let date: Date }
      let date = Date(timeIntervalSince1970: 1_760_000_000)
      #expect(try TemplateValue(encoding: Post(date: date)) == ["date": .date(date)])
      #expect(TemplateValue(any: ["date": date] as [String: Any]) == ["date": .date(date)])
      #expect(try Template("{% date %}").render(["date": .date(date)]) == "2025-10-09T08:53:20Z")
   }

   @Test func decodingKeepsTypes() throws {
      let json = #"{"s": "x", "i": 3, "d": 1.5, "b": true, "n": null, "a": [1, "y"], "o": {"k": false}}"#
      let value = try JSONDecoder().decode(TemplateValue.self, from: Data(json.utf8))
      #expect(value == ["s": "x", "i": 3, "d": 1.5, "b": true, "n": nil, "a": [1, "y"], "o": ["k": false]])
   }

   @Test func foundationValuesKeepTypes() {
      let object: [String: Any] = ["b": true, "i": 3, "d": 1.5, "n": NSNull(), "u": UInt8(7), "s": Substring("sub")]
      #expect(TemplateValue(any: object) == ["b": true, "i": 3, "d": 1.5, "n": nil, "u": 7, "s": "sub"])
   }

   @Test func propertyListContext() throws {
      let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0"><dict>
      <key>size</key><integer>2345234</integer>
      <key>names</key><array><string>a</string><string>b</string></array>
      </dict></plist>
      """
      let object = try PropertyListSerialization.propertyList(from: Data(plist.utf8), format: nil)
      let template = try Template("{% size | bytes %} {% names.@count %}")
      #expect(template.render(object: object) == "2.2 MB 2")
   }
}

@Suite struct ExpressionSeamTests {
   /// Treats every expression as a literal string, to show any compiler can
   /// stand in for the built-in one.
   struct EchoCompiler: ExpressionCompiler {
      struct Echo: CompiledExpression {
         let text: String
         func evaluate(in scope: ExpressionScope) -> TemplateValue { .string(text.uppercased()) }
      }

      func compile(_ source: String, locals: [String]) throws -> any CompiledExpression {
         Echo(text: source)
      }
   }

   /// Resolves the source as a single name, using the locals slot when it is a
   /// loop variable.
   struct NameCompiler: ExpressionCompiler {
      struct Name: CompiledExpression {
         let slot: Int?
         let name: String
         func evaluate(in scope: ExpressionScope) -> TemplateValue {
            if let slot { return scope.local(slot) }
            if case .dictionary(let root) = scope.root { return root[name] ?? .null }
            return .null
         }
      }

      func compile(_ source: String, locals: [String]) throws -> any CompiledExpression {
         Name(slot: locals.lastIndex(of: source), name: source)
      }
   }

   /// Wraps the built-in compiler, as an adapter that pre-processes or audits
   /// expressions would.
   struct WrappingCompiler: ExpressionCompiler {
      func compile(_ source: String, locals: [String]) throws -> any CompiledExpression {
         try NativeExpressionCompiler().compile(source, locals: locals)
      }
   }

   @Test func wrappedNativeCompiler() throws {
      var options = TemplateOptions()
      options.expressionCompiler = WrappingCompiler()
      let source = "{% foreach(p in people) %}{% if(p.age > 40) %}{% p.name %}{% endif %}{% endforeach %}"
      #expect(try render(source, ["people": [["name": "A", "age": 50], ["name": "B", "age": 20]]], options: options) == "A")
   }

   @Test func nativeExpressionEvaluatesStandalone() throws {
      let expression = try NativeExpressionCompiler().compile("people.@sum.age * 2 + x", locals: ["x"])
      var scope = ExpressionScope(root: ["people": [["age": 1], ["age": 2]]], features: .default, localCount: 1)
      scope.locals[0] = 10
      #expect(expression.evaluate(in: scope) == 16)
   }

   @Test func customCompiler() throws {
      var options = TemplateOptions()
      options.expressionCompiler = EchoCompiler()
      #expect(try render("{% hello world %}", options: options) == "HELLO WORLD")
   }

   @Test func customCompilerSeesLoopSlots() throws {
      var options = TemplateOptions()
      options.expressionCompiler = NameCompiler()
      #expect(try render("{% foreach(x in list) %}{% x %}{% xIndex %},{% endforeach %}", ["list": ["a", "b"]], options: options) == "a0,b1,")
   }
}

@Suite struct ConcurrencyTests {
   @Test func oneTemplateRendersConcurrently() async throws {
      let template = try Template("{% foreach(p in people) %}{% if(p.age >= 40) %}{% p.name | escaped %}{% else %}-{% endif %}{% endforeach %}={% people.@sum.age %}")

      let results = await withTaskGroup(of: (Int, String).self) { group in
         for i in 0..<64 {
            group.addTask {
               let people: [TemplateValue] = (0..<20).map { ["name": .string("<\(i)-\($0)>"), "age": .int(30 + $0)] }
               return (i, template.render(["people": .array(people)]))
            }
         }
         var results: [Int: String] = [:]
         for await (i, output) in group {
            results[i] = output
         }
         return results
      }

      #expect(results.count == 64)
      for (i, output) in results {
         let names = (10..<20).map { "&lt;\(i)-\($0)&gt;" }.joined()
         let expected = String(repeating: "-", count: 10) + names + "=790"
         #expect(output == expected)
      }
   }
}

@Suite struct ReadmeTests {
   @Test func customFunctions() throws {
      var options = TemplateOptions()
      options.functions["initials"] = { receiver, _ in
         .string(receiver.renderedString.split(separator: " ").compactMap(\.first).map(String.init).joined())
      }
      options.functions["shout"] = Functions.text { $0.uppercased() + "!" }
      let template = try Template("{% firstName | trimmed | escaped %}|{% name | initials %}|{% name | shout %}", options: options)
      let context: TemplateValue = ["firstName": "  Tom & Jerry ", "name": "Dustin Mierau"]
      #expect(template.render(context) == "Tom &amp; Jerry|DM|DUSTIN MIERAU!")
   }

   @Test func naturalFunctionExamples() throws {
      let template = try Template("""
         {% person.firstName.prefix(5).uppercased() %} \
         {% person.firstName | prefix(5) | uppercased %} \
         {% path("~", "dustin", "photo.jpg") %}
         """)
      let context: TemplateValue = ["person": ["firstName": "Dustin"]]
      #expect(template.render(context) == "DUSTI DUSTI ~/dustin/photo.jpg")
   }

   @Test func formatPatterns() throws {
      var options = TemplateOptions()
      options.locale = Locale(identifier: "en_US")
      options.timeZone = TimeZone(identifier: "UTC")!
      let template = try Template("{% post.date | format(\"EEEE, MMMM d\") %} {% item.weight | format(\"0.0\") %} kg", options: options)
      #expect(template.render(["post": ["date": "2025-10-09"], "item": ["weight": 2.5]]) == "Thursday, October 9 2.5 kg")
   }

   @Test func loopIndex() throws {
      let template = try Template("{% foreach(contact in contacts) %}{% contactIndex + 1 %}:{% contact %} {% endforeach %}")
      #expect(template.render(["contacts": ["a", "b"]]) == "1:a 2:b ")
   }
}

@Suite struct FormatTests {
   /// 2025-10-09 08:53:20 UTC, which is 1:53 AM in Los Angeles.
   let moment = Date(timeIntervalSince1970: 1_760_000_000)

   var options: TemplateOptions {
      var options = TemplateOptions()
      options.locale = Locale(identifier: "en_US")
      options.timeZone = TimeZone(identifier: "America/Los_Angeles")!
      return options
   }

   @Test func datesRenderAsISO8601ByDefault() throws {
      #expect(try render("{% when %}", ["when": .date(moment)]) == "2025-10-09T08:53:20Z")
   }

   @Test func dateStyles() throws {
      let locale = options.locale
      let zone = options.timeZone
      let cases: [(String, String)] = [
         ("date", moment.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: zone))),
         ("time", moment.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: zone))),
         ("dateTime", moment.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: zone))),
         ("iso8601", "2025-10-09T08:53:20Z"),
      ]
      for (style, expected) in cases {
         #expect(try render("{% when | \(style) %}", ["when": .date(moment)], options: options) == expected)
      }
      #expect(try render("{% when | date %}", ["when": .date(moment)], options: options) == "Oct 9, 2025")
   }

   @Test func relativeDates() throws {
      let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
      #expect(try render("{% when | relative %}", ["when": .date(twoDaysAgo)], options: options) == "2 days ago")
   }

   @Test func datePatterns() throws {
      let context: TemplateValue = ["when": .date(moment)]
      #expect(try render("{% when | format(\"yyyy-MM-dd\") %}", context, options: options) == "2025-10-09")
      #expect(try render("{% when | format(\"MMM d, yyyy 'at' h:mm a\") %}", context, options: options) == "Oct 9, 2025 at 1:53 AM")
      #expect(try render("{% when | format('EEEE') %}", context, options: options) == "Thursday")
   }

   @Test func datesFromStringsAndNumbers() throws {
      let context: TemplateValue = [
         "stamp": "2025-10-09T08:53:20Z",
         "fraction": "2025-10-09T08:53:20.250Z",
         "offset": "2025-10-09T10:53:20+02:00",
         "day": "2025-10-09",
         "seconds": 1_760_000_000,
      ]
      let template = try Template("{% stamp | format(\"HH:mm\") %} {% fraction | format(\"HH:mm\") %} {% offset | format(\"HH:mm\") %} {% day | format(\"MMM d\") %} {% seconds | format(\"HH:mm\") %}", options: options)
      #expect(template.render(context) == "01:53 01:53 01:53 Oct 9 01:53")
   }

   @Test func numberStyles() throws {
      let context: TemplateValue = ["big": 1234567.891, "share": 0.256, "price": 1234.5, "count": 1200, "text": "42.5"]
      #expect(try render("{% big | number %}|{% share | percent %}|{% price | currency %}|{% count | number %}|{% text | number %}", context, options: options)
         == "1,234,567.891|25.6%|$1,234.50|1,200|42.5")

      var euros = options
      euros.currencyCode = "EUR"
      #expect(try render("{% price | currency %}", context, options: euros) == "€1,234.50")
   }

   @Test func numberPatterns() throws {
      let context: TemplateValue = ["price": 1234.5, "count": 3, "loss": -2.5]
      #expect(try render("{% price | format(\"#,##0.00\") %} {% count | format(\"0.0\") %} {% loss | format(\"0.00\") %}", context, options: options) == "1,234.50 3.0 -2.50")
   }

   @Test func valuesAFormatDoesNotFitRenderAsUsual() throws {
      #expect(try render("[{% name | date %}] [{% name | number %}] [{% missing | date %}]", ["name": "Dustin"], options: options) == "[Dustin] [Dustin] []")
   }

   @Test func formatsChainWithOtherFunctions() throws {
      let context: TemplateValue = ["when": .date(moment), "dates": [.date(moment)]]
      #expect(try render("{% dates | date | joined %}", context, options: options) == "Oct 9, 2025")
      #expect(try render("{% when | format(\"yyyy-MM-dd HH:mm\") | urlEncoded %}", context, options: options) == "2025-10-09%2001%3A53")
   }

   @Test func appFunctionsReplaceFormats() throws {
      var custom = options
      custom.functions["date"] = Functions.text { "custom \($0)" }
      #expect(try render("{% x | date %}", ["x": "a"], options: custom) == "custom a")
   }

   @Test func asInsideStringsIsText() throws {
      #expect(try render(#"{% "this as that" %}"#) == "this as that")
   }

   @Test func datesCompareAndAggregate() throws {
      let earlier = moment.addingTimeInterval(-60)
      let context: TemplateValue = ["a": .date(earlier), "b": .date(moment), "posts": [["date": .date(earlier)], ["date": .date(moment)]]]
      #expect(try render("{% if(a < b) %}before{% endif %} {% posts.@max.date | format(\"HH:mm\") %}", context, options: options) == "before 01:53")
   }

   @Test func formattingFromManyThreads() async throws {
      let template = try Template("{% when | format(\"yyyy-MM-dd HH:mm\") %} {% price | format(\"#,##0.00\") %}", options: options)
      let context: TemplateValue = ["when": .date(moment), "price": 1234.5]
      let outputs = await withTaskGroup(of: Set<String>.self) { group in
         for _ in 0..<8 {
            group.addTask { Set((0..<200).map { _ in template.render(context) }) }
         }
         return await group.reduce(into: Set<String>()) { $0.formUnion($1) }
      }
      #expect(outputs == ["2025-10-09 01:53 1,234.50"])
   }
}

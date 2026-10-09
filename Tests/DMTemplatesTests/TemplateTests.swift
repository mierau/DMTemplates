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
      #expect(try render("{% people.first.uppercaseString %}", context) == "DUSTIN, GARRY")
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

   @Test func stringProperties() throws {
      #expect(try render("{% firstName.length %} {% firstName.lowercaseString %}", context) == "6 dustin")
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
      let source = "{% foreach(filename in files.name.lowercaseString) %}{% filename %};{% endforeach %}"
      #expect(try render(source, context) == "a.txt;b.jpg;")
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

      Escaped HTML: {%[e] about %}
      URL Encoded: {%[u] url %}
      {% if(file.fileSize between {0, 100}) %}
      File size for {%[e] file.name %} too small!
      {% else %}
      File name: {%[e] file.name %}
      File size: {%[b] file.fileSize %}
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

@Suite struct ModifierTests {
   @Test func byteSizes() throws {
      let source = "{%[  b ] fileSize %}"
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
      #expect(try render("{%[u] name %}", ["name": "Düstinø Mîeråü"]) == "D%C3%BCstin%C3%B8%20M%C3%AEer%C3%A5%C3%BC")
      #expect(try render("{%[u] q %}", ["q": "a&b=c/d"]) == "a%26b%3Dc%2Fd")
   }

   @Test func xmlEscaping() throws {
      #expect(try render("{%[e] xml %}", ["xml": "<this>is some & \"xml\"</this>"]) == "&lt;this&gt;is some &amp; &quot;xml&quot;&lt;/this&gt;")
      #expect(try render("{%[e] s %}", ["s": "it's\ta\n"]) == "it&apos;s&#x09;a&#x0A;")
   }

   @Test func customModifiersRunInOrder() throws {
      var options = TemplateOptions()
      options.modifiers = Modifiers()
      options.modifiers["w"] = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      options.modifiers["r"] = { String($0.reversed()) }
      options.modifiers["q"] = { "\"\($0)\"" }
      let context: TemplateValue = ["name": "  \nDustin "]
      #expect(try render("{%[wrq] name %}", context, options: options) == "\"nitsuD\"")
      #expect(try render("{%[qw] name %}", context, options: options) == "\"  \nDustin \"")
   }

   @Test func modifierLookupIgnoresCase() throws {
      #expect(try render("{%[E] x %}", ["x": "<"]) == "&lt;")
   }

   @Test func modifiersSkipMissingValues() throws {
      #expect(try render("[{%[e] missing %}]") == "[]")
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

   @Test func unknownModifier() {
      #expect(error("{%[z] name %}")?.message == "Unknown modifier 'z'")
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

   @Test func functionsAreOffByDefault() throws {
      let template = try Template("[{% FUNCTION(person.firstName, 'uppercaseString') %}]")
      #expect(template.render(context) == "[]")
      #expect(template.render(context, features: [.functions]) == "[DUSTIN]")
   }

   @Test func readmeExamples() throws {
      let features: RenderFeatures = [.functions]
      #expect(try Template("{% function(person.firstName, \"substringToIndex:\", 5) %}").render(context, features: features) == "Dusti")
      #expect(try Template("{% function(function(person.firstName, \"substringToIndex:\", 5), \"uppercaseString\") %}").render(context, features: features) == "DUSTI")
      #expect(try Template("{% function(\"\".class, \"pathWithComponents:\", {\"~\", \"dustin\", \"photo.jpg\"}) %}").render(context, features: features) == "~/dustin/photo.jpg")
   }

   @Test func functionsWorkInConditionsAndLoops() throws {
      let template = try Template("{% foreach(n in names) %}{% if(FUNCTION(n, 'length') > 3) %}{% FUNCTION(n, 'lowercaseString') %} {% endif %}{% endforeach %}")
      #expect(template.render(["names": ["Ann", "DUSTIN", "Ollie"]], features: .functions) == "dustin ollie ")
   }

   @Test func customFunctions() throws {
      var options = TemplateOptions()
      options.functions["repeat"] = { receiver, arguments in
         guard case .int(let count)? = arguments.first else { return .null }
         return .string(String(repeating: receiver.renderedString, count: count))
      }
      let template = try Template("{% FUNCTION(x, 'repeat', 3) %}", options: options)
      #expect(template.render(["x": "ab"], features: .functions) == "ababab")
   }

   @Test func unknownFunctionsFailAtParse() {
      #expect(throws: TemplateError.self) { try Template("{% FUNCTION(x, 'deleteEverything') %}") }
      var options = TemplateOptions()
      options.functions = Functions()
      #expect(throws: TemplateError.self) { try Template("{% FUNCTION(x, 'uppercaseString') %}", options: options) }
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
      let template = try Template("{%[b] size %} {% names.@count %}")
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
      let template = try Template("{% foreach(p in people) %}{% if(p.age >= 40) %}{%[e] p.name %}{% else %}-{% endif %}{% endforeach %}={% people.@sum.age %}")

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
   @Test func customModifierAndFunction() throws {
      var options = TemplateOptions()
      options.modifiers["w"] = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      options.functions["reversed"] = { receiver, _ in
         .string(String(receiver.renderedString.reversed()))
      }
      let template = try Template("{%[we] firstName %}|{% FUNCTION(name, \"reversed\") %}", options: options)
      let context: TemplateValue = ["firstName": "  Tom & Jerry ", "name": "abc"]
      #expect(template.render(context, features: [.functions]) == "Tom &amp; Jerry|cba")
   }

   @Test func functionExamples() throws {
      let template = try Template("""
         {% FUNCTION(FUNCTION(person.firstName, "substringToIndex:", 5), "uppercaseString") %} \
         {% FUNCTION(nil, "pathWithComponents:", {"~", "dustin", "photo.jpg"}) %}
         """)
      let context: TemplateValue = ["person": ["firstName": "Dustin"]]
      #expect(template.render(context, features: [.functions]) == "DUSTI ~/dustin/photo.jpg")
      #expect(template.render(context) == " ")
   }

   @Test func loopIndex() throws {
      let template = try Template("{% foreach(contact in contacts) %}{% contactIndex + 1 %}:{% contact %} {% endforeach %}")
      #expect(template.render(["contacts": ["a", "b"]]) == "1:a 2:b ")
   }
}

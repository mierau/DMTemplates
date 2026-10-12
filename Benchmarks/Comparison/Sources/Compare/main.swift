// StringCheese
// Dustin Mierau
// Cared for under the MIT license.
//
// Usage: Compare <fixtures directory> <output directory> [seconds per measurement]
// Renders the same page, Fixtures/people.json through the people template
// written for each engine, with StringCheese, Stencil, Mustache and Leaf, and
// prints a Markdown table of microseconds per render. Every engine escapes
// HTML, and each output is checked against StringCheese's, ignoring
// whitespace, before it's measured.

import Foundation
import StringCheese
import Stencil
import Mustache
import LeafKit
import NIOCore
import NIOEmbedded

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
   print("usage: Compare <fixtures directory> <output directory> [seconds]")
   exit(1)
}
let fixtures = URL(fileURLWithPath: arguments[1])
let outputs = URL(fileURLWithPath: arguments[2])
let seconds = arguments.count > 3 ? Double(arguments[3]) ?? 1 : 1

/// Runs `body` repeatedly for about `seconds` and returns microseconds per call.
func measure(_ body: () throws -> Int) rethrows -> Double {
   var sink = 0
   for _ in 0..<10 { sink &+= try body() }

   let clock = ContinuousClock()
   let budget = Duration.milliseconds(Int(seconds * 1000))
   var iterations = 0
   let start = clock.now
   var elapsed = Duration.zero
   while elapsed < budget {
      for _ in 0..<10 { sink &+= try body() }
      iterations += 10
      elapsed = clock.now - start
   }
   if sink == 42 { print("") }
   let (s, attoseconds) = elapsed.components
   let total = Double(s) + Double(attoseconds) / 1e18
   return total / Double(iterations) * 1e6
}

func source(_ name: String) throws -> String {
   try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
}

// MARK: Context

struct Person: Decodable {
   let name: String
   let city: String
   let admin: Bool
}
struct Page: Decodable {
   let title: String
   let people: [Person]
}

let json = try Data(contentsOf: fixtures.appendingPathComponent("people.json"))
let page = try JSONDecoder().decode(Page.self, from: json)

// Stencil, Mustache and StringCheese's render(object:) take the same
// dictionary of Swift values. StringCheese's render(_:) and Leaf take their
// own value types, converted once up front.
let dictionary: [String: Any] = [
   "title": page.title,
   "people": page.people.map { ["name": $0.name, "city": $0.city, "admin": $0.admin] as [String: Any] },
]
let templateValue = try JSONDecoder().decode(TemplateValue.self, from: json)
let leafContext: [String: LeafData] = [
   "title": .string(page.title),
   "people": .array(page.people.map { .dictionary(["name": .string($0.name), "city": .string($0.city), "admin": .bool($0.admin)]) }),
]

// MARK: Engines

struct Engine {
   let name: String
   /// Renders a template parsed once, ahead of time.
   let render: () throws -> String
   /// Parses the template and renders it.
   let parseAndRender: () throws -> String
}

var cheeseOptions = TemplateOptions()
cheeseOptions.escaping = .html
let cheeseSource = try source("people.cheese")
let cheese = try StringCheese.Template(cheeseSource, options: cheeseOptions)

let stencilExtension = Extension()
stencilExtension.registerFilter("escape") { (value: Any?) in
   guard let value else { return nil }
   var escaped = ""
   for character in "\(value)" {
      switch character {
      case "&": escaped += "&amp;"
      case "<": escaped += "&lt;"
      case ">": escaped += "&gt;"
      case "\"": escaped += "&quot;"
      case "'": escaped += "&#39;"
      default: escaped.append(character)
      }
   }
   return escaped
}
let stencilEnvironment = Environment(extensions: [stencilExtension])
let stencilSource = try source("people.stencil")
let stencil = Stencil.Template(templateString: stencilSource, environment: stencilEnvironment)

let mustacheSource = try source("people.mustache")
let mustache = try MustacheTemplate(string: mustacheSource)

struct MemorySource: LeafSource {
   let files: [String: String]
   func file(template: String, escape: Bool, on eventLoop: any EventLoop) throws -> EventLoopFuture<ByteBuffer> {
      guard let file = files[template] else {
         return eventLoop.makeFailedFuture(LeafError(.noTemplateExists(template)))
      }
      return eventLoop.makeSucceededFuture(ByteBuffer(string: file))
   }
}
let leafLoop = EmbeddedEventLoop()
let leafSources = LeafSources.singleSource(MemorySource(files: ["people": try source("people.leaf")]))
let leafConfiguration = LeafConfiguration(rootDirectory: "/")
let leafCached = LeafRenderer(configuration: leafConfiguration, sources: leafSources, eventLoop: leafLoop)
let uncachedCache = DefaultLeafCache()
uncachedCache.isEnabled = false
let leafUncached = LeafRenderer(configuration: leafConfiguration, cache: uncachedCache, sources: leafSources, eventLoop: leafLoop)

/// Leaf renders through futures. On an embedded event loop with an in-memory
/// source they complete as the render returns.
func leafRender(_ renderer: LeafRenderer) throws -> String {
   let future = renderer.render(path: "people", context: leafContext)
   leafLoop.run()
   var buffer = try future.wait()
   return buffer.readString(length: buffer.readableBytes) ?? ""
}

let engines = [
   Engine(name: "StringCheese",
          render: { cheese.render(templateValue) },
          parseAndRender: { try StringCheese.Template(cheeseSource, options: cheeseOptions).render(templateValue) }),
   Engine(name: "StringCheese, render(object:)",
          render: { cheese.render(object: dictionary) },
          parseAndRender: { try StringCheese.Template(cheeseSource, options: cheeseOptions).render(object: dictionary) }),
   Engine(name: "Stencil",
          render: { try stencil.render(dictionary) },
          parseAndRender: { try Stencil.Template(templateString: stencilSource, environment: stencilEnvironment).render(dictionary) }),
   Engine(name: "Mustache",
          render: { mustache.render(dictionary) },
          parseAndRender: { try MustacheTemplate(string: mustacheSource).render(dictionary) }),
   Engine(name: "Leaf",
          render: { try leafRender(leafCached) },
          parseAndRender: { try leafRender(leafUncached) }),
]

// MARK: Run

func normalized(_ text: String) -> String {
   text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
let expected = normalized(cheese.render(templateValue))

var rows: [(name: String, render: Double, parseAndRender: Double)] = []
for engine in engines {
   let output = try engine.render()
   let file = engine.name.lowercased().filter { $0.isLetter } + ".html"
   try output.write(to: outputs.appendingPathComponent(file), atomically: true, encoding: .utf8)
   guard normalized(output) == expected, normalized(try engine.parseAndRender()) == expected else {
      FileHandle.standardError.write(Data("\(engine.name) rendered something different; see \(outputs.path)/\(file)\n".utf8))
      exit(1)
   }
   rows.append((engine.name, try measure { try engine.render().utf8.count }, try measure { try engine.parseAndRender().utf8.count }))
}

func microseconds(_ value: Double, relativeTo base: Double) -> String {
   String(format: "%.1f µs (%.1f×)", value, value / base)
}

print("| Engine | Render, parsed once | Parse and render |")
print("|---|--:|--:|")
for row in rows {
   print("| \(row.name) | \(microseconds(row.render, relativeTo: rows[0].render)) | \(microseconds(row.parseAndRender, relativeTo: rows[0].parseAndRender)) |")
}

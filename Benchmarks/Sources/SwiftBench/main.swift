// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.
//
// Usage: SwiftBench <fixtures directory> <output directory> [seconds per measurement]
// Measures each fixture (<name>.tmpl rendered against <name>.json) and writes
// one rendering per fixture to the output directory for comparison.

import DMTemplates
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
   print("usage: SwiftBench <fixtures directory> <output directory> [seconds]")
   exit(1)
}
let fixtures = URL(fileURLWithPath: arguments[1])
let outputs = URL(fileURLWithPath: arguments[2])
let seconds = arguments.count > 3 ? Double(arguments[3]) ?? 1 : 1

/// Runs `body` repeatedly for about `seconds` and returns microseconds per call.
func measure(_ body: () -> Int) -> (microseconds: Double, iterations: Int) {
   var sink = 0
   for _ in 0..<10 { sink &+= body() }
   
   let clock = ContinuousClock()
   let budget = Duration.milliseconds(Int(seconds * 1000))
   var iterations = 0
   let start = clock.now
   var elapsed = Duration.zero
   while elapsed < budget {
      for _ in 0..<10 { sink &+= body() }
      iterations += 10
      elapsed = clock.now - start
   }
   if sink == 42 { print("") }
   let (s, attoseconds) = elapsed.components
   let total = Double(s) + Double(attoseconds) / 1e18
   return (total / Double(iterations) * 1e6, iterations)
}

/// Renders from every core at once and returns microseconds of wall time per
/// render across all of them.
func measureConcurrent(_ template: Template, _ contextData: Data) async -> (microseconds: Double, tasks: Int) {
   let tasks = ProcessInfo.processInfo.activeProcessorCount
   let context = try! JSONDecoder().decode(TemplateValue.self, from: contextData)
   let perTask = max(10, measure { template.render(context).utf8.count }.iterations / 2)
   let clock = ContinuousClock()
   let start = clock.now
   await withTaskGroup(of: Int.self) { group in
      for _ in 0..<tasks {
         group.addTask {
            // Each task renders its own context, as a server would per request.
            let context = try! JSONDecoder().decode(TemplateValue.self, from: contextData)
            var sink = 0
            for _ in 0..<perTask { sink &+= template.render(context).utf8.count }
            return sink
         }
      }
      for await _ in group {}
   }
   let (s, attoseconds) = (clock.now - start).components
   let total = Double(s) + Double(attoseconds) / 1e18
   return (total / Double(tasks * perTask) * 1e6, tasks)
}

func line(_ fixture: String, _ label: String, _ microseconds: Double, _ note: String) {
   let name = fixture.padding(toLength: 10, withPad: " ", startingAt: 0)
   let metric = label.padding(toLength: 34, withPad: " ", startingAt: 0)
   print("\(name) \(metric) \(String(format: "%10.2f", microseconds)) us/op  \(note)")
}

try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)

let names = try FileManager.default.contentsOfDirectory(atPath: fixtures.path)
   .filter { $0.hasSuffix(".tmpl") }
   .map { String($0.dropLast(5)) }
   .sorted()

for name in names {
   let source = try String(contentsOf: fixtures.appendingPathComponent(name + ".tmpl"), encoding: .utf8)
   let contextData = try Data(contentsOf: fixtures.appendingPathComponent(name + ".json"))
   let context = try JSONDecoder().decode(TemplateValue.self, from: contextData)
   let template = try Template(source)
   
   try template.render(context).write(to: outputs.appendingPathComponent(name + ".swift.txt"), atomically: true, encoding: .utf8)
   
   let parse = measure { (try? Template(source)) != nil ? 1 : 0 }
   line(name, "parse", parse.microseconds, "")
   
   let render = measure { template.render(context).utf8.count }
   line(name, "render (parsed once)", render.microseconds, "")
   
   let both = measure { (try? Template(source))?.render(context).utf8.count ?? 0 }
   line(name, "parse + render", both.microseconds, "")
   
   let concurrent = await measureConcurrent(template, contextData)
   line(name, "render, all cores", concurrent.microseconds, "(\(concurrent.tasks) tasks sharing one template, wall time / renders)")
}

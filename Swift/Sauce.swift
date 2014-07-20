// Sauce
// by Dustin Mierau
// Under MIT license

import Foundation

class Sauce {
   var markers = (begin:"{%", end:"%}")
   var source:String { willSet { self.syntaxTree = nil } }
   var trimming:Bool { willSet { self.syntaxTree = nil } }
   var context = Context(object:nil)
   var syntaxTree: SyntaxNode?
   
   init(source:String) {
      self.source = source
      self.trimming = true
   }
   
   convenience init(file:String) {
      self.init(source:NSString.stringWithContentsOfFile(file, encoding:NSUTF8StringEncoding, error:nil))
   }
   
   convenience init() {
      self.init(source:"")
   }
   
   func render(object:NSObject?) -> String {
      // Setup new context with specified object.
      self.context = Context(object:object)
      
      // If necessary, analyze template source, build
      // syntax tree, and trim whitespace if desired.
      if !self.syntaxTree {
         self.analyze()
         if self.trimming {
            self.trim()
         }
      }
      
      // Render template.
      var rendered = NSMutableString()
      self.build(self.syntaxTree!, output:rendered)
      
      return rendered
   }
   
   func analyze() {
      self.syntaxTree = SyntaxNode(type:.Root)
      var previousNode: SyntaxNode = self.syntaxTree!
      var syntaxCursor = self.syntaxTree!
      
      let scanner = NSScanner(string:self.source)
      scanner.charactersToBeSkipped = nil
      analyzeLoop: while !scanner.atEnd {
         var scannedText:NSString?
         
         if scanner.scanUpToString(self.markers.begin, intoString:&scannedText) {
            var text = scannedText!
            let node = SyntaxNode(text:text)
            node.parent = syntaxCursor
            node.parent!.children += node
            node.previous = previousNode
            previousNode.next = node
            previousNode = node
         }
         
         if scanner.scanUpToString(self.markers.end, intoString:&scannedText) {
            scanner.scanString(self.markers.end, intoString:nil)
            let text = scannedText!.substringFromIndex(countElements(self.markers.begin))
            let node = SyntaxNode(statement:text)

            if node.isBranchEnd {
               syntaxCursor = syntaxCursor.parent!
            }
            
            node.parent = syntaxCursor
            node.parent!.children += node
            node.previous = previousNode
            previousNode.next = node
            
            if node.isBranchStart {
               syntaxCursor = node
            }
            
            previousNode = node
         }
      }
   }
   
   func build(node:SyntaxNode, output:NSMutableString) {
      var condition = false
      
      if node.type == .Root {
         self.context.push()
      }
      
      for (childIndex, child) in enumerate(node.children) {
         switch child.type {
         case .Text:
            output.appendString(child.content)
            
         case .If:
            self.context.push()
            condition = child.evaluateConditionalStatement(self.context)
            if condition {
               self.build(child, output:output)
            }

         case .ElseIf:
            self.context.pop()
            self.context.push()
            if !condition {
               condition = child.evaluateConditionalStatement(self.context)
               if condition {
                  self.build(child, output:output)
               }
            }
            
         case .Else:
            self.context.pop()
            self.context.push()
            if !condition {
               condition = true
               self.build(child, output:output)
            }
            
         case .End:
            self.context.pop()
            condition = false
            
         case .ForEach:
            self.context.push()
            child.evaluateLoopStatement(self.context, { loopIndex, loopValueName, loopValue in
               self.context.push()
               self.context.setValue(loopValue, forKey:loopValueName)
               self.context.setValue(loopIndex, forKey:"\(loopValueName)Index")
               self.build(child, output:output)
               self.context.pop()
            })
            
         case .Variable:
            if let (varName, varValue:AnyObject?, varAssign) = child.evaluateVariableStatement(self.context) {
               if varValue {
                  self.context.setValue(varValue, forKey:varName)
               }
               else {
                  self.context.setValue(NSNull(), forKey:varName)
               }
            }
            
         case .Value:
            if let valueOutput:AnyObject = child.evaluateValueStatement(self.context) {
               output.appendString(valueOutput.description)
            }
            
         case .Debug:
            if let debugValue:AnyObject = child.evaluateDebugStatement(self.context) {
               println("\(debugValue)")
            }
         
         default:
            break
         }
      }
      
      if node.type == .Root {
         self.context.pop()
      }
   }
   
   func trim(parentNode:SyntaxNode? = nil) {
      /*
      
      Trimming Rules:
      
      • Spaces and tabs leading a trimmable tag are removed.
      • Spaces, tabs, and a single newline trailing a trimmable tag are removed.
      • Ignore removal if whitespace leading or trailing a trimmable tag contains non-whitespace characters.
      
      */
      
      var parent = self.syntaxTree!
      if parentNode {
         parent = parentNode!
      }
      
      for child in parent.children {
         if child.trimmable {
            var shouldTrim = true
            var startText:NSString = ""
            var startLineRange = NSMakeRange(NSNotFound, 0)
            var endText:NSString = ""
            var endLineRange = NSMakeRange(NSNotFound, 0)
            
            if child.previous && child.previous!.type == .Text {
               let text:NSString = child.previous!.content
               startLineRange = text.lineRangeForRange(NSMakeRange(text.length, 0))
               startText = text.substringWithRange(startLineRange).stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
               shouldTrim = (startText.length == 0)
            }
            
            if shouldTrim && child.next && child.next!.type == .Text {
               let text:NSString = child.next!.content
               endLineRange = text.lineRangeForRange(NSMakeRange(0, 0))
               endText = text.substringWithRange(endLineRange).stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
               shouldTrim = (endText.length == 0)
            }
            
            if shouldTrim && startLineRange.location != NSNotFound && child.previous {
               let text:NSString = child.previous!.content
               child.previous!.content = text.substringToIndex(startLineRange.location)
            }
            
            if shouldTrim && endLineRange.location != NSNotFound && child.next {
               let text:NSString = child.next!.content
               child.next!.content = text.substringFromIndex(endLineRange.location + endLineRange.length)
            }
         }
      
         if child.children.count > 0 {
            self.trim(parentNode:child)
         }
      }
   }
   
   func print() {
      self.syntaxTree?.print()
   }
   
   enum SyntaxNodeType:Int {
      case None = 0
      case Root
      case Text, Value, Variable
      case If, ElseIf, Else
      case ForEach
      case End
      case Debug
      
      var description:String {
        return [None:"None", Root:"Root", Text:"Text", Value:"Value", Variable:"Variable", If:"If", ElseIf:"ElseIf", Else:"Else", ForEach:"ForEach", End:"End", Debug:"Debug"][self]!
      }
   }
   
   class SyntaxNode {
      var type:SyntaxNodeType = .None
      var content:NSString
      var children:[SyntaxNode] = []
      weak var parent:SyntaxNode?
      weak var next:SyntaxNode?
      weak var previous:SyntaxNode?
      
      var isBranchStart:Bool {
         switch self.type {
            case .If, .ElseIf, .Else, .ForEach:
               return true
            default:
               return false
         }
      }
      
      var isBranchEnd:Bool {
         switch self.type {
            case .ElseIf, .Else, .End:
               return true
            default:
               return false
         }
      }
      
      var trimmable:Bool {
         switch self.type {
            case .Variable, .If, .ElseIf, .Else, .ForEach, .End, .Debug:
               return true
            default:
               return false
         }
      }
      
      init(text:String) {
         self.content = text
         self.type = .Text
      }
      
      init(statement:String) {
         func matchesRegex(str:NSString, regex:String) -> Bool {
				return str.rangeOfString(regex, options:.RegularExpressionSearch | .CaseInsensitiveSearch | .AnchoredSearch).location != NSNotFound
			}
         
         self.content = statement.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
         
         self.type = .Value
         if matchesRegex(self.content, "\\s*(var\\s+)?[a-zA-Z0-9]+\\s+=\\s+") {
            self.type = .Variable
         }
         else if matchesRegex(self.content, "\\s*if\\s*\\(") {
			   self.type = .If
			}
         else if matchesRegex(self.content, "\\s*else\\s+if\\s*\\(") {
			   self.type = .ElseIf
			}
         else if matchesRegex(self.content, "\\s*else\\b") {
			   self.type = .Else
			}
         else if matchesRegex(self.content, "\\s*end\\b") {
				self.type = .End
			}
         else if matchesRegex(self.content, "\\s*foreach\\s*\\(") {
				self.type = .ForEach
			}
         else if matchesRegex(self.content, "\\s*debug\\s*\\(") {
            self.type = .Debug
         }
      }
      
      init(type:SyntaxNodeType) {
         self.type = type
         self.content = ""
      }
      
      func print(contents:Bool = false, indent:Int = 0) {
         var desc = "\(self.type.description)"
         if contents == true {
            desc += ": \"\(self.content)\""
         }
         
         for var i = indent; i > 0; i-- {
            desc = "\t" + desc
         }
         println(desc)
         
         for n in self.children {
            n.print(contents:contents, indent:indent+1)
         }
      }
      
      func evaluateVariableStatement(context:Context) -> (name:String, value:AnyObject?, assign:Bool)? {
         let regex = NSRegularExpression(pattern:"(?:\\s*)(var\\s+)?([a-zA-Z0-9]+)(?:\\s+=\\s+)(.*)", options:.CaseInsensitive, error:nil)
         let result = regex.firstMatchInString(self.content, options:NSMatchingOptions.fromRaw(0)!, range:NSMakeRange(0, self.content.length))
         if result.numberOfRanges == 4 {
            let varRange = result.rangeAtIndex(1)
            let varIsAssignment = (varRange.location == NSNotFound)
            let varNameRange = result.rangeAtIndex(2)
            let varExpressionRange = result.rangeAtIndex(3)
            if varNameRange.location != NSNotFound && varExpressionRange.location != NSNotFound {
               let statementVariableName = self.content.substringWithRange(varNameRange).stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
               let statementExpression = self.content.substringWithRange(varExpressionRange).stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
               var statementValue:AnyObject = NSNull()
               if let v:AnyObject = self.fetchValueForStatement(statementExpression, context:context) {
                  statementValue = v
               }
               return (statementVariableName, statementValue, varIsAssignment)
            }
         }
         
         return nil
      }
      
      func evaluateValueStatement(context:Context) -> AnyObject? {
         var isExpression = false
         let expressionCharacterSet = NSCharacterSet(charactersInString:"*-+()[]=/0123456789")
         if self.content.rangeOfCharacterFromSet(expressionCharacterSet).location != NSNotFound {
            isExpression = true
         }
         
         if let value:AnyObject = self.fetchValueForStatement(self.content, context:context, allowJSON:false, allowExpressions:isExpression) {
            return value
         }
         
         return nil
      }
      
      func evaluateConditionalStatement(context:Context) -> Bool {
         let statementStart = self.content.rangeOfString("^\\s*(?:if|else\\s+if)\\s*\\(\\s*", options:.RegularExpressionSearch | .CaseInsensitiveSearch)
         let statementEnd = self.content.rangeOfString("\\s*\\)\\s*$", options:.RegularExpressionSearch | .CaseInsensitiveSearch)
         let statementContent = self.content.substringWithRange(NSMakeRange(statementStart.location+statementStart.length, statementEnd.location-(statementStart.location+statementStart.length)))
         return NSPredicate(format:statementContent, argumentArray:nil).evaluateWithObject(context)
      }
      
      func evaluateDebugStatement(context:Context) -> AnyObject? {
         let regex = NSRegularExpression(pattern:"(?:debug\\s*\\(\\s*)(.*)(?:\\s*\\)\\s*)", options:.CaseInsensitive, error:nil)
         let result = regex.firstMatchInString(self.content, options:NSMatchingOptions.fromRaw(0)!, range:NSMakeRange(0, self.content.length))
         
         if result.numberOfRanges == 2 {
            let statementContent = self.content.substringWithRange(result.rangeAtIndex(1))
            if let statementValue:AnyObject = self.fetchValueForStatement(statementContent, context:context) {
               return statementValue
            }
         }
         
         return nil
      }
      
      func evaluateLoopStatement(context:Context, loop:(index:UInt, name:String, value:AnyObject) -> ()) {
         var statementInfo:(variable:String, array:[AnyObject]) = ("", [])
         
         let regex = NSRegularExpression(pattern:"(?:foreach\\s*\\(\\s*)(.*)\\s*in\\s*(.*)(?:\\s*\\)\\s*)", options:.CaseInsensitive, error:nil)
         let result = regex.firstMatchInString(self.content, options:NSMatchingOptions.fromRaw(0)!, range:NSMakeRange(0, self.content.length))

         if result.numberOfRanges == 3 {
            statementInfo.variable = self.content.substringWithRange(result.rangeAtIndex(1)).stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
            let statementArray = self.content.substringWithRange(result.rangeAtIndex(2)).stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
            if let value:AnyObject = self.fetchValueForStatement(statementArray, context:context) {
               statementInfo.array = value as [AnyObject]
            }
         }
         
         for (index, value) in enumerate(statementInfo.array) {
            loop(index:UInt(index), name:statementInfo.variable, value:value)
         }
      }
      
      func fetchValueForStatement(statement:String, context:Context, allowJSON:Bool = true, allowExpressions:Bool = true) -> AnyObject? {
         let statementContent:NSString = statement.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
         
         // Try JSON evaluation if allowed.
         if allowJSON && (statementContent.hasPrefix("[") || statementContent.hasPrefix("{")) {
   			var jsonError:NSError?
   			let jsonObject:AnyObject? = NSJSONSerialization.JSONObjectWithData(statementContent.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion:false), options:nil, error:&jsonError)
   			if !jsonError {
               return jsonObject
   			}
         }
         
         // Try expression evaluation if allowed.
         if allowExpressions {
            let expression = NSExpression(format:statementContent, argumentArray:nil)
            return expression.expressionValueWithObject(context, context:nil)
         }

         // Attempt to find value via key value path.
         if let keyPathValue:AnyObject = context.valueForKeyPath(statementContent) {
            return keyPathValue
         }

         return nil
      }
   }
   
   class Context:NSObject {
      var object:NSObject?
      var stack:[NSMutableDictionary] = []
      
      init(object:NSObject?) {
         self.object = object
      }
      
      func push() {
         self.stack += NSMutableDictionary()
      }
      
      func pop() {
         self.stack.removeLast()
      }
      
      override func valueForUndefinedKey(key:String) -> AnyObject? {
         if let (_, keyValue:AnyObject) = self.findKeyInfo(key) {
            return keyValue
         }
         
         return self.object?.valueForKeyPath(key);
      }
      
      override func setValue(value:AnyObject?, forUndefinedKey:String) {
         if let (frameIndex, _) = self.findKeyInfo(forUndefinedKey) {
            let frame = self.stack[frameIndex]
            frame.setObject(value, forKey:forUndefinedKey)
         }
         else if self.stack.count > 0 {
            let frame = self.stack[self.stack.count-1]
            frame.setObject(value, forKey:forUndefinedKey)
         }
      }
      
      override func setNilValueForKey(key:String) {
         if let (frameIndex, _) = self.findKeyInfo(key) {
            let frame = self.stack[frameIndex]
            frame.removeObjectForKey(key)
         }
      }
      
      func findKeyInfo(key:String) -> (frameIndex:Int, keyValue:AnyObject)? {
         if self.stack.count > 0 {
            for (i, frame) in enumerate(reverse(self.stack)) {
               if let v:AnyObject = frame.valueForKeyPath(key) {
                  return (frameIndex:(self.stack.count-1)-i, keyValue:v)
               }
            }
         }
         return nil
      }
   }
}
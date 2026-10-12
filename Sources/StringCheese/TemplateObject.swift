// StringCheese
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

/// A value templates read one key at a time, as a template asks for them,
/// rather than one converted into a `TemplateValue` before rendering. It suits
/// large or expensive values a template only reads part of, such as a model
/// object backed by a database.
///
///     struct Account: TemplateObject {
///        let id: Int
///        func value(forKey key: String) -> TemplateValue? {
///           switch key {
///           case "name": return .string(Database.name(of: id))
///           case "orders": return .array(Database.orders(of: id).map { .object($0) })
///           default: return nil
///           }
///        }
///     }
///
///     template.render(["account": .object(Account(id: 7))])
///
/// `TemplateValue(any:)` and `render(object:)` keep these as objects. On
/// Apple platforms they also read other `NSObject`s, such as Core Data
/// objects, this way, through their `@objc` properties.
public protocol TemplateObject: Sendable {
   /// The value for `key`, or nil when there's no such key. Strict mode
   /// reports a nil as a missing key; return `.null` for a key that's there
   /// with no value.
   func value(forKey key: String) -> TemplateValue?

   /// The whole object, for when a template uses it as one value rather than
   /// reading a key: writing it out, looping over it, counting or comparing
   /// it, or passing it to a function. Default: its description, as text.
   var templateValue: TemplateValue { get }
}

extension TemplateObject {
   public var templateValue: TemplateValue {
      .string(String(describing: self))
   }
}

extension TemplateValue {
   /// The value to use where a template needs the whole value: an object's
   /// `templateValue`, and any other value as it is.
   var resolved: TemplateValue {
      if case .object(let object) = self {
         return object.templateValue
      }
      return self
   }
}

#if canImport(ObjectiveC)
/// An `NSObject` read through KVC, one `@objc` property at a time.
///
/// Like the object itself, this is only as safe to use from several threads
/// as the object is; render a Core Data object on its context's queue.
struct KeyValueObject: TemplateObject, @unchecked Sendable {
   let object: NSObject

   func value(forKey key: String) -> TemplateValue? {
      // KVC raises an Objective-C exception, which Swift can't catch, for a
      // key the object doesn't have, so check for a getter first.
      guard object.responds(to: NSSelectorFromString(key)) else {
         return nil
      }
      return TemplateValue(any: object.value(forKey: key))
   }

   var templateValue: TemplateValue {
      .string(object.description)
   }
}
#endif

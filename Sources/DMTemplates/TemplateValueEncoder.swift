// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

import Foundation

/// Encodes Encodable values straight into template values.
///
/// The result matches what JSONEncoder would produce with its default
/// settings, read back as a template value, except that dates stay dates.
/// Skipping the round trip through JSON text makes it many times faster.
enum TemplateValueEncoder {
   static func encode<T: Encodable>(_ value: T, codingPath: @autoclosure () -> [any CodingKey] = []) throws -> TemplateValue {
      if let converted = convert(value) {
         return converted
      }
      let encoder = Encoder(codingPath: codingPath())
      try value.encode(to: encoder)
      return encoder.storage.finish()
   }

   /// Values that convert directly, either because they're simple or because
   /// they'd encode themselves into something templates can't use, such as a
   /// date as a count of seconds.
   private static func convert<T>(_ value: T) -> TemplateValue? {
      // Exact type checks keep a Bool from passing for a number, or the
      // reverse, through NSNumber bridging.
      if T.self == String.self { return .string(value as! String) }
      if T.self == Int.self { return .int(value as! Int) }
      if T.self == Double.self { return .double(value as! Double) }
      if T.self == Bool.self { return .bool(value as! Bool) }

      switch value {
      case let v as TemplateValue: return v
      case let v as Date: return .date(v)
      case let v as URL: return .string(v.absoluteString)
      case let v as Data: return .string(v.base64EncodedString())
      case let v as Decimal: return .decimal(v)
      // Other numbers, such as Int32 or Float, encode themselves through
      // SingleValueContainer.
      default: return nil
      }
   }
}

// MARK: - Storage

/// What a value's containers write into.
private final class Storage {
   private var single: TemplateValue?
   private var keyed: [String: TemplateValue]?
   private var unkeyed: [TemplateValue]?

   /// Nested containers and super encoders. They're written to after they're
   /// handed out, so their values are collected when encoding finishes.
   private var nested: [(slot: Slot, storage: Storage)] = []

   private enum Slot {
      case key(String)
      case index(Int)
   }

   /// The encoded value. Read once, after encoding finishes.
   func finish() -> TemplateValue {
      for (slot, storage) in nested {
         switch slot {
         case .key(let key): keyed?[key] = storage.finish()
         case .index(let index): unkeyed?[index] = storage.finish()
         }
      }
      if let keyed { return .dictionary(keyed) }
      if let unkeyed { return .array(unkeyed) }
      return single ?? .null
   }

   var count: Int { unkeyed?.count ?? 0 }

   func set(_ value: TemplateValue) {
      single = value
   }

   func set(_ value: TemplateValue, forKey key: any CodingKey) {
      makeKeyed()
      keyed![key.stringValue] = value
   }

   func append(_ value: TemplateValue) {
      makeUnkeyed()
      unkeyed!.append(value)
   }

   /// Storage for a nested container or super encoder under `key`.
   func nested(forKey key: any CodingKey) -> Storage {
      let storage = Storage()
      set(.null, forKey: key)
      nested.append((.key(key.stringValue), storage))
      return storage
   }

   /// Storage for a nested container or super encoder appended to the array.
   func appendNested() -> Storage {
      let storage = Storage()
      nested.append((.index(count), storage))
      append(.null)
      return storage
   }

   /// Makes this storage hold a dictionary, even an empty one.
   func makeKeyed() {
      if keyed == nil { keyed = [:] }
   }

   /// Makes this storage hold an array, even an empty one.
   func makeUnkeyed() {
      if unkeyed == nil { unkeyed = [] }
   }
}

// MARK: - Encoder

private final class Encoder: Swift.Encoder {
   let storage: Storage
   let codingPath: [any CodingKey]
   var userInfo: [CodingUserInfoKey: Any] { [:] }

   init(codingPath: [any CodingKey], storage: Storage = Storage()) {
      self.codingPath = codingPath
      self.storage = storage
   }

   func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
      storage.makeKeyed()
      return KeyedEncodingContainer(KeyedContainer(storage: storage, codingPath: codingPath))
   }

   func unkeyedContainer() -> any UnkeyedEncodingContainer {
      storage.makeUnkeyed()
      return UnkeyedContainer(storage: storage, codingPath: codingPath)
   }

   func singleValueContainer() -> any SingleValueEncodingContainer {
      SingleValueContainer(storage: storage, codingPath: codingPath)
   }
}

private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
   let storage: Storage
   let codingPath: [any CodingKey]

   mutating func encodeNil(forKey key: Key) throws {
      storage.set(.null, forKey: key)
   }

   mutating func encode(_ value: String, forKey key: Key) throws {
      storage.set(.string(value), forKey: key)
   }

   mutating func encode(_ value: Int, forKey key: Key) throws {
      storage.set(.int(value), forKey: key)
   }

   mutating func encode(_ value: Double, forKey key: Key) throws {
      storage.set(.double(value), forKey: key)
   }

   mutating func encode(_ value: Bool, forKey key: Key) throws {
      storage.set(.bool(value), forKey: key)
   }

   mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
      storage.set(try TemplateValueEncoder.encode(value, codingPath: codingPath + [key]), forKey: key)
   }

   mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
      let nested = storage.nested(forKey: key)
      nested.makeKeyed()
      return KeyedEncodingContainer(KeyedContainer<NestedKey>(storage: nested, codingPath: codingPath + [key]))
   }

   mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
      let nested = storage.nested(forKey: key)
      nested.makeUnkeyed()
      return UnkeyedContainer(storage: nested, codingPath: codingPath + [key])
   }

   mutating func superEncoder() -> any Swift.Encoder {
      superEncoder(for: SuperKey.super)
   }

   mutating func superEncoder(forKey key: Key) -> any Swift.Encoder {
      superEncoder(for: key)
   }

   private func superEncoder(for key: any CodingKey) -> any Swift.Encoder {
      Encoder(codingPath: codingPath + [key], storage: storage.nested(forKey: key))
   }
}

private struct UnkeyedContainer: UnkeyedEncodingContainer {
   let storage: Storage
   let codingPath: [any CodingKey]

   var count: Int { storage.count }

   private var nextKey: IndexKey { IndexKey(intValue: count) }

   mutating func encodeNil() throws {
      storage.append(.null)
   }

   mutating func encode(_ value: String) throws {
      storage.append(.string(value))
   }

   mutating func encode(_ value: Int) throws {
      storage.append(.int(value))
   }

   mutating func encode(_ value: Double) throws {
      storage.append(.double(value))
   }

   mutating func encode(_ value: Bool) throws {
      storage.append(.bool(value))
   }

   mutating func encode<T: Encodable>(_ value: T) throws {
      let key = nextKey
      storage.append(try TemplateValueEncoder.encode(value, codingPath: codingPath + [key]))
   }

   mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
      let key = nextKey
      let nested = storage.appendNested()
      nested.makeKeyed()
      return KeyedEncodingContainer(KeyedContainer<NestedKey>(storage: nested, codingPath: codingPath + [key]))
   }

   mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
      let key = nextKey
      let nested = storage.appendNested()
      nested.makeUnkeyed()
      return UnkeyedContainer(storage: nested, codingPath: codingPath + [key])
   }

   mutating func superEncoder() -> any Swift.Encoder {
      let key = nextKey
      return Encoder(codingPath: codingPath + [key], storage: storage.appendNested())
   }
}

private struct SingleValueContainer: SingleValueEncodingContainer {
   let storage: Storage
   let codingPath: [any CodingKey]

   mutating func encodeNil() throws { storage.set(.null) }
   mutating func encode(_ value: Bool) throws { storage.set(.bool(value)) }
   mutating func encode(_ value: String) throws { storage.set(.string(value)) }
   mutating func encode(_ value: Double) throws { storage.set(.double(value)) }
   // Through text, as JSON would, so 0.1 stays 0.1 rather than becoming
   // 0.10000000149011612.
   mutating func encode(_ value: Float) throws { storage.set(.double(Double(String(value)) ?? Double(value))) }
   mutating func encode(_ value: Int) throws { storage.set(.int(value)) }
   mutating func encode(_ value: Int8) throws { storage.set(.int(Int(value))) }
   mutating func encode(_ value: Int16) throws { storage.set(.int(Int(value))) }
   mutating func encode(_ value: Int32) throws { storage.set(.int(Int(value))) }
   mutating func encode(_ value: Int64) throws { storage.set(TemplateValue(integer: value)) }
   mutating func encode(_ value: UInt) throws { storage.set(TemplateValue(integer: value)) }
   mutating func encode(_ value: UInt8) throws { storage.set(.int(Int(value))) }
   mutating func encode(_ value: UInt16) throws { storage.set(.int(Int(value))) }
   mutating func encode(_ value: UInt32) throws { storage.set(TemplateValue(integer: value)) }
   mutating func encode(_ value: UInt64) throws { storage.set(TemplateValue(integer: value)) }

   mutating func encode<T: Encodable>(_ value: T) throws {
      storage.set(try TemplateValueEncoder.encode(value, codingPath: codingPath))
   }
}

// MARK: - Keys

private enum SuperKey: String, CodingKey {
   case `super`
}

private struct IndexKey: CodingKey {
   let intValue: Int?
   var stringValue: String { "Index \(intValue ?? 0)" }

   init(intValue: Int) { self.intValue = intValue }
   init?(stringValue: String) { nil }
}

private extension TemplateValue {
   /// An integer, as a real number when it's too big for Int.
   init<T: BinaryInteger>(integer value: T) {
      self = Int(exactly: value).map { .int($0) } ?? .double(Double(value))
   }
}

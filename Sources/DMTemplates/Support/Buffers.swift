// DMTemplates
// Dustin Mierau
// Cared for under the MIT license.

// Fixed buffers for compiled templates. See `ExpressionCode` for why compiled
// templates keep their parts in raw buffers rather than arrays.

/// A range of entries in a buffer, stored compactly.
struct Span {
   var start: Int32
   var count: Int32

   init(start: Int, count: Int) {
      self.start = Int32(start)
      self.count = Int32(count)
   }

   var range: Range<Int> { Int(start)..<Int(start + count) }
}

extension UnsafeMutableBufferPointer {
   /// A newly allocated buffer holding a copy of `elements`. Pair with
   /// `release()`.
   static func copying(_ elements: [Element]) -> UnsafeMutableBufferPointer<Element> {
      let buffer = UnsafeMutableBufferPointer<Element>.allocate(capacity: elements.count)
      _ = buffer.initialize(from: elements)
      return buffer
   }

   /// Destroys the elements and frees a buffer made by `copying(_:)`.
   func release() {
      _ = deinitialize()
      deallocate()
   }
}

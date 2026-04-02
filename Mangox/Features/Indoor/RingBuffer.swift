import Foundation

struct RingBuffer<T: Numeric> {
    private var storage: [T]
    private var index = 0
    private var count = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = [T](repeating: 0, count: capacity)
    }

    mutating func append(_ value: T) {
        storage[index] = value
        index = (index + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// Returns elements in insertion order (oldest first).
    var values: [T] {
        guard count > 0 else { return [] }
        if count < capacity {
            return Array(storage[0..<count])
        }
        // Buffer has wrapped: elements from index…end are older,
        // elements from 0..<index are newer.
        return Array(storage[index..<capacity]) + Array(storage[0..<index])
    }

    var isFull: Bool { count == capacity }
    var isEmpty: Bool { count == 0 }
    var currentCount: Int { count }

    mutating func reset() {
        storage = [T](repeating: 0, count: capacity)
        index = 0
        count = 0
    }
}

extension RingBuffer where T: BinaryInteger {
    /// Correct average: always iterates the logical values in insertion order,
    /// respecting wrap-around. Previously iterated storage[0..<count] directly,
    /// which returns wrong slots once the buffer has wrapped.
    var average: Double {
        guard count > 0 else { return 0 }
        return Double(sum) / Double(count)
    }

    /// Sum of all logical values without allocating an intermediate array.
    var sum: T {
        guard count > 0 else { return 0 }
        var result = T.zero
        if count < capacity {
            for i in 0..<count { result += storage[i] }
        } else {
            for i in index..<capacity { result += storage[i] }
            for i in 0..<index { result += storage[i] }
        }
        return result
    }
}

extension RingBuffer where T: BinaryFloatingPoint {
    var average: Double {
        guard count > 0 else { return 0 }
        return Double(sum) / Double(count)
    }

    /// Sum of all logical values without allocating an intermediate array.
    var sum: T {
        guard count > 0 else { return 0 }
        var result = T.zero
        if count < capacity {
            for i in 0..<count { result += storage[i] }
        } else {
            for i in index..<capacity { result += storage[i] }
            for i in 0..<index { result += storage[i] }
        }
        return result
    }
}

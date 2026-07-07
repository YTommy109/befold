import Foundation

/// A simple LRU (Least Recently Used) cache for expensive computations.
final class LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var storage: [Key: Value] = [:]
    private var usageOrder: [Key] = []

    init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
    }

    func value(for key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    func insert(_ value: Value, for key: Key) {
        if storage[key] == nil && storage.count >= capacity {
            evictLeastRecentlyUsed()
        }
        storage[key] = value
        touch(key)
    }

    private func touch(_ key: Key) {
        usageOrder.removeAll { $0 == key }
        usageOrder.append(key)
    }

    private func evictLeastRecentlyUsed() {
        guard !usageOrder.isEmpty else { return }
        let oldest = usageOrder.removeFirst()
        storage.removeValue(forKey: oldest)
    }
}

// MARK: - Usage example

let cache = LRUCache<String, Int>(capacity: 3)
cache.insert(42, for: "answer")
cache.insert(7, for: "lucky")

if let answer = cache.value(for: "answer") {
    print("The answer is \(answer)")
}

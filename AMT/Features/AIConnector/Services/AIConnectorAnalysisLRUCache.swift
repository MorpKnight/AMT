import Foundation

/// Small in-memory LRU cache used by document-scoped analysis stages.
///
/// The cache deliberately has no persistence or cross-document sharing. A
/// ViewModel owns one instance for each stage, and clearing the ViewModel's
/// state releases all entries when the document is closed.
struct AIConnectorAnalysisLRUCache<Value> {
    private let capacity: Int
    private var values: [String: Value] = [:]
    private var recency: [String] = []

    init(capacity: Int = 256) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { values.count }

    subscript(key: String) -> Value? {
        mutating get {
            guard let value = values[key] else { return nil }
            touch(key)
            return value
        }
        set {
            if let newValue {
                values[key] = newValue
                touch(key)
                evictIfNeeded()
            } else {
                values.removeValue(forKey: key)
                recency.removeAll { $0 == key }
            }
        }
    }

    mutating func removeAll() {
        values.removeAll()
        recency.removeAll()
    }

    private mutating func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private mutating func evictIfNeeded() {
        while recency.count > capacity {
            let oldest = recency.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }
}

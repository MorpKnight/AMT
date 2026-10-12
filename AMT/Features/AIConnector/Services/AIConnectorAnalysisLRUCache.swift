import Foundation

/// Bounded derived data. Payload bytes are a conservative estimate, not process RSS.
/// Owners keep actor isolation; the cache performs no inference or persistence.
nonisolated struct AIConnectorBoundedLRUCache<Key: Hashable, Value> {
    struct Statistics: Sendable {
        var hits = 0
        var misses = 0
        var evictions = 0
        var oversizedEntries = 0
    }
    private let capacity: Int
    private let maximumCost: Int
    private let payloadCost: (Key, Value) -> Int
    private var values: [Key: Value] = [:]
    private var costs: [Key: Int] = [:]
    private var recency: [Key] = []
    private(set) var totalCost = 0
    private(set) var statistics = Statistics()

    init(capacity: Int = 256, maximumCost: Int = 8 * 1_024 * 1_024,
         payloadCost: @escaping (Key, Value) -> Int = { key, value in
             AIConnectorCachePayloadCost.estimate(key) + AIConnectorCachePayloadCost.estimate(value)
         }) {
        self.capacity = max(capacity, 1)
        self.maximumCost = max(maximumCost, 0)
        self.payloadCost = payloadCost
    }
    var count: Int { values.count }
    var snapshot: [Key: Value] { values }

    subscript(key: Key) -> Value? {
        mutating get {
            guard let value = values[key] else { statistics.misses += 1; return nil }
            statistics.hits += 1
            touch(key)
            return value
        }
        set {
            remove(key)
            guard let value = newValue else { return }
            let cost = max(payloadCost(key, value), 0)
            guard cost <= maximumCost else { statistics.oversizedEntries += 1; return }
            values[key] = value; costs[key] = cost; totalCost += cost
            recency.append(key)
            while count > capacity || totalCost > maximumCost {
                guard let oldest = recency.first else { break }
                remove(oldest); statistics.evictions += 1
            }
        }
    }
    mutating func removeAll() {
        values.removeAll(); costs.removeAll(); recency.removeAll(); totalCost = 0
    }
    private mutating func remove(_ key: Key) {
        values.removeValue(forKey: key)
        totalCost -= costs.removeValue(forKey: key) ?? 0
        recency.removeAll { $0 == key }
    }
    private mutating func touch(_ key: Key) {
        recency.removeAll { $0 == key }; recency.append(key)
    }
}

typealias AIConnectorAnalysisLRUCache<Value> = AIConnectorBoundedLRUCache<String, Value>

/// Counts logical payload including repeated strings; shared backing storage may use less RAM.
nonisolated enum AIConnectorCachePayloadCost {
    static func estimate(_ value: Any, depth: Int = 0) -> Int {
        if let text = value as? String { return 32 + text.utf8.count }
        if let url = value as? URL { return 32 + url.absoluteString.utf8.count }
        if let data = value as? Data { return 32 + data.count }
        guard depth < 16 else { return 4_096 }
        let mirror = Mirror(reflecting: value)
        guard !mirror.children.isEmpty else { return 16 }
        return mirror.children.reduce(32) { $0 + estimate($1.value, depth: depth + 1) }
    }
}

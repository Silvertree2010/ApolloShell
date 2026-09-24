struct BoundedCache<Key: Hashable, Value> {
    private final class Slot {
        let value: Value
        var stamp: Int

        init(_ value: Value, stamp: Int) {
            self.value = value
            self.stamp = stamp
        }
    }

    let limit: Int
    private var storage: [Key: Slot] = [:]
    private var clock = 0

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    var count: Int { storage.count }

    subscript(key: Key) -> Value? {
        mutating get {
            guard let slot = storage[key] else { return nil }
            clock += 1
            slot.stamp = clock
            return slot.value
        }
        set {
            guard let newValue else {
                storage[key] = nil
                return
            }
            clock += 1
            storage[key] = Slot(newValue, stamp: clock)
            if storage.count > limit { evict() }
        }
    }

    mutating func removeAll() {
        storage.removeAll()
    }

    private mutating func evict() {
        let keep = max(1, limit * 3 / 4)
        let newest = storage.sorted { $0.value.stamp > $1.value.stamp }.prefix(keep)
        storage = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
    }
}

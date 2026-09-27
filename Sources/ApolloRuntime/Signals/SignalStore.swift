import ApolloConfig

public struct SubscriptionToken: Hashable, Sendable {
    public let id: Int
}

struct StoreSnapshot: Sendable {
    let roots: [String: Value]

    func value(_ root: String, _ fields: [String]) -> Value {
        guard let base = roots[root] else { return .null }
        return SignalStore.read(base, fields)
    }
}

@MainActor
public final class SignalStore {
    private struct Subscription {
        let path: DependencyPath
        let onChange: @MainActor () -> Void
    }

    private var roots: [String: Value] = [:]
    private var subscriptions: [Int: Subscription] = [:]
    private var demandGroups: [Int: [DependencyPath]] = [:]
    private var demandCounts: [DependencyPath: Int] = [:]
    private var nextToken = 0
    private let scheduler: any FlushScheduler
    private var flushRequested = false
    private var demandObservers: [@MainActor (String) -> Void] = []
    private var demandSettleObservers: [@MainActor () -> Void] = []

    public var onFlush: (@MainActor () -> Void)?

    public func addDemandObserver(_ observer: @escaping @MainActor (String) -> Void) {
        demandObservers.append(observer)
    }

    public func addDemandSettleObserver(_ observer: @escaping @MainActor () -> Void) {
        demandSettleObservers.append(observer)
    }

    public init(scheduler: any FlushScheduler) {
        self.scheduler = scheduler
    }

    public func value(_ path: DependencyPath) -> Value {
        guard let base = roots[path.root] else { return .null }
        return SignalStore.read(base, path.fields)
    }

    public func set(_ path: DependencyPath, _ value: Value) {
        set(path, sanitized: SignalStore.sanitize(value))
    }

    func set(_ path: DependencyPath, sanitized: Value) {
        guard !self.value(path).isEqualInOrder(sanitized) else { return }
        let base = roots[path.root] ?? .record(Record())
        roots[path.root] = SignalStore.write(base, path.fields, sanitized)
        notify(path)
        requestFlush()
    }

    func remove(_ path: DependencyPath) {
        guard let last = path.fields.last, let base = roots[path.root] else { return }
        let parentFields = Array(path.fields.dropLast())
        guard case .record(var record) = SignalStore.read(base, parentFields), record[last] != nil else { return }
        record[last] = nil
        roots[path.root] = SignalStore.write(base, parentFields, .record(record))
        notify(path)
        requestFlush()
    }

    func removeRoot(_ root: String) {
        guard roots.removeValue(forKey: root) != nil else { return }
        notify(DependencyPath(root, []))
        requestFlush()
    }

    @discardableResult
    public func subscribe(_ path: DependencyPath, _ onChange: @escaping @MainActor () -> Void) -> SubscriptionToken {
        let token = nextToken
        nextToken += 1
        subscriptions[token] = Subscription(path: path, onChange: onChange)
        incrementDemand([path])
        return SubscriptionToken(id: token)
    }

    @discardableResult
    public func demand(_ paths: Set<DependencyPath>) -> SubscriptionToken {
        let token = nextToken
        nextToken += 1
        let ordered = Array(paths)
        demandGroups[token] = ordered
        incrementDemand(ordered)
        return SubscriptionToken(id: token)
    }

    public func unsubscribe(_ token: SubscriptionToken) {
        if let subscription = subscriptions.removeValue(forKey: token.id) {
            decrementDemand([subscription.path])
            return
        }
        if let paths = demandGroups.removeValue(forKey: token.id) {
            decrementDemand(paths)
        }
    }

    public func demandedPaths(root: String) -> Set<DependencyPath> {
        Set(demandCounts.keys.filter { $0.root == root })
    }

    var rootCount: Int {
        roots.count
    }

    var demandedPathCount: Int {
        demandCounts.count
    }

    var subscriptionCount: Int {
        subscriptions.count + demandGroups.count
    }

    func demandCount(_ path: DependencyPath) -> Int {
        demandCounts[path, default: 0]
    }

    private func incrementDemand(_ paths: [DependencyPath]) {
        var touchedRoots: [String] = []
        for path in paths {
            let count = demandCounts[path, default: 0]
            demandCounts[path] = count + 1
            if count == 0 {
                touchedRoots.append(path.root)
            }
        }
        for root in touchedRoots {
            for observer in demandObservers { observer(root) }
        }
    }

    private func decrementDemand(_ paths: [DependencyPath]) {
        var touchedRoots: [String] = []
        for path in paths {
            let count = demandCounts[path, default: 0] - 1
            if count <= 0 {
                demandCounts.removeValue(forKey: path)
                touchedRoots.append(path.root)
            } else {
                demandCounts[path] = count
            }
        }
        for root in touchedRoots {
            for observer in demandObservers { observer(root) }
        }
    }

    func snapshot() -> StoreSnapshot {
        StoreSnapshot(roots: roots)
    }

    private func notify(_ changed: DependencyPath) {
        for subscription in subscriptions.values where Self.related(subscription.path, changed) {
            subscription.onChange()
        }
    }

    func requestFlush() {
        guard !flushRequested else { return }
        flushRequested = true
        scheduler.requestFlush { [weak self] in
            guard let self else { return }
            self.flushRequested = false
            self.onFlush?()
            for observer in self.demandSettleObservers { observer() }
        }
    }

    private static func related(_ a: DependencyPath, _ b: DependencyPath) -> Bool {
        guard a.root == b.root else { return false }
        return isPrefix(a.fields, b.fields) || isPrefix(b.fields, a.fields)
    }

    private static func isPrefix(_ prefix: [String], _ fields: [String]) -> Bool {
        guard prefix.count <= fields.count else { return false }
        return Array(fields[0..<prefix.count]) == prefix
    }

    nonisolated static func read(_ value: Value, _ fields: [String]) -> Value {
        guard let first = fields.first else { return value }
        guard case .record(let record) = value, let next = record[first] else { return .null }
        return read(next, Array(fields.dropFirst()))
    }

    nonisolated static func write(_ value: Value, _ fields: [String], _ newValue: Value) -> Value {
        guard let first = fields.first else { return newValue }
        var record: Record
        if case .record(let existing) = value {
            record = existing
        } else {
            record = Record()
        }
        let child = record[first] ?? .null
        record[first] = write(child, Array(fields.dropFirst()), newValue)
        return .record(record)
    }

    nonisolated static func sanitize(_ value: Value) -> Value {
        isClean(value, depth: 0) ? value : rebuiltClean(value, depth: 0)
    }

    private nonisolated static func isClean(_ value: Value, depth: Int) -> Bool {
        switch value {
        case .number(let number):
            return number.isFinite
        case .list(let items):
            return depth < RuntimeLimits.valueDepth && items.allSatisfy { isClean($0, depth: depth + 1) }
        case .record(let record):
            return depth < RuntimeLimits.valueDepth && record.keys.allSatisfy { isClean(record[$0] ?? .null, depth: depth + 1) }
        default:
            return true
        }
    }

    private nonisolated static func rebuiltClean(_ value: Value, depth: Int) -> Value {
        switch value {
        case .number(let number):
            return number.isFinite ? value : .null
        case .list(let items):
            guard depth < RuntimeLimits.valueDepth else { return .null }
            return .list(items.map { isClean($0, depth: depth + 1) ? $0 : rebuiltClean($0, depth: depth + 1) })
        case .record(let record):
            guard depth < RuntimeLimits.valueDepth else { return .null }
            var sanitized = Record()
            for key in record.keys {
                let child = record[key] ?? .null
                sanitized[key] = isClean(child, depth: depth + 1) ? child : rebuiltClean(child, depth: depth + 1)
            }
            return .record(sanitized)
        default:
            return value
        }
    }
}

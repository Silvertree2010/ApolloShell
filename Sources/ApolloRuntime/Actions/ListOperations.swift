import ApolloBase
import ApolloConfig

public enum ListKey: Sendable, Hashable {
    case index(Int)
    case entry(String)
}

public struct ListLocator: Sendable, Hashable {
    public var entry: ListKey?
    public var field: String?

    public init(entry: ListKey? = nil, field: String? = nil) {
        self.entry = entry
        self.field = field
    }
}

public enum ListOperation: Sendable, Hashable {
    case insert(item: Value, at: Int?, idFrom: String?)
    case remove(at: ListKey)
    case move(from: ListKey, to: Int)
    case update(at: ListKey, fields: Record)
}

public enum ListOperations {
    public static func apply(
        _ op: ListOperation,
        to value: Value,
        locator: ListLocator = ListLocator(),
        span: SourceSpan = .synthetic()
    ) -> Result<Value, Diagnostic> {
        applyLocated(value, locator: locator, span: span) { items in
            applyDirect(op, to: items, span: span)
        }
    }

    public static func moveTo(
        from source: Value,
        at sourceKey: ListKey,
        to destination: Value,
        index: Int,
        locator: ListLocator = ListLocator(),
        span: SourceSpan = .synthetic()
    ) -> Result<(source: Value, destination: Value), Diagnostic> {
        locate(source, locator: locator, span: span).flatMap { located in
            resolveIndex(sourceKey, in: located.items, span: span).flatMap { sourceIndex in
                locate(destination, locator: locator, span: span).flatMap { destinationLocated in
                    guard index >= 0, index <= destinationLocated.items.count else {
                        return .failure(outOfRange("move-to target", index, upTo: destinationLocated.items.count, span: span))
                    }
                    var newSourceItems = located.items
                    let moved = newSourceItems.remove(at: sourceIndex)
                    var newDestinationItems = destinationLocated.items
                    newDestinationItems.insert(moved, at: index)
                    return .success((source: located.rebuild(newSourceItems), destination: destinationLocated.rebuild(newDestinationItems)))
                }
            }
        }
    }

    public static func swap(
        _ value: Value,
        _ keyA: ListKey,
        _ keyB: ListKey,
        locator: ListLocator = ListLocator(),
        span: SourceSpan = .synthetic()
    ) -> Result<Value, Diagnostic> {
        locate(value, locator: locator, span: span).flatMap { located in
            resolveIndex(keyA, in: located.items, span: span).flatMap { indexA in
                resolveIndex(keyB, in: located.items, span: span).map { indexB in
                    var newItems = located.items
                    newItems.swapAt(indexA, indexB)
                    return located.rebuild(newItems)
                }
            }
        }
    }

    public static func swap(
        _ a: Value,
        _ keyA: ListKey,
        _ b: Value,
        _ keyB: ListKey,
        locator: ListLocator = ListLocator(),
        span: SourceSpan = .synthetic()
    ) -> Result<(a: Value, b: Value), Diagnostic> {
        locate(a, locator: locator, span: span).flatMap { locatedA in
            resolveIndex(keyA, in: locatedA.items, span: span).flatMap { indexA in
                locate(b, locator: locator, span: span).flatMap { locatedB in
                    resolveIndex(keyB, in: locatedB.items, span: span).map { indexB in
                        var newA = locatedA.items
                        var newB = locatedB.items
                        let temp = newA[indexA]
                        newA[indexA] = newB[indexB]
                        newB[indexB] = temp
                        return (a: locatedA.rebuild(newA), b: locatedB.rebuild(newB))
                    }
                }
            }
        }
    }

    private static func applyLocated(
        _ value: Value,
        locator: ListLocator,
        span: SourceSpan,
        transform: ([Value]) -> Result<[Value], Diagnostic>
    ) -> Result<Value, Diagnostic> {
        locate(value, locator: locator, span: span).flatMap { located in
            transform(located.items).map(located.rebuild)
        }
    }

    private static func locate(
        _ value: Value,
        locator: ListLocator,
        span: SourceSpan
    ) -> Result<(items: [Value], rebuild: ([Value]) -> Value), Diagnostic> {
        guard let entryKey = locator.entry else {
            return extractList(value, span: span).map { items in
                (items, { .list($0) })
            }
        }
        return extractList(value, span: span).flatMap { items in
            resolveIndex(entryKey, in: items, span: span).flatMap { index in
                guard case .record(let record) = items[index] else {
                    return .failure(Diagnostic(.warning, "list locator entry is not a record", span: span, code: .listOperation))
                }
                if let field = locator.field {
                    let fieldValue = record[field] ?? .list([])
                    return extractList(fieldValue, span: span).map { fieldItems in
                        (fieldItems, { newFieldItems in
                            var newRecord = record
                            newRecord[field] = .list(newFieldItems)
                            var newItems = items
                            newItems[index] = .record(newRecord)
                            return .list(newItems)
                        })
                    }
                }
                return extractList(items[index], span: span).map { entryItems in
                    (entryItems, { newEntryItems in
                        var newItems = items
                        newItems[index] = .list(newEntryItems)
                        return .list(newItems)
                    })
                }
            }
        }
    }

    private static func applyDirect(_ op: ListOperation, to items: [Value], span: SourceSpan) -> Result<[Value], Diagnostic> {
        switch op {
        case .insert(let item, let at, let idFrom):
            return resolveInsertItem(item, idFrom: idFrom, existing: items, span: span).flatMap { resolvedItem in
                let index = at ?? items.count
                guard index >= 0, index <= items.count else {
                    return .failure(outOfRange("insert index", index, upTo: items.count, span: span))
                }
                var newItems = items
                newItems.insert(resolvedItem, at: index)
                return .success(newItems)
            }
        case .remove(let at):
            return resolveIndex(at, in: items, span: span).map { index in
                var newItems = items
                newItems.remove(at: index)
                return newItems
            }
        case .move(let from, let to):
            return resolveIndex(from, in: items, span: span).flatMap { fromIndex in
                guard to >= 0, to <= items.count else {
                    return .failure(outOfRange("move target", to, upTo: items.count, span: span))
                }
                if to == fromIndex || to == fromIndex + 1 {
                    return .success(items)
                }
                var newItems = items
                let moved = newItems.remove(at: fromIndex)
                let insertionIndex = to > fromIndex ? to - 1 : to
                newItems.insert(moved, at: insertionIndex)
                return .success(newItems)
            }
        case .update(let at, let fields):
            return resolveIndex(at, in: items, span: span).flatMap { index in
                guard case .record(var record) = items[index] else {
                    return .failure(Diagnostic(.warning, "list.update needs a record entry", span: span, code: .listOperation))
                }
                for key in fields.keys {
                    record[key] = fields[key]
                }
                var newItems = items
                newItems[index] = .record(record)
                return .success(newItems)
            }
        }
    }

    private static func resolveInsertItem(_ item: Value, idFrom: String?, existing: [Value], span: SourceSpan) -> Result<Value, Diagnostic> {
        guard let field = idFrom else { return .success(item) }
        guard case .record(var record) = item else {
            return .failure(Diagnostic(.warning, "id-from requires a record item", span: span, code: .listOperation))
        }
        guard case .string(let base)? = record[field], !base.isEmpty else {
            return .failure(Diagnostic(.warning, "id-from field \"\(field)\" is missing or empty", span: span, code: .listOperation))
        }
        let taken = Set(existing.compactMap { entry -> String? in
            guard case .record(let entryRecord) = entry, case .string(let id)? = entryRecord["id"] else { return nil }
            return id
        })
        record["id"] = .string(uniqueID(base: base, taken: taken))
        return .success(.record(record))
    }

    private static func uniqueID(base: String, taken: Set<String>) -> String {
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    private static func resolveIndex(_ key: ListKey, in items: [Value], span: SourceSpan) -> Result<Int, Diagnostic> {
        switch key {
        case .index(let index):
            guard index >= 0 else {
                return .failure(Diagnostic(.warning, "list index must not be negative", span: span, code: .listOperation))
            }
            guard index < items.count else {
                return .failure(outOfRange("list index", index, upTo: items.count, span: span))
            }
            return .success(index)
        case .entry(let id):
            if let found = items.firstIndex(where: { matches($0, id) }) {
                return .success(found)
            }
            return .failure(Diagnostic(.warning, "no list entry with key \"\(id)\"", span: span, code: .listOperation))
        }
    }

    private static func matches(_ item: Value, _ id: String) -> Bool {
        if case .record(let record) = item, case .string(let recordID)? = record["id"] {
            return recordID == id
        }
        if case .string(let text) = item {
            return text == id
        }
        return false
    }

    private static func extractList(_ value: Value, span: SourceSpan) -> Result<[Value], Diagnostic> {
        guard case .list(let items) = value else {
            return .failure(Diagnostic(.warning, "expected a list, got \(value.typeName)", span: span, code: .listOperation))
        }
        return .success(items)
    }

    private static func outOfRange(_ label: String, _ index: Int, upTo count: Int, span: SourceSpan) -> Diagnostic {
        Diagnostic(.warning, "\(label) \(index) out of range (0...\(count))", span: span, code: .listOperation)
    }
}

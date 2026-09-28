import Foundation
import ApolloBase
import ApolloConfig

@MainActor
final class Container {
    let region = Region()
    private let assign: @MainActor ([ElementInstance]) -> Void

    init(_ assign: @escaping @MainActor ([ElementInstance]) -> Void) {
        self.assign = assign
    }

    func refresh() {
        assign(region.flatten())
    }
}

@MainActor
final class Region {
    var parts: [TreeNode] = []
    var context: BuildContext?
    var entryKey: EntryKey?
    var item: Value = .null
    var index = 0
    var stamp = 0

    func flatten() -> [ElementInstance] {
        var result: [ElementInstance] = []
        append(into: &result)
        return result
    }

    private func append(into result: inout [ElementInstance]) {
        let parts = self.parts
        var index = 0
        while index < parts.count {
            let part = parts[index]
            index += 1
            if let element = part.flatInstance {
                result.append(element)
                continue
            }
            let regions = part.innerRegions
            var inner = 0
            while inner < regions.count {
                regions[inner].append(into: &result)
                inner += 1
            }
        }
    }
}

@MainActor
class TreeNode {
    var isDead = false
    var isParked = false
    var outerActive: Bool
    weak var region: Region?
    var stamp = 0

    var flatInstance: ElementInstance? { nil }

    init(outerActive: Bool) {
        self.outerActive = outerActive
    }

    var surfaceNode: SurfaceNode? {
        if let element = self as? ElementNode {
            return element.surface
        }
        return (self as? StructureNode)?.context.surface
    }

    var innerRegions: [Region] {
        if let element = self as? ElementNode {
            return element.childRegions
        }
        return (self as? StructureNode)?.regions ?? []
    }
}

struct BuildContext {
    let surface: SurfaceNode
    var scope: LocalScope
    var path: Identity
    var depth: Int
    var useDepth: Int
    var active: Bool
    let container: Container
    var slotOwner: StructureNode?
    var entryKey: Value?
}

@MainActor
final class ElementNode: TreeNode {
    let instance: ElementInstance

    override var flatInstance: ElementInstance? { instance }
    unowned let surface: SurfaceNode
    let runtimeID: String?
    var selfVisible = true
    var isConfigured = false
    var depth: Int
    var useDepth: Int
    var slotOwner: StructureNode?
    var visibleBinding: BindingHandle?
    var cellBindings: [String: BindingHandle] = [:]
    var argumentBindings: [Int: BindingHandle] = [:]
    var childContainer: Container?
    var slotContainers: [String: Container] = [:]

    init(instance: ElementInstance, surface: SurfaceNode, runtimeID: String?, context: BuildContext) {
        self.instance = instance
        self.surface = surface
        self.runtimeID = runtimeID
        depth = context.depth
        useDepth = context.useDepth
        slotOwner = context.slotOwner
        super.init(outerActive: context.active)
    }

    func childContext(_ container: Container, path: Identity) -> BuildContext {
        BuildContext(surface: surface, scope: instance.scope, path: path, depth: depth + 1, useDepth: useDepth, active: innerActive, container: container, slotOwner: slotOwner)
    }

    var innerActive: Bool {
        outerActive && selfVisible
    }

    var innerBindings: [BindingHandle] {
        Array(cellBindings.values) + Array(argumentBindings.values)
    }

    var allBindings: [BindingHandle] {
        var handles = innerBindings
        if let visibleBinding {
            handles.append(visibleBinding)
        }
        return handles
    }

    var childRegions: [Region] {
        var regions: [Region] = []
        if let childContainer {
            regions.append(childContainer.region)
        }
        for name in slotContainers.keys.sorted() {
            if let container = slotContainers[name] {
                regions.append(container.region)
            }
        }
        return regions
    }

    var childParts: [TreeNode] {
        childRegions.flatMap(\.parts)
    }
}

@MainActor
final class StructureNode: TreeNode {
    enum Kind: Equatable {
        case when(WhenIR)
        case switchOn(SwitchIR)
        case each(EachIR)
        case use(DynamicUseIR)
        case slot(String)

        init?(_ child: ChildIR) {
            switch child {
            case .element: return nil
            case .slot(let name): self = .slot(name ?? "")
            case .when(let when): self = .when(when)
            case .switchOn(let switchIR): self = .switchOn(switchIR)
            case .each(let each): self = .each(each)
            case .dynamicUse(let use): self = .use(use)
            }
        }

        var tag: String {
            switch self {
            case .when(let when): "when|" + when.key
            case .switchOn(let switchIR): "switch|" + switchIR.key
            case .each(let each): "each|" + each.key
            case .use(let use): "use|" + use.key
            case .slot(let name): "slot|" + name
            }
        }
    }

    var kind: Kind
    var context: BuildContext
    var subject: BindingHandle?
    var caseBindings: [[BindingHandle]] = []
    var argumentBindings: [String: BindingHandle] = [:]
    var defaultBindings: (parameters: [ParameterIR], arguments: Set<String>, handles: [BindingHandle])?
    var regions: [Region] = [] {
        didSet { entryLookup = nil }
    }
    var entryLookup: [EntryKey: Region]?
    var selection: String?
    var define: DefineIR?
    var rebuildQueued = false
    var slotNodes: [StructureNode] = []
    var slotPruneAt = 8
    var slotGeneration = -1

    init(kind: Kind, context: BuildContext) {
        self.kind = kind
        self.context = context
        super.init(outerActive: context.active)
    }

    var allBindings: [BindingHandle] {
        var handles: [BindingHandle] = []
        if let subject { handles.append(subject) }
        for group in caseBindings { handles.append(contentsOf: group) }
        for name in argumentBindings.keys.sorted() {
            if let handle = argumentBindings[name] { handles.append(handle) }
        }
        if let defaults = defaultBindings { handles.append(contentsOf: defaults.handles) }
        return handles
    }

    func register(_ slot: StructureNode) {
        if slotNodes.count >= slotPruneAt {
            slotNodes.removeAll { $0.isDead }
            slotPruneAt = max(8, slotNodes.count * 2)
        }
        slotNodes.append(slot)
    }
}

struct EntryKey: Hashable {
    private enum Kind: UInt8 {
        case position, string, number, bool, other
    }

    private let kind: Kind
    private let text: String
    private let number: Double
    private let typeName: String
    var ordinal: Int

    init(value: Value?, index: Int, ordinal: Int = 1) {
        self.ordinal = ordinal
        switch value {
        case nil:
            kind = .position
            text = ""
            number = Double(index)
            typeName = ""
        case .string(let value)?:
            kind = .string
            text = value
            number = 0
            typeName = ""
        case .number(let value)?:
            kind = .number
            text = ""
            number = value
            typeName = ""
        case .bool(let flag)?:
            kind = .bool
            text = ""
            number = flag ? 1 : 0
            typeName = ""
        case let other?:
            kind = .other
            text = EntryKey.text(other)
            number = 0
            typeName = other.typeName
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(ordinal)
        switch kind {
        case .position, .number, .bool:
            hasher.combine(number)
        case .string:
            hasher.combine(text)
        case .other:
            hasher.combine(typeName)
            hasher.combine(text)
        }
    }

    var component: String {
        var result: String
        switch kind {
        case .position:
            result = "i:" + String(Int(number))
        case .string:
            result = "k:string:" + EntryKey.escaped(text)
        case .number:
            result = "k:number:" + EntryKey.text(.number(number))
        case .bool:
            result = "k:bool:" + (number == 1 ? "true" : "false")
        case .other:
            result = "k:" + typeName + ":" + EntryKey.escaped(text)
        }
        if ordinal > 1 {
            result += "#" + String(ordinal)
        }
        return result
    }

    private static func escaped(_ text: String) -> String {
        text.contains("#") ? text.replacingOccurrences(of: "#", with: "##") : text
    }

    static func text(_ value: Value) -> String {
        switch value {
        case .string(let text): text
        case .number(let number): number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        case .bool(let flag): flag ? "true" : "false"
        default: String(describing: value)
        }
    }
}

@MainActor
final class CloseWaiter {
    let continuation: CheckedContinuation<Void, Never>
    var work: ScheduledWork?
    var resumed = false

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        guard !resumed else { return }
        resumed = true
        work?.cancel()
        continuation.resume()
    }
}

@MainActor
final class SurfaceNode {
    var budgetWarned = false
    let instance: SurfaceInstance
    let identity: Identity
    let surfaceKey: String
    var propertyBindings: [String: BindingHandle] = [:]
    var root: Container?
    var visibleProperty = true
    var hiddenByFullscreen = false
    var isClosing = false
    var isOpening = false
    var isConfigured = false
    var elementCount = 0
    var parkedElements: (generation: Int, pending: Int, count: Int)?
    var ids: [String: ElementNode] = [:]
    var closeWaiters: [CloseWaiter] = []
    var toasts: [Value] = []

    init(instance: SurfaceInstance) {
        self.instance = instance
        surfaceKey = instance.id + "@" + instance.screenKey
        identity = Identity([surfaceKey])
    }

    var kind: String {
        instance.ir.kind
    }

    var scope: LocalScope {
        LocalScope([
            ContextScopeKeys.surfaceKey: .string(surfaceKey),
            ContextScopeKeys.screenKey: .string(instance.screenKey),
        ])
    }
}

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

    func flatten() -> [ElementInstance] {
        var result: [ElementInstance] = []
        append(into: &result)
        return result
    }

    private func append(into result: inout [ElementInstance]) {
        for part in parts {
            if let element = part as? ElementNode {
                result.append(element.instance)
            } else if let structure = part as? StructureNode {
                for region in structure.regions {
                    region.append(into: &result)
                }
            }
        }
    }
}

@MainActor
class TreeNode {
    var isDead = false
    var outerActive: Bool

    init(outerActive: Bool) {
        self.outerActive = outerActive
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
}

@MainActor
final class ElementNode: TreeNode {
    let instance: ElementInstance
    unowned let surface: SurfaceNode
    let runtimeID: String?
    var selfVisible = true
    var isConfigured = false
    var visibleBinding: BindingHandle?
    var propertyBindings: [BindingHandle] = []
    var demandTokens: [SubscriptionToken] = []
    var childContainer: Container?
    var slotContainers: [String: Container] = [:]

    init(instance: ElementInstance, surface: SurfaceNode, runtimeID: String?, outerActive: Bool) {
        self.instance = instance
        self.surface = surface
        self.runtimeID = runtimeID
        super.init(outerActive: outerActive)
    }

    var innerActive: Bool {
        outerActive && selfVisible
    }

    var childParts: [TreeNode] {
        var parts = childContainer?.region.parts ?? []
        for name in slotContainers.keys.sorted() {
            parts.append(contentsOf: slotContainers[name]?.region.parts ?? [])
        }
        return parts
    }
}

@MainActor
final class StructureNode: TreeNode {
    enum Kind {
        case when(WhenIR)
        case switchOn(SwitchIR)
        case each(EachIR)
        case use(DynamicUseIR)
    }

    let kind: Kind
    let context: BuildContext
    var subject: BindingHandle?
    var caseBindings: [[BindingHandle]] = []
    var argumentBindings: [String: BindingHandle] = [:]
    var regions: [Region] = []
    var selection: String?
    var rebuildQueued = false

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
        return handles
    }

    var key: String {
        switch kind {
        case .when(let when): when.key
        case .switchOn(let switchIR): switchIR.key
        case .each(let each): each.key
        case .use(let use): use.key
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
    let instance: SurfaceInstance
    let identity: Identity
    let surfaceKey: String
    var propertyBindings: [BindingHandle] = []
    var root: Container?
    var visibleProperty = true
    var hiddenByFullscreen = false
    var isClosing = false
    var isConfigured = false
    var elementCount = 0
    var ids: [String: ElementNode] = [:]
    var closeWaiters: [CloseWaiter] = []

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

import AppKit
import ApolloConfig
import ApolloRuntime

indirect enum ElementMenuEntry {
    case item(ElementMenuCommand)
    case separator
    case section(String)
    case submenu(String, [ElementMenuEntry])

    var title: String {
        switch self {
        case .item(let command): command.title
        case .separator: "-"
        case .section(let title): "[" + title + "]"
        case .submenu(let title, _): title + " >"
        }
    }
}

struct ElementMenuCommand {
    var title: String
    var icon: String?
    var checked = false
    var disabled = false
    var shortcut: String?
    var alternate = false
    var perform: @MainActor () -> Void
}

@MainActor
protocol MenuSourceProviding {
    func entries(_ kind: String, properties: [String: Value], element: ElementInstance, context: RenderContext) async -> [ElementMenuEntry]
}

@MainActor
protocol MenuPresenting {
    func present(_ element: ElementInstance, context: RenderContext, from view: NSView, at point: NSPoint?)
}

@MainActor
enum MenuModel {
    static func entries(for element: ElementInstance, context: RenderContext) async -> [ElementMenuEntry] {
        guard let menu = element.ir.menu else { return [] }
        return await build(menu.items, element: element, context: context, locals: [:])
    }

    static func build(_ items: [MenuItemIR], element: ElementInstance, context: RenderContext, locals: [String: Value]) async -> [ElementMenuEntry] {
        var result: [ElementMenuEntry] = []
        func value(_ compiled: CompiledValue) -> Value {
            if let runtime = context.runtime { return runtime.evaluate(compiled, on: element.identity, locals: locals) }
            return HandlerRules.literal(compiled) ?? .null
        }
        for (position, item) in items.enumerated() {
            switch item {
            case let .item(title, properties, actions):
                let identity = element.identity
                let site = "menu#\(position)"
                let captured = locals
                result.append(.item(ElementMenuCommand(
                    title: value(title).stringified,
                    icon: properties["icon"].map(value)?.plainText,
                    checked: properties["checked"].map(value)?.isTruthy ?? false,
                    disabled: properties["disabled"].map(value)?.isTruthy ?? false,
                    shortcut: properties["shortcut"].map(value)?.plainText,
                    alternate: properties["alternate"].map(value)?.isTruthy ?? false,
                    perform: { [weak context] in
                        guard let task = context?.runtime?.run(actions, on: identity, site: site, event: Record(), locals: captured) else { return }
                        context?.track(task)
                    }
                )))
            case .separator:
                result.append(.separator)
            case .section(let title):
                result.append(.section(value(title).stringified))
            case let .submenu(title, children):
                result.append(.submenu(value(title).stringified, await build(children, element: element, context: context, locals: locals)))
            case let .source(kind, properties):
                let resolved = properties.mapValues(value)
                if let source = context.menuSources[kind] {
                    result += await source.entries(kind, properties: resolved, element: element, context: context)
                }
            case let .each(variable, index, list, _, body):
                guard case .list(let values) = value(list) else { continue }
                for (offset, entry) in values.enumerated() {
                    var inner = locals
                    inner[variable] = entry
                    if let index { inner[index] = .number(Double(offset)) }
                    result += await build(body, element: element, context: context, locals: inner)
                }
            case let .when(condition, then, otherwise):
                result += await build(value(condition).isTruthy ? then : otherwise, element: element, context: context, locals: locals)
            }
        }
        return result
    }
}

@MainActor
final class NativeMenuPresenter: MenuPresenting {
    func present(_ element: ElementInstance, context: RenderContext, from view: NSView, at point: NSPoint?) {
        let pointer = point ?? view.window.map { view.convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        Task { @MainActor [weak view, weak context] in
            guard let context else { return }
            let entries = await MenuModel.entries(for: element, context: context)
            guard !entries.isEmpty, let view, view.window != nil else { return }
            Self.open(entries, element: element, context: context, view: view, pointer: pointer)
        }
    }

    private static func open(_ entries: [ElementMenuEntry], element: ElementInstance, context: RenderContext, view: NSView, pointer: NSPoint?) {
        let menu = NativeMenu.make(entries, context: context)
        let side = element.ir.menu?.properties["side"].map { context.runtime?.evaluate($0, on: element.identity, locals: [:]) ?? HandlerRules.literal($0) ?? .null }?.plainText ?? "pointer"
        let offset = element.ir.menu?.properties["offset"].flatMap { context.runtime?.evaluate($0, on: element.identity, locals: [:]) }.flatMap(StyleValues.numberValue) ?? 6
        let location = NativeMenu.location(side: side, offset: offset, bounds: view.bounds, flipped: view.isFlipped, menuWidth: menu.size.width, pointer: pointer)
        menu.popUp(positioning: nil, at: location, in: view)
    }
}

@MainActor
enum NativeMenu {
    static func location(side: String, offset: CGFloat, bounds: CGRect, flipped: Bool, menuWidth: CGFloat, pointer: NSPoint?) -> NSPoint {
        let top = flipped ? bounds.minY : bounds.maxY
        let bottom = flipped ? bounds.maxY + offset : bounds.minY - offset
        switch side {
        case "right": return NSPoint(x: bounds.maxX + offset, y: top)
        case "left": return NSPoint(x: bounds.minX - offset - menuWidth, y: top)
        case "below": return NSPoint(x: bounds.minX, y: bottom)
        default: return pointer ?? NSPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    static func make(_ entries: [ElementMenuEntry], context: RenderContext) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .item(let command):
                let item = MenuActionItem(command: command)
                item.image = command.icon.flatMap { context.themeIcon($0) ?? NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
                if command.alternate {
                    let previous = menu.items.last
                    item.keyEquivalent = previous?.keyEquivalent ?? ""
                    item.keyEquivalentModifierMask = (previous?.keyEquivalentModifierMask ?? []).union(.option)
                    item.isAlternate = true
                }
                menu.addItem(item)
            case .separator:
                menu.addItem(.separator())
            case .section(let title):
                menu.addItem(NSMenuItem.sectionHeader(title: title))
            case let .submenu(title, children):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = make(children, context: context)
                menu.addItem(item)
            }
        }
        return menu
    }
}

@MainActor
final class MenuActionItem: NSMenuItem {
    private let perform: @MainActor () -> Void

    init(command: ElementMenuCommand) {
        perform = command.perform
        var equivalent = ""
        var mask: NSEvent.ModifierFlags = []
        if let shortcut = command.shortcut, let chord = KeyChord.parse(shortcut), chord.key.count == 1 {
            equivalent = chord.key
            if chord.modifiers.contains(.command) { mask.insert(.command) }
            if chord.modifiers.contains(.option) { mask.insert(.option) }
            if chord.modifiers.contains(.shift) { mask.insert(.shift) }
            if chord.modifiers.contains(.control) { mask.insert(.control) }
        }
        super.init(title: command.title, action: #selector(run), keyEquivalent: equivalent)
        keyEquivalentModifierMask = mask
        target = self
        state = command.checked ? .on : .off
        isEnabled = !command.disabled
    }

    required init(coder: NSCoder) {
        fatalError("not from a nib")
    }

    @objc private func run() {
        perform()
    }
}

import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class AppsProvider: BaseProvider {
    static let badgeInterval: Double = 3
    static let ownLaunchWindow: TimeInterval = 10
    static let launchTimeout: Double = 15
    static let fileManagerIcon = ImageRef(source: "builtin", id: "file-manager-folder")
    static let accessibilityActions: Set<String> = ["apps.new-window", "apps.cycle-windows", "apps.show-all-windows", "apps.run-command"]
    static let accessibilityClicks: Set<DockClickAction> = [.raiseWindowElsewhere, .raiseWindowOnActiveSpace, .raiseCoveredWindow, .unminimizeLast, .newWindow]

    private let source: any AppsSource
    private var catalog: [AppEntry] = []
    private var badges: [String: String] = [:]
    private var usage = UsageStats()
    private var favorites = PinnedList()
    private var launching: Set<String> = []
    private var ownLaunches: [String: Date] = [:]
    private var fileManagerSetting: String?
    private var wantedAll = false
    private var badgeReading = false
    private var generation = 0
    private var warnedSaves: Set<String> = []

    public init(source: any AppsSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("apps"), clock: clock)
    }

    override func didStart() {
        generation += 1
        badgeReading = false
        wantedAll = false
        loadStores()
        source.observeChanges { [weak self] change in
            self?.changed(change)
        }
        publishAll()
    }

    override func didChangeDemand() {
        let wantsAll = demand.wants("all")
        if wantsAll && !wantedAll { scan() }
        wantedAll = wantsAll
        timers.set("badges", every: Self.badgeInterval, active: demand.wants("dock"), immediately: true) { [weak self] in
            self?.readBadges()
        }
        if !demand.wants("dock") { badgeReading = false }
    }

    override func didStop() {
        generation += 1
        source.stopObserving()
    }

    override func didConfigure(_ settings: Record) {
        if case .string(let id) = settings["file-manager"] ?? .null, !id.isEmpty {
            fileManagerSetting = id
        } else {
            fileManagerSetting = nil
        }
        if isRunning { publishAll() }
    }

    private func loadStores() {
        if let data = source.loadUsage(), let decoded = try? JSONDecoder().decode(UsageStats.self, from: data) {
            usage = decoded
        }
        let data = source.loadFavorites()
        if PinnedList.isUnreadable(data) {
            source.preserveUnreadableFavorites()
            note("pinned.json is unreadable, kept a copy as pinned.json.unreadable")
        }
        favorites = PinnedList.load(from: data)
    }

    private func scan() {
        let generation = generation
        source.scanCatalog { [weak self] entries in
            guard let self, self.isRunning, generation == self.generation else { return }
            self.catalog = entries
            self.publishAll()
        }
    }

    private func readBadges() {
        guard isRunning, !badgeReading else { return }
        badgeReading = true
        let generation = generation
        source.readBadges { [weak self] next in
            guard let self, generation == self.generation else { return }
            self.badgeReading = false
            guard self.isRunning, next != self.badges else { return }
            self.badges = next
            self.publishAll()
        }
    }

    private func changed(_ change: AppsChange) {
        guard isRunning else { return }
        switch change {
        case .launched(let id):
            launching.remove(id)
            countLaunch(id)
            publishAll()
            emit("apps.launched", Record([("app", record(id))]))
        case .terminated(let id):
            launching.remove(id)
            let app = record(id)
            publishAll()
            emit("apps.terminated", Record([("app", app)]))
        case .activated(let id):
            publishAll()
            emit("apps.activated", Record([("app", record(id))]))
        case .visibility, .dock:
            publishAll()
        }
    }

    private func countLaunch(_ id: String) {
        let now = source.now
        if let own = ownLaunches[id], now.timeIntervalSince(own) <= Self.ownLaunchWindow {
            ownLaunches[id] = nil
            return
        }
        recordUsage(id)
    }

    private func recordUsage(_ id: String) {
        usage.record(id, at: source.now)
        if let data = try? JSONEncoder().encode(usage) {
            saved(source.saveUsage(data), "usage.json")
        }
    }

    private var fileManager: String {
        ProviderFileManager.resolve(setting: fileManagerSetting, isInstalled: source.isInstalled)
    }

    private func dockSlots(running: [RunningApp]) -> [DockSlot] {
        let fm = fileManager
        return DockLayout.slots(
            pinned: [fm] + source.dockPinned().filter { $0 != fm && $0 != AppleDockPrefs.finder },
            running: running.map(\.bundleID),
            hidden: ProviderFileManager.hidden(for: fm),
            isAvailable: { $0 == fm || self.source.isInstalled($0) }
        )
    }

    private func publishAll() {
        guard isRunning else { return }
        let running = source.runningApps()
        let byID = Dictionary(running.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        let fm = fileManager
        let slots = dockSlots(running: running)
        let pinnedInDock = Set(slots.filter { $0.pinned && $0.bundleID != fm }.map(\.bundleID))
        let context = RecordContext(running: byID, pinnedInDock: pinnedInDock, fileManager: fm)

        publish("all", .list(catalog.map { record($0.bundleID ?? $0.url.path, context) }))
        publish("running", .list(running.map { record($0.bundleID, context) }))
        publish("dock", .list(slots.enumerated().map { index, slot in
            var app = recordValue(slot.bundleID, context)
            let isFileManager = index == 0 && slot.bundleID == fm
            app["section"] = .string(isFileManager ? "file-manager" : slot.pinned ? "pinned" : "running")
            if isFileManager && fm != AppleDockPrefs.finder {
                app["icon"] = .image(Self.fileManagerIcon)
            }
            return .record(app)
        }))
        publish("favorites", .list(favorites.ids.map { record($0, context) }))
        publish("frontmost", running.first(where: \.active).map { record($0.bundleID, context) } ?? .null)
        publish("file-manager", record(fm, context))
        publish("file-managers", .list(ProviderFileManager.choices(setting: fileManagerSetting, isInstalled: source.isInstalled).map { record($0, context) }))
    }

    private struct RecordContext {
        var running: [String: RunningApp]
        var pinnedInDock: Set<String>
        var fileManager: String
    }

    private func currentContext() -> RecordContext {
        let running = source.runningApps()
        let fm = fileManager
        let pinned = Set(dockSlots(running: running).filter { $0.pinned && $0.bundleID != fm }.map(\.bundleID))
        return RecordContext(running: Dictionary(running.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first }), pinnedInDock: pinned, fileManager: fm)
    }

    private func record(_ id: String) -> Value {
        record(id, currentContext())
    }

    private func record(_ id: String, _ context: RecordContext) -> Value {
        .record(recordValue(id, context))
    }

    private func recordValue(_ id: String, _ context: RecordContext) -> Record {
        let app = context.running[id]
        let entry = catalog.first { ($0.bundleID ?? $0.url.path) == id }
        let installed = entry != nil || source.isInstalled(id)
        let favoriteIndex = favorites.ids.firstIndex(of: id)
        return Record([
            ("bundle-id", .string(id)),
            ("name", .string(app?.name ?? entry?.name ?? source.appName(id) ?? id)),
            ("path", ProviderValue.string(app?.path ?? entry?.url.path ?? source.appPath(id))),
            ("icon", .image(ImageRef(source: "app-icon", id: id))),
            ("installed", .bool(installed)),
            ("usage", .number(usage.weight(for: id, at: source.now))),
            ("favorite-index", ProviderValue.number(favoriteIndex)),
            ("running", .bool(app != nil)),
            ("launching", .bool(launching.contains(id) || (app?.launching ?? false))),
            ("active", .bool(app?.active ?? false)),
            ("hidden", .bool(app?.hidden ?? false)),
            ("badge", ProviderValue.string(badges[id])),
            ("windows", .number(Double(app?.windows ?? 0))),
            ("minimized", .number(Double(app?.minimized ?? 0))),
            ("dock-pinned", .bool(context.pinnedInDock.contains(id))),
            ("favorite", .bool(favoriteIndex != nil)),
        ])
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        let action = arguments.action
        guard schema.actions.contains(where: { $0.name == action }) else {
            throw ProviderActionError.unknownAction(action)
        }
        if Self.accessibilityActions.contains(action), !source.accessibilityTrusted {
            warn("\(action) needs the accessibility permission")
            return .null
        }
        switch action {
        case "apps.refresh":
            loadStores()
            scan()
        case "apps.dock-move":
            move(try arguments.string(0), onto: try arguments.string(1))
        case "apps.favorite-move":
            let fromNumber = try arguments.number(0)
            let toNumber = try arguments.number(1)
            guard fromNumber >= 0, fromNumber < Double(favorites.ids.count), toNumber >= 0 else {
                throw ProviderActionError.invalidArgument(action: action, message: "position out of range")
            }
            let from = Int(fromNumber)
            let to = Int(min(toNumber, Double(favorites.ids.count)))
            favorites.move(fromOffsets: IndexSet(integer: from), toOffset: to)
            saveFavorites()
        default:
            try perform(action, app: try Self.appID(arguments), arguments: arguments)
        }
        publishAll()
        return .null
    }

    private func perform(_ action: String, app id: String, arguments: ActionArguments) throws {
        switch action {
        case "apps.click":
            click(id, modifiers: Self.modifiers(arguments))
        case "apps.launch":
            launch(id)
        case "apps.new-window":
            forward(.newWindow, id, action)
        case "apps.cycle-windows":
            let direction = try arguments.string(1)
            guard direction == "up" || direction == "down" else {
                throw ProviderActionError.invalidArgument(action: action, message: "direction must be \"up\" or \"down\"")
            }
            guard source.runningApps().contains(where: { $0.bundleID == id }) else { return }
            if !source.perform(.cycleWindows(up: direction == "up"), on: id) {
                click(id, modifiers: [])
            }
        case "apps.open-files":
            guard case .list(let items) = try arguments.value(1) else {
                throw ProviderActionError.invalidArgument(action: action, message: "files must be a list")
            }
            forward(.openFiles(items.compactMap { if case .string(let path) = $0 { path } else { nil } }), id, action)
        case "apps.show-all-windows":
            forward(.showAllWindows, id, action)
        case "apps.hide":
            forward(.hide, id, action)
        case "apps.unhide":
            forward(.unhide, id, action)
        case "apps.quit":
            forward(.quit, id, action)
        case "apps.force-quit":
            forward(.forceQuit, id, action)
        case "apps.reveal":
            if case .string("finder") = arguments.property("in") ?? (arguments.values.count > 1 ? arguments.values[1] : .null) {
                source.reveal(id, .finder)
            } else {
                source.reveal(id, .fileManager(ProviderFileManager.reveal(fileManager: fileManager, systemFileViewer: source.systemFileViewer)))
            }
        case "apps.dock-pin":
            guard id != fileManager else { return }
            _ = source.placeInDock(id, at: .end)
        case "apps.dock-unpin":
            guard id != fileManager else { return }
            _ = source.removeFromDock(id)
        case "apps.favorite-add":
            if !favorites.add(id) {
                if favorites.isFull { warn("apps.favorite-add: at most \(PinnedList.limit) favorites") }
                return
            }
            saveFavorites()
        case "apps.favorite-remove":
            favorites.remove(id)
            saveFavorites()
        case "apps.run-command":
            let command = try arguments.string(1)
            if source.runMenuCommand(id, command) {
                recordUsage(id)
            } else {
                warn("apps.run-command: \"\(command)\" not found in \(id)")
            }
        default:
            throw ProviderActionError.unknownAction(action)
        }
    }

    private func forward(_ windowAction: AppsWindowAction, _ id: String, _ action: String) {
        if !source.perform(windowAction, on: id) {
            warn("\(action) failed for \(id)")
        }
    }

    private func launch(_ id: String) {
        ownLaunches[id] = source.now
        recordUsage(id)
        if source.runningApps().contains(where: { $0.bundleID == id }) {
            _ = source.launch(id)
            return
        }
        guard source.launch(id) else {
            warn("apps.launch: \(id) could not be started")
            return
        }
        launching.insert(id)
        timers.once("launching-\(id)", after: Self.launchTimeout) { [weak self] in
            guard let self, self.launching.remove(id) != nil else { return }
            self.publishAll()
        }
    }

    private func click(_ id: String, modifiers: Set<String>) {
        let previous = source.runningApps().first(where: \.active)?.bundleID
        var state = source.clickState(id, command: modifiers.contains("cmd"), option: modifiers.contains("alt"))
        if launching.contains(id) {
            state = DockClickState(
                running: state.running, launching: true, frontmost: state.frontmost, hidden: state.hidden,
                windowsOnActiveSpace: state.windowsOnActiveSpace, windowsElsewhere: state.windowsElsewhere,
                minimizedWindows: state.minimizedWindows, hasCoveredWindow: state.hasCoveredWindow,
                command: state.command, option: state.option
            )
        }
        for step in DockClick.actions(for: state) {
            switch step {
            case .launch:
                launch(id)
            case .reveal:
                source.reveal(id, .fileManager(ProviderFileManager.reveal(fileManager: fileManager, systemFileViewer: source.systemFileViewer)))
            default:
                if Self.accessibilityClicks.contains(step), !source.accessibilityTrusted {
                    warn("apps.click needs the accessibility permission to raise windows")
                    _ = source.perform(.click(.activate, previous: previous), on: id)
                    continue
                }
                _ = source.perform(.click(step, previous: previous), on: id)
            }
        }
    }

    private func move(_ from: String, onto target: String) {
        let fm = fileManager
        guard from != fm else { return }
        let slots = dockSlots(running: source.runningApps())
        let ids = slots.map(\.bundleID)
        let position: AppleDockPrefs.Position
        if target == fm {
            position = .start
        } else if let slot = slots.first(where: { $0.bundleID == target }), slot.pinned {
            let fromIndex = ids.firstIndex(of: from) ?? ids.count
            let toIndex = ids.firstIndex(of: target) ?? ids.count
            position = fromIndex < toIndex ? .after(target) : .before(target)
        } else {
            position = .end
        }
        if !source.placeInDock(from, at: position) {
            warn("apps.dock-move: \(from) could not be placed")
        }
    }

    private func saveFavorites() {
        saved(source.saveFavorites(favorites.encoded()), "pinned.json")
    }

    private func saved(_ ok: Bool, _ file: String) {
        if ok {
            warnedSaves.remove(file)
        } else if warnedSaves.insert(file).inserted {
            warn("\(file) could not be saved. The change only applies until the next restart.")
        }
    }

    static func appID(_ arguments: ActionArguments) throws -> String {
        switch try arguments.value(0) {
        case .string(let id) where !id.isEmpty:
            return id
        case .record(let record):
            if case .string(let id) = record["bundle-id"] ?? .null, !id.isEmpty { return id }
        default:
            break
        }
        throw ProviderActionError.invalidArgument(action: arguments.action, message: "expected an app record or a bundle id")
    }

    static func modifiers(_ arguments: ActionArguments) -> Set<String> {
        let value = arguments.property("modifiers") ?? (arguments.values.count > 1 ? arguments.values[1] : .null)
        guard case .list(let items) = value else { return [] }
        var result: Set<String> = []
        for case .string(let name) in items {
            switch name.lowercased() {
            case "cmd", "command": result.insert("cmd")
            case "alt", "option", "opt": result.insert("alt")
            default: result.insert(name.lowercased())
            }
        }
        return result
    }
}

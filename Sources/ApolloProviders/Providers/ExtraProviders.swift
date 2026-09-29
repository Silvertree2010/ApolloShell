import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class ClipboardProvider: BaseProvider {
    static let pollInterval: Double = 0.5

    private let source: any ClipboardSource
    private let now: @MainActor () -> Date
    public private(set) var list = ClipboardList()
    private var lastChange: Int?
    private var poll: ScheduledWork?

    public init(source: any ClipboardSource, clock: any RuntimeClock, now: @escaping @MainActor () -> Date = { Date() }) {
        self.source = source
        self.now = now
        super.init(schema: BuiltinProviderSchemas.schema("clipboard"), clock: clock)
    }

    public var isWatching: Bool { poll != nil }

    override func didStart() {
        if poll == nil {
            lastChange = source.changeCount
            schedule()
        }
        publishHistory()
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        switch arguments.action {
        case "clipboard.remove":
            list.remove(try arguments.string(0))
        case "clipboard.clear":
            list.clear()
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        publishHistory()
        return .null
    }

    private func schedule() {
        poll = clock.schedule(after: Self.pollInterval) { [weak self] in
            guard let self else { return }
            self.check()
            self.schedule()
        }
    }

    func check() {
        let count = source.changeCount
        guard count != lastChange else { return }
        lastChange = count
        let content = source.read()
        guard ClipboardList.records(types: content.types), let text = content.text else { return }
        list.add(text, at: now())
        publishHistory()
    }

    private func publishHistory() {
        guard isRunning else { return }
        publish("history", .list(list.entries.map { entry in
            .record(Record([
                ("text", .string(entry.text)),
                ("preview", .string(ClipboardList.preview(entry.text))),
                ("date", .date(entry.date)),
            ]))
        }))
    }
}

@MainActor
public final class FilesProvider: BaseProvider {
    static let limit = 16
    static let window: Double = 7 * 86_400

    private let source: any RecentFilesSource
    private let now: @MainActor () -> Date
    private var generation = 0

    public init(source: any RecentFilesSource, clock: any RuntimeClock, now: @escaping @MainActor () -> Date = { Date() }) {
        self.source = source
        self.now = now
        super.init(schema: BuiltinProviderSchemas.schema("files"), clock: clock)
    }

    override func didStart() {
        generation += 1
        let generation = generation
        publish("recent", .list([]))
        source.read(since: now().addingTimeInterval(-Self.window), limit: Self.limit) { [weak self] files in
            guard let self, self.isRunning, generation == self.generation else { return }
            self.publish("recent", .list(files.prefix(Self.limit).map(Self.record)))
        }
    }

    override func didStop() {
        generation += 1
    }

    static func record(_ file: RecentFile) -> Value {
        .record(Record([
            ("path", .string(file.path)),
            ("name", .string(file.name)),
            ("icon", .image(ImageRef(source: "app-icon", id: file.path))),
            ("date", .date(file.date)),
        ]))
    }
}

@MainActor
public final class DrivesProvider: BaseProvider {
    private let source: any DrivesSource
    private var last: [DriveInfo]?

    public init(source: any DrivesSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("drives"), clock: clock)
    }

    override func didStart() {
        last = nil
        source.observe { [weak self] in self?.refresh() }
        refresh()
    }

    override func didStop() {
        source.stopObserving()
        last = nil
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        guard arguments.action == "drives.eject" else { throw ProviderActionError.unknownAction(arguments.action) }
        let path = NSString(string: try arguments.string(0)).expandingTildeInPath
        if !source.eject(path) { warn("drives.eject: \(path) could not be ejected") }
        refresh()
        return .null
    }

    private func refresh() {
        guard isRunning else { return }
        let volumes = source.volumes()
        publish("list", .list(volumes.map(Self.record)))
        if let last, last != volumes { emit("drives.changed") }
        last = volumes
    }

    static func record(_ drive: DriveInfo) -> Value {
        .record(Record([
            ("name", .string(drive.name)),
            ("path", .string(drive.path)),
            ("icon", .string(drive.ejectable ? "externaldrive.fill" : "internaldrive.fill")),
            ("ejectable", .bool(drive.ejectable)),
            ("total", .number(drive.total)),
            ("free", .number(drive.free)),
            ("used", .number(drive.used)),
        ]))
    }
}

@MainActor
public final class PhotosProvider: BaseProvider {
    private let source: any PhotosSource
    private var folders: [String] = [PhotoFolder.defaultFolder]
    private var pictures: [String: [String]] = [:]
    private var generation = 0

    public init(source: any PhotosSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("photos"), clock: clock)
    }

    override func didConfigure(_ settings: Record) {
        var next: [String] = []
        switch settings["folders"] ?? .null {
        case .list(let items):
            for case .string(let folder) in items where !next.contains(folder) { next.append(folder) }
        case .string(let folder):
            next = [folder]
        default:
            next = [PhotoFolder.defaultFolder]
        }
        guard next != folders else { return }
        folders = next
        if isRunning { load() }
    }

    override func didStart() {
        load()
    }

    override func didStop() {
        generation += 1
        pictures = [:]
    }

    public func thumbnailData(_ path: String) -> Data? {
        guard pictures.values.contains(where: { $0.contains(path) }) else { return nil }
        return source.thumbnail(path)
    }

    private func load() {
        generation += 1
        let generation = generation
        pictures = pictures.filter { folders.contains($0.key) }
        publishAll()
        for folder in folders {
            source.pictures(in: PhotoFolder.expand(folder)) { [weak self] paths in
                guard let self, self.isRunning, generation == self.generation else { return }
                self.pictures[folder] = paths
                self.publishAll()
            }
        }
    }

    private func publishAll() {
        guard isRunning else { return }
        var record = Record()
        for folder in folders {
            record[folder] = .list((pictures[folder] ?? []).map { path in
                .record(Record([
                    ("path", .string(path)),
                    ("name", .string((path as NSString).lastPathComponent)),
                    ("image", .image(ImageRef(source: "photos", id: path))),
                ]))
            })
        }
        publish("by-folder", .record(record))
    }
}

@MainActor
public final class NetworkInfoProvider: BaseProvider {
    static let publicCache: Double = 600

    private let source: any NetworkInfoSource
    private let now: @MainActor () -> Date
    private var wantsPublic = true
    private var publicAddress: String?
    private var publicFetchedAt: Date?

    public init(source: any NetworkInfoSource, clock: any RuntimeClock, now: @escaping @MainActor () -> Date = { Date() }) {
        self.source = source
        self.now = now
        super.init(schema: BuiltinProviderSchemas.schema("network-info"), clock: clock)
    }

    override func didConfigure(_ settings: Record) {
        let wanted = settings["public-address"] != .bool(false)
        guard wanted != wantsPublic else { return }
        wantsPublic = wanted
        if isRunning { refresh() }
    }

    override func didStart() {
        refresh()
    }

    private func refresh() {
        guard isRunning else { return }
        let link = source.link()
        publish("kind", .string(link.kind.rawValue))
        publish("name", ProviderValue.string(link.name))
        publish("local-address", ProviderValue.string(link.localAddress))
        publish("latency", .null)
        source.measureLatency { [weak self] ms in
            guard let self, self.isRunning else { return }
            self.publish("latency", ProviderValue.number(ms))
        }
        guard wantsPublic else {
            publicAddress = nil
            publish("public-address", .null)
            return
        }
        publish("public-address", ProviderValue.string(publicAddress))
        let date = now()
        if publicFetchedAt.map({ date.timeIntervalSince($0) > Self.publicCache }) ?? true {
            publicFetchedAt = date
            source.fetchPublicAddress { [weak self] address in
                guard let self, let address else { return }
                self.publicAddress = address
                if self.isRunning, self.wantsPublic { self.publish("public-address", .string(address)) }
            }
        }
    }
}

@MainActor
public final class DisplayProvider: BaseProvider {
    static let interval: Double = 2

    private let source: any DisplaySource

    public init(source: any DisplaySource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("display"), clock: clock)
    }

    override func didStart() {
        timers.set("brightness", every: Self.interval, active: true, immediately: true) { [weak self] in
            self?.read()
        }
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        guard arguments.action == "display.set-brightness" else { throw ProviderActionError.unknownAction(arguments.action) }
        let value = min(max(try arguments.number(0), 0), 1)
        guard source.setBrightness(value) else {
            warn("display.set-brightness: no display supports it")
            read()
            return .null
        }
        publish("brightness", .number(value))
        return .null
    }

    private func read() {
        guard isRunning else { return }
        publish("brightness", ProviderValue.number(source.brightness()))
    }
}

@MainActor
public final class WallpaperProvider: BaseProvider {
    private let source: any WallpaperSource
    private var wallpapers: [AppleWallpaper] = []
    private let pick: @MainActor ([AppleWallpaper]) -> AppleWallpaper?

    public init(source: any WallpaperSource, clock: any RuntimeClock, pick: @escaping @MainActor ([AppleWallpaper]) -> AppleWallpaper? = { $0.randomElement() }) {
        self.source = source
        self.pick = pick
        super.init(schema: BuiltinProviderSchemas.schema("wallpaper"), clock: clock)
    }

    override func didStart() {
        wallpapers = source.appleWallpapers()
        publish("apple", .list(wallpapers.map(Self.record)))
        publish("current", ProviderValue.string(source.current()))
    }

    override func didStop() {
        wallpapers = []
    }

    public func thumbnailData(_ path: String) -> Data? {
        guard wallpapers.contains(where: { $0.thumbnail?.path == path }) else { return nil }
        return source.thumbnail(path)
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        switch arguments.action {
        case "wallpaper.set":
            let path = NSString(string: try arguments.string(0)).expandingTildeInPath
            var screen: String?
            if case .string(let id)? = arguments.property("screen"), !id.isEmpty { screen = id }
            apply(path, screen: screen)
        case "wallpaper.random":
            let available = (wallpapers.isEmpty ? source.appleWallpapers() : wallpapers).filter(\.isAvailable)
            guard let choice = pick(available), let url = choice.url else {
                warn("wallpaper.random: no downloaded wallpaper found")
                return .null
            }
            apply(url.path, screen: nil)
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        return .null
    }

    private func apply(_ path: String, screen: String?) {
        let ok = source.set(path, screen: screen)
        if !ok {
            let name = wallpapers.first { $0.url?.path == path }?.name ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            emit("wallpaper.failed", Record([("path", .string(path)), ("name", .string(name))]))
        }
        guard isRunning else { return }
        publish("current", ok && screen == nil ? .string(path) : ProviderValue.string(source.current()))
    }

    static func record(_ wallpaper: AppleWallpaper) -> Value {
        .record(Record([
            ("name", .string(wallpaper.name)),
            ("path", ProviderValue.string(wallpaper.url?.path)),
            ("thumbnail", wallpaper.thumbnail.map { .image(ImageRef(source: "wallpaper", id: $0.path)) } ?? .null),
        ]))
    }
}

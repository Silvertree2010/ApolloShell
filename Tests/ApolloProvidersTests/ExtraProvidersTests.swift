import Foundation
import Testing
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
final class FakeClipboardSource: ClipboardSource {
    var changeCount = 0
    var content = ClipboardContent(types: [], text: nil)

    func copy(_ text: String, types: [String] = ["public.utf8-plain-text"]) {
        changeCount += 1
        content = ClipboardContent(types: types, text: text)
    }

    func read() -> ClipboardContent { content }
}

@MainActor
final class FakeRecentFilesSource: RecentFilesSource {
    var files: [RecentFile] = []
    var reads: [(since: Date, limit: Int)] = []

    func read(since: Date, limit: Int, _ completion: @escaping @MainActor ([RecentFile]) -> Void) {
        reads.append((since, limit))
        completion(files)
    }
}

@MainActor
final class FakeDrivesSource: DrivesSource {
    var drives: [DriveInfo] = [DriveInfo(name: "Macintosh HD", path: "/", total: 1000, free: 250, ejectable: false)]
    var handler: (@MainActor () -> Void)?
    var ejected: [String] = []
    var ejectWorks = true

    func volumes() -> [DriveInfo] { drives }
    func observe(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    func stopObserving() { handler = nil }

    func eject(_ path: String) -> Bool {
        ejected.append(path)
        guard ejectWorks else { return false }
        drives.removeAll { $0.path == path }
        return true
    }
}

@MainActor
final class FakePhotosSource: PhotosSource {
    var folders: [String: [String]] = [:]
    var asked: [String] = []

    func pictures(in folder: String, _ completion: @escaping @MainActor ([String]) -> Void) {
        asked.append(folder)
        completion(folders[folder] ?? [])
    }

    func thumbnail(_ path: String) -> Data? { Data(path.utf8) }
}

@MainActor
final class FakeNetworkInfoSource: NetworkInfoSource {
    var current = NetworkLink(kind: .wifi, name: "Apollo", localAddress: "192.168.1.20")
    var latency: Double? = 12
    var fetches = 0

    func link() -> NetworkLink { current }
    func measureLatency(_ completion: @escaping @MainActor (Double?) -> Void) { completion(latency) }

    func fetchPublicAddress(_ completion: @escaping @MainActor (String?) -> Void) {
        fetches += 1
        completion("203.0.113.7")
    }
}

@MainActor
final class FakeDisplaySource: DisplaySource {
    var value: Double? = 0.4
    var sets: [Double] = []

    func brightness() -> Double? { value }

    func setBrightness(_ value: Double) -> Bool {
        guard self.value != nil else { return false }
        sets.append(value)
        self.value = value
        return true
    }
}

@MainActor
final class FakeWallpaperSource: WallpaperSource {
    var list = [
        AppleWallpaper(name: "Sequoia", url: nil, thumbnail: nil),
        AppleWallpaper(name: "Tahoe", url: URL(fileURLWithPath: "/w/Tahoe.heic"), thumbnail: URL(fileURLWithPath: "/w/.thumbnails/Tahoe.heic")),
    ]
    var currentPath: String? = "/w/Old.heic"
    var sets: [(String, String?)] = []
    var works = true

    func appleWallpapers() -> [AppleWallpaper] { list }
    func current() -> String? { currentPath }

    func set(_ path: String, screen: String?) -> Bool {
        sets.append((path, screen))
        if works { currentPath = path }
        return works
    }

    func thumbnail(_ path: String) -> Data? { Data(path.utf8) }
}

@MainActor
@Suite("Provider aus 0.2.1: timer, clipboard, files, drives, photos, network-info, display, wallpaper, system-extras")
struct ExtraProvidersTests {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    func timer() -> (ProviderHarness, TimerProvider) {
        let harness = ProviderHarness()
        let clock = harness.clock
        let provider = TimerProvider(clock: clock, now: { Self.base.addingTimeInterval(clock.now) })
        harness.register(provider)
        return (harness, provider)
    }

    @Test("timer liefert jedes Registry-Feld und zaehlt jede Sekunde herunter")
    func timerFieldsAndTicks() async throws {
        let (harness, _) = timer()
        harness.demand("timer")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("timer"), strict: false).isEmpty)
        #expect(harness.value("timer", "mode") == .string("standard"))
        #expect(harness.value("timer", "remaining") == .number(600))
        _ = try await harness.perform("timer", "timer.start", [.number(5)])
        #expect(harness.value("timer", "running") == .bool(true))
        #expect(harness.value("timer", "duration") == .number(300))
        harness.advance(2)
        #expect(harness.value("timer", "remaining") == .number(298))
        #expect(harness.value("timer", "elapsed") == .number(2))
        _ = try await harness.perform("timer", "timer.pause")
        harness.advance(10)
        #expect(harness.value("timer", "remaining") == .number(298))
        _ = try await harness.perform("timer", "timer.resume")
        harness.advance(1)
        #expect(harness.value("timer", "remaining") == .number(297))
        _ = try await harness.perform("timer", "timer.reset")
        #expect(harness.value("timer", "running") == .bool(false))
        #expect(harness.value("timer", "remaining") == .number(300))
    }

    @Test("timer.finished kommt auch, wenn nichts die Felder liest, und der Timer steht danach bei null")
    func timerFinishesWithoutDemand() async throws {
        let (harness, provider) = timer()
        let awake = harness.keepAwake("timer")
        _ = try await harness.perform("timer", "timer.start", [.number(1)])
        harness.advance(59)
        #expect(harness.eventNames().isEmpty)
        harness.advance(1)
        #expect(harness.eventNames() == ["timer.finished"])
        #expect(harness.events.first?.fields["mode"] == .string("standard"))
        #expect(harness.events.first?.fields["duration"] == .number(60))
        #expect(!provider.state.isRunning && provider.state.isIdle)
        harness.releaseAwake(awake)
    }

    @Test("timer laeuft ohne jede Nachfrage weiter und hat beim naechsten Oeffnen die richtige Zeit")
    func timerSurvivesStop() async throws {
        let (harness, provider) = timer()
        let token = harness.demand("timer", "remaining")
        _ = try await harness.perform("timer", "timer.start", [.number(10)])
        harness.release(token)
        harness.advance(120)
        harness.demand("timer", "remaining")
        #expect(harness.value("timer", "remaining") == .number(480))
        harness.advance(600)
        #expect(provider.state.isIdle)
        #expect(harness.value("timer", "running") == .bool(false))
    }

    @Test("Pomodoro: Fokus 25 min, dann Kurzpause, die Pause startet erst auf Wunsch")
    func pomodoro() async throws {
        let (harness, _) = timer()
        harness.demand("timer")
        _ = try await harness.perform("timer", "timer.set-mode", [.string("pomodoro")])
        #expect(harness.value("timer", "duration") == .number(1500))
        #expect(harness.value("timer", "phase") == .string("focus"))
        #expect(harness.value("timer", "round") == .number(1))
        _ = try await harness.perform("timer", "timer.start")
        harness.advance(1500)
        #expect(harness.events.last?.name == "timer.finished")
        #expect(harness.events.last?.fields["phase"] == .string("focus"))
        #expect(harness.value("timer", "phase") == .string("short-break"))
        #expect(harness.value("timer", "running") == .bool(false))
        #expect(harness.value("timer", "duration") == .number(300))
    }

    @Test("set-mode: gleicher Modus waehrend er laeuft bleibt, anderer Modus faengt neu an, falsche Werte werfen")
    func setMode() async throws {
        let (harness, provider) = timer()
        harness.demand("timer")
        _ = try await harness.perform("timer", "timer.start")
        harness.advance(5)
        _ = try await harness.perform("timer", "timer.set-mode", [.string("standard"), .number(20)])
        #expect(provider.state.isRunning && provider.state.length == 600)
        _ = try await harness.perform("timer", "timer.set-mode", [.string("stopwatch")])
        #expect(provider.state.mode == .stopwatch && provider.state.isIdle)
        #expect(harness.value("timer", "remaining") == .null)
        await #expect(throws: ProviderActionError.self) { try await harness.perform("timer", "timer.set-mode", [.string("egg")]) }
        await #expect(throws: ProviderActionError.self) { try await harness.perform("timer", "timer.start", [.number(0)]) }
    }

    @Test("clipboard: merkt Text, laesst Geheimes aus, liest weiter auch ohne Nachfrage")
    func clipboard() async throws {
        let harness = ProviderHarness()
        let source = FakeClipboardSource()
        let clock = harness.clock
        let provider = ClipboardProvider(source: source, clock: clock, now: { Self.base.addingTimeInterval(clock.now) })
        harness.register(provider)
        let token = harness.demand("clipboard", "history")
        source.copy("hello")
        harness.advance(0.5)
        source.copy("secret", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
        harness.advance(0.5)
        guard case .list(let items) = harness.value("clipboard", "history") else { Issue.record("no list"); return }
        #expect(items.count == 1)
        guard case .record(let first) = items[0] else { Issue.record("no record"); return }
        #expect(first["text"] == .string("hello"))
        #expect(first["date"] == .date(Self.base.addingTimeInterval(0.5)))
        harness.release(token)
        source.copy("while closed")
        harness.advance(1)
        #expect(provider.isWatching)
        harness.demand("clipboard", "history")
        #expect(provider.list.items == ["while closed", "hello"])
        _ = try await harness.perform("clipboard", "clipboard.remove", [.string("hello")])
        #expect(provider.list.items == ["while closed"])
        _ = try await harness.perform("clipboard", "clipboard.clear")
        #expect(harness.value("clipboard", "history") == .list([]))
    }

    @Test("files.recent: letzte 7 Tage, hoechstens 16, mit Datei-Symbol")
    func recentFiles() {
        let harness = ProviderHarness()
        let source = FakeRecentFilesSource()
        source.files = (0..<20).map { RecentFile(path: "/Users/a/f\($0).txt", name: "f\($0).txt", date: Self.base) }
        harness.register(FilesProvider(source: source, clock: harness.clock, now: { Self.base }))
        harness.demand("files", "recent")
        #expect(source.reads.first?.since == Self.base.addingTimeInterval(-7 * 86_400))
        guard case .list(let items) = harness.value("files", "recent") else { Issue.record("no list"); return }
        #expect(items.count == 16)
        guard case .record(let first) = items[0] else { return }
        #expect(first["icon"] == .image(ImageRef(source: "app-icon", id: "/Users/a/f0.txt")))
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("files")).isEmpty)
    }

    @Test("drives: Liste mit Belegung, drives.changed beim Ein- und Aushaengen, Auswerfen")
    func drives() async throws {
        let harness = ProviderHarness()
        let source = FakeDrivesSource()
        harness.register(DrivesProvider(source: source, clock: harness.clock))
        harness.demand("drives", "list")
        #expect(harness.eventNames().isEmpty)
        source.drives.append(DriveInfo(name: "Stick", path: "/Volumes/Stick", total: 100, free: 60, ejectable: true))
        source.handler?()
        #expect(harness.eventNames() == ["drives.changed"])
        guard case .list(let items) = harness.value("drives", "list"), case .record(let stick) = items[1] else { Issue.record("no list"); return }
        #expect(stick["icon"] == .string("externaldrive.fill"))
        #expect(stick["used"] == .number(0.4))
        _ = try await harness.perform("drives", "drives.eject", [.string("/Volumes/Stick")])
        #expect(source.ejected == ["/Volumes/Stick"])
        #expect(harness.eventNames() == ["drives.changed", "drives.changed"])
        source.ejectWorks = false
        _ = try await harness.perform("drives", "drives.eject", [.string("/")])
        #expect(harness.warnings.count == 1)
    }

    @Test("photos: by-folder je Ordner aus folders=, Vorschau nur fuer gelistete Bilder")
    func photos() {
        let harness = ProviderHarness()
        let source = FakePhotosSource()
        source.folders["/p/a"] = ["/p/a/1.jpg", "/p/a/2.png"]
        let provider = PhotosProvider(source: source, clock: harness.clock)
        harness.register(provider)
        harness.host.configure("photos", Record([("folders", .list([.string("/p/a"), .string("/p/b")]))]))
        harness.demand("photos", "by-folder")
        guard case .record(let byFolder) = harness.value("photos", "by-folder"), case .list(let pictures)? = byFolder["/p/a"] else { Issue.record("no record"); return }
        #expect(pictures.count == 2)
        #expect(byFolder["/p/b"] == .list([]))
        #expect(provider.thumbnailData("/p/a/1.jpg") != nil)
        #expect(provider.thumbnailData("/etc/secret.png") == nil)
    }

    @Test("network-info: Art, Adressen, Latenz; oeffentliche Adresse nur auf Wunsch und hoechstens alle 10 Minuten")
    func networkInfo() {
        let harness = ProviderHarness()
        let source = FakeNetworkInfoSource()
        let clock = harness.clock
        harness.register(NetworkInfoProvider(source: source, clock: clock, now: { Self.base.addingTimeInterval(clock.now) }))
        let token = harness.demand("network-info")
        #expect(harness.value("network-info", "kind") == .string("wifi"))
        #expect(harness.value("network-info", "latency") == .number(12))
        #expect(harness.value("network-info", "public-address") == .string("203.0.113.7"))
        harness.release(token)
        harness.demand("network-info")
        #expect(source.fetches == 1)
        harness.host.configure("network-info", Record([("public-address", .bool(false))]))
        harness.flush()
        #expect(harness.value("network-info", "public-address") == .null)
        #expect(source.fetches == 1)
    }

    @Test("display: Helligkeit oder null, set-brightness klemmt auf 0 bis 1, ohne Display eine Warnung")
    func display() async throws {
        let harness = ProviderHarness()
        let source = FakeDisplaySource()
        harness.register(DisplayProvider(source: source, clock: harness.clock))
        harness.demand("display", "brightness")
        #expect(harness.value("display", "brightness") == .number(0.4))
        _ = try await harness.perform("display", "display.set-brightness", [.number(1.5)])
        #expect(source.sets == [1])
        source.value = nil
        harness.advance(2)
        #expect(harness.value("display", "brightness") == .null)
        _ = try await harness.perform("display", "display.set-brightness", [.number(0.5)])
        #expect(harness.warnings.count == 1)
    }

    @Test("wallpaper: Apples Bilder mit Vorschau, set und random, Fehler als wallpaper.failed")
    func wallpaper() async throws {
        let harness = ProviderHarness()
        let source = FakeWallpaperSource()
        let provider = WallpaperProvider(source: source, clock: harness.clock, pick: { $0.first })
        harness.register(provider)
        harness.demand("wallpaper")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("wallpaper"), strict: false).isEmpty)
        guard case .list(let items) = harness.value("wallpaper", "apple"), case .record(let sequoia) = items[0] else { Issue.record("no list"); return }
        #expect(sequoia["path"] == .null)
        #expect(provider.thumbnailData("/w/.thumbnails/Tahoe.heic") != nil)
        #expect(provider.thumbnailData("/etc/passwd") == nil)
        _ = try await harness.perform("wallpaper", "wallpaper.random")
        #expect(source.sets.map(\.0) == ["/w/Tahoe.heic"])
        #expect(harness.value("wallpaper", "current") == .string("/w/Tahoe.heic"))
        source.works = false
        _ = try await harness.perform("wallpaper", "wallpaper.set", [.string("/w/x.png")], properties: Record([("screen", .string("s1"))]))
        #expect(source.sets.last?.1 == "s1")
        #expect(harness.eventNames() == ["wallpaper.failed"])
    }

    @Test("system-extras: versteckte Dateien mit Zustand, Papierkorb, Mission Control, Launchpad, AirDrop")
    func systemExtras() async throws {
        let harness = ProviderHarness()
        let source = FakeSystemSource()
        harness.register(SystemProvider(source: source, clock: harness.clock))
        harness.demand("system", "hidden-files")
        #expect(harness.value("system", "hidden-files") == .bool(false))
        _ = try await harness.perform("system", "system.toggle-hidden-files")
        #expect(source.hiddenFilesSets == [true])
        #expect(harness.value("system", "hidden-files") == .bool(true))
        for action in ["system.empty-trash", "system.mission-control", "system.launchpad", "system.airdrop"] {
            _ = try await harness.perform("system", action)
        }
        #expect(source.commands == [.emptyTrash, .missionControl, .launchpad, .airDrop])
        source.hiddenFiles = nil
        _ = try await harness.perform("system", "system.toggle-hidden-files")
        #expect(source.hiddenFilesSets == [true])
        #expect(harness.warnings.count == 1)
    }

    @Test("battery.set-low-power schaltet und liest den Zustand nach")
    func lowPower() async throws {
        let harness = ProviderHarness()
        let source = FakeBatterySource(BatteryReading(level: 80, charging: false, onAC: false))
        harness.register(BatteryProvider(source: source, clock: harness.clock))
        harness.demand("battery", "low-power-mode")
        _ = try await harness.perform("battery", "battery.set-low-power", [.bool(true)])
        #expect(source.lowPowerSets == [true])
        harness.advance(1)
        #expect(harness.value("battery", "low-power-mode") == .bool(true))
    }
}

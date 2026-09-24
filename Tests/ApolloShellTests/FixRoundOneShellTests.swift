import Testing
import AppKit
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloShell

@MainActor
@Suite("Fix-Runde 1: Shell, Tasten, Timer")
struct ShellFixRoundOneTests {
    @Test("Befund 15: Timer laufen auch im Event-Tracking-Modus und haben Toleranz")
    func commonModeTimer() {
        _ = NSApplication.shared
        let tracking = CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString)
        let timer = ShellTimer.repeating(10) {}
        #expect(CFRunLoopContainsTimer(CFRunLoopGetMain(), timer, tracking))
        #expect(CFRunLoopContainsTimer(CFRunLoopGetMain(), timer, .defaultMode))
        #expect(timer.tolerance > 0)
        timer.invalidate()
    }

    @Test("Befund 12: verlorenes Loslassen beendet die Wiederholung, belegtes Kürzel wird erneut versucht")
    func repeatAndRetry() throws {
        var scheduled: [@MainActor () -> Void] = []
        let repeater = KeyRepeater(timing: { .init(delay: 0.3, interval: 0.05) }, schedule: { _, work in
            scheduled.append(work)
            return DispatchWorkItem {}
        })
        let keys = try KeysFixture("""
        popup "menu" { row {} }
        bind "ctrl+alt+up" id="louder" repeat=#true { toggle "menu" }
        """, repeater: repeater)
        var down = true
        keys.keys.keyIsDown = { _ in down }
        keys.registrar.press("ctrl+alt+up")
        scheduled.removeFirst()()
        #expect(keys.triggered.count == 2)
        down = false
        scheduled.removeFirst()()
        #expect(keys.triggered.count == 2)
        #expect(repeater.active.isEmpty)
        #expect(scheduled.isEmpty)

        let taken = try KeysFixture("""
        popup "menu" { row {} }
        bind "ctrl+alt+k" id="menu" { toggle "menu" }
        """)
        taken.registrar.taken = ["ctrl+alt+k"]
        taken.keys.apply([])
        taken.keys.apply(taken.fixture.ir?.binds ?? [])
        #expect(taken.keys.hasFailures)
        taken.registrar.taken = []
        taken.keys.retryFailed()
        #expect(!taken.keys.hasFailures)
        #expect(taken.registrar.registered.last == "ctrl+alt+k")
        #expect(taken.published.first.flatMap { if case .record(let record) = $0 { record["ok"] } else { nil } } == .bool(true))
    }

    @Test("Befund 10: Wache beobachtet den nächsten vorhandenen Ordner und folgt neuen Dateien")
    func watchFollows() async throws {
        #expect(FolderWatcher.existingAncestor("/private/tmp/apollo-\(UUID().uuidString)/configs/x") == "/private/tmp")
        let harness = try ShellHarness("popup \"menu\" { row {} }")
        try await harness.start()
        harness.shell.watch()
        let before = harness.shell.watchedPaths
        #expect(!before.isEmpty)
        #expect(before.allSatisfy { FileManager.default.fileExists(atPath: $0) })
        let extra = harness.config.appendingPathComponent("parts")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        try "popup \"more\" { row {} }\n".write(to: extra.appendingPathComponent("more.kdl"), atomically: true, encoding: .utf8)
        try harness.write("include \"parts/more.kdl\"\npopup \"menu\" { row {} }")
        await harness.shell.reload()?.value
        #expect(harness.shell.watchedPaths.contains(extra.standardizedFileURL.path))
        let location = harness.shell.location
        try harness.write("popup \"menu\" { row {")
        await harness.shell.reload()?.value
        #expect(harness.shell.location == location)
        harness.shell.shutdown()
    }

    @Test("Befund 11: Signal und willTerminate lösen shutdown aus, einmal; restart startet neu")
    func termination() async throws {
        let queue = DispatchQueue(label: "termination-test")
        let center = NotificationCenter()
        let seen = LockedList()
        let watch = TerminationWatch(signals: [SIGUSR2], queue: queue, center: center) { number in
            seen.append(number ?? 0)
        }
        kill(getpid(), SIGUSR2)
        for _ in 0..<200 where seen.values.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        #expect(seen.values == [SIGUSR2, 0])
        watch.cancel()
        signal(SIGUSR2, SIG_DFL)

        let harness = try ShellHarness("popup \"menu\" { row {} }")
        try await harness.start()
        var relaunched: [Int32] = []
        var terminated = 0
        harness.shell.relaunch = { _, pid in relaunched.append(pid) }
        harness.shell.terminateApp = { terminated += 1 }
        harness.shell.perform(.restart)
        harness.shell.shutdown()
        #expect(harness.shell.shutdowns == 1)
        #expect(relaunched == [ProcessInfo.processInfo.processIdentifier])
        #expect(terminated == 1)
    }

    @Test("Befund 13: Hell/Dunkel stylt neu, Tastaturbelegung wertet chord neu aus")
    func environmentChanges() async throws {
        let harness = try ShellHarness("popup \"menu\" { row {} }")
        harness.shell.isDark = { false }
        try await harness.start()
        let restyles = harness.shell.host.stats.restyles
        harness.shell.appearanceChanged()
        #expect(harness.shell.host.stats.restyles == restyles)
        harness.shell.isDark = { true }
        harness.shell.appearanceChanged()
        #expect(harness.shell.host.stats.restyles == restyles + 1)
        harness.shell.appearanceChanged()
        #expect(harness.shell.host.stats.restyles == restyles + 1)

        harness.shell.keyNames.keyName = { _ in "Q" }
        let assembly = try #require(harness.shell.assembly)
        var shown: [Value] = []
        let handle = assembly.bindings.bind(try harness.shell.compiled("'cmd+q' | chord"), scope: LocalScope(), active: true) { shown.append($0) }
        harness.settle()
        harness.shell.keyNames.keyName = { _ in "Z" }
        harness.shell.keyboardLayoutChanged()
        harness.settle()
        handle.cancel()
        #expect(shown.count == 2)
        #expect(shown.last.flatMap { if case .string(let text) = $0 { text.contains("Z") } else { nil } } == true)
        harness.shell.shutdown()
    }

    @Test("Befund 4: osd.show zeigt die OSD und startet den Timer neu")
    func osdShow() async throws {
        let harness = try ShellHarness("osd \"volume\" timeout=\"1s\" { row {} }")
        try await harness.start()
        var timers: [DispatchWorkItem] = []
        harness.shell.host.scheduleTimer = { _, work in timers.append(work) }
        _ = try await harness.shell.runActions("osd.show \"volume\"")
        #expect(harness.runtime.surface("volume", screenKey: ShellHarness.a.key)?.isOpen == true)
        #expect(timers.count == 1)
        _ = try await harness.shell.runActions("osd.show \"volume\"")
        #expect(timers.count == 2)
        #expect(timers.first?.isCancelled == true)
        #expect(timers.filter { !$0.isCancelled }.count == 1)
        #expect(harness.shell.overlay.problems.isEmpty)
        harness.shell.shutdown()
    }

    @Test("Befund 4: window-Hauptmenü mit ⌘W und Bearbeiten-Kürzeln, ohne ⌘Q")
    func mainMenu() {
        let menu = WindowMainMenu.make()
        let items = menu.items.flatMap { $0.submenu?.items ?? [] }
        func action(_ key: String, _ mask: NSEvent.ModifierFlags = .command) -> Selector? {
            items.first { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == mask }?.action
        }
        #expect(action("w") == #selector(NSWindow.performClose(_:)))
        #expect(action("c") == #selector(NSText.copy(_:)))
        #expect(action("v") == #selector(NSText.paste(_:)))
        #expect(action("x") == #selector(NSText.cut(_:)))
        #expect(action("a") == #selector(NSText.selectAll(_:)))
        #expect(action("z") == Selector(("undo:")))
        #expect(action("z", [.command, .shift]) == Selector(("redo:")))
        #expect(!items.contains { $0.keyEquivalent == "q" })
    }
}

final class LockedList: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Int32] = []
    func append(_ value: Int32) { lock.withLock { items.append(value) } }
    var values: [Int32] { lock.withLock { items } }
}

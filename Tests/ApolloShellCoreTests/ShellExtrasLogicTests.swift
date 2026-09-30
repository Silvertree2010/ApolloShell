import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Timer, Zwischenablage, Rechner, Hintergrundbilder")
struct ShellExtrasLogicTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("Timer rechnet aus runningSince, Pause bankt, Ende stoppt bei null")
    func timerCounts() {
        var state = ShellTimerState()
        #expect(state.mode == .standard && state.isIdle && state.target == 600)
        state.start(at: start)
        #expect(state.remaining(at: start.addingTimeInterval(100)) == 500)
        state.pause(at: start.addingTimeInterval(100))
        #expect(!state.isIdle && !state.isRunning)
        state.start(at: start.addingTimeInterval(1000))
        #expect(state.elapsed(at: start.addingTimeInterval(1500)) == 600)
        #expect(state.isFinished(at: start.addingTimeInterval(1500)))
        state.finish()
        #expect(state.isIdle && state.mode == .standard)
    }

    @Test("Pomodoro: Fokus, Kurzpause, jede vierte Pause lang, Runde 1 bis 4")
    func pomodoroPhases() {
        var state = ShellTimerState()
        state.set(mode: .pomodoro)
        var phases: [ShellTimerState.Phase] = []
        var rounds: [Int] = []
        for _ in 0..<8 {
            phases.append(state.phase)
            rounds.append(state.round)
            state.finish()
        }
        #expect(phases == [.focus, .shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak])
        #expect(rounds == [1, 1, 2, 2, 3, 3, 4, 4])
        #expect(state.phase == .focus && state.round == 1)
        #expect(ShellTimerState.Phase.shortBreak.rawValue == "short-break")
    }

    @Test("Stoppuhr hat kein Ziel, Text rundet beim Herunterzaehlen auf")
    func stopwatchAndText() {
        var state = ShellTimerState()
        state.set(mode: .stopwatch)
        #expect(state.target == nil && state.remaining(at: start) == nil)
        #expect(ShellTimerState.text(244.2, countingDown: true) == "4:05")
        #expect(ShellTimerState.text(3723, countingDown: false) == "1:02:03")
    }

    @Test("Zwischenablage: nur Text, geheime Typen nicht, hoechstens 20, Doppeltes nach oben")
    func clipboardList() {
        #expect(!ClipboardList.records(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(ClipboardList.records(types: ["public.utf8-plain-text"]))
        var list = ClipboardList()
        for index in 0..<25 { list.add("item \(index)", at: start.addingTimeInterval(Double(index))) }
        #expect(list.entries.count == 20)
        #expect(list.items.first == "item 24")
        list.add("item 10", at: start.addingTimeInterval(100))
        #expect(list.items.first == "item 10" && list.entries.first?.date == start.addingTimeInterval(100))
        #expect(list.entries.count == 20)
        list.add("   \n")
        #expect(list.entries.count == 20)
        list.remove("item 10")
        #expect(!list.items.contains("item 10"))
        #expect(ClipboardList.preview("a\n  b\tc") == "a b c")
        list.clear()
        #expect(list.entries.isEmpty)
    }

    @Test("Rechner wie LauncherCalculator im alten 0.2")
    func calculator() {
        #expect(LauncherCalculator.evaluate("2*(3+4)") == 14)
        #expect(LauncherCalculator.evaluate("pi").map { abs($0 - .pi) < 1e-12 } == true)
        #expect(LauncherCalculator.evaluate("round(2.5)+floor(1.9)+ceil(1.1)") == 6)
        #expect(LauncherCalculator.evaluate("log(1000)") == 3)
        #expect(LauncherCalculator.evaluate("2*(") == nil)
        #expect(LauncherCalculator.format(0.5) == "0.5")
        #expect(LauncherCalculator.format(1e21) == "1E+021")
    }

    @Test("Hintergrundbilder: madesktop nur mit Download setzbar, Vorschau aus .thumbnails, Farben dabei")
    func wallpapers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wallpapers-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Desktop Pictures")
        let downloads = root.appendingPathComponent("downloads")
        let manager = FileManager.default
        try manager.createDirectory(at: folder.appendingPathComponent(".thumbnails"), withIntermediateDirectories: true)
        try manager.createDirectory(at: folder.appendingPathComponent("Solid Colors"), withIntermediateDirectories: true)
        try manager.createDirectory(at: downloads, withIntermediateDirectories: true)
        for name in ["Sonoma.heic", "Tahoe.madesktop", "Sequoia.madesktop", ".thumbnails/Tahoe.heic", "Solid Colors/Blue.png", "Sequoia.txt"] {
            manager.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data())
        }
        manager.createFile(atPath: downloads.appendingPathComponent("Tahoe.heic").path, contents: Data())
        defer { try? manager.removeItem(at: root) }
        let all = AppleWallpaper.all(folder: folder, downloads: downloads)
        #expect(all.map(\.name) == ["Blue", "Sequoia", "Sonoma", "Tahoe"])
        let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
        #expect(byName["Sequoia"]?.isAvailable == false && byName["Sequoia"]?.thumbnail == nil)
        #expect(byName["Tahoe"]?.url?.lastPathComponent == "Tahoe.heic" && byName["Tahoe"]?.thumbnail?.path.contains(".thumbnails") == true)
        #expect(byName["Sonoma"]?.url == byName["Sonoma"]?.thumbnail)
    }

    @Test("Fotoordner: nur Bilder der ersten Ebene, sortiert, Zugehoerigkeit genau")
    func photoFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("photos-\(UUID().uuidString)")
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        for name in ["b.JPG", "a.png", "notes.txt", ".hidden.png", "sub/c.png"] {
            manager.createFile(atPath: root.appendingPathComponent(name).path, contents: Data())
        }
        defer { try? manager.removeItem(at: root) }
        #expect(PhotoFolder.pictures(in: root.path).map(\.lastPathComponent) == ["a.png", "b.JPG"])
        #expect(PhotoFolder.contains(root.appendingPathComponent("a.png").path, folders: [root.path]))
        #expect(!PhotoFolder.contains(root.appendingPathComponent("sub/c.png").path, folders: [root.path]))
        #expect(!PhotoFolder.contains(root.appendingPathComponent("../x.png").path, folders: [root.path]))
        #expect(!PhotoFolder.contains(root.appendingPathComponent("notes.txt").path, folders: [root.path]))
        #expect(PhotoFolder.expand(nil) == NSString(string: "~/Pictures").expandingTildeInPath)
    }
}

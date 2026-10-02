import Testing
import AppKit
import SwiftUI
import ApolloBase
import ApolloConfig
import ApolloStyle
import ApolloRuntime
import ApolloProviders
@testable import ApolloShell

@MainActor
final class FakeWindow: HostWindow {
    var frame: CGRect = .zero
    var isShown = false
    var fittingSize = CGSize(width: 100, height: 50)
    var watching = false
    func watchFitting(_ on: Bool) { watching = on }
    var onCloseRequest: (@MainActor () -> Void)?
    var onKey: (@MainActor (String) -> Bool)?
    var onResize: (@MainActor () -> Void)?
    var onOcclusion: (@MainActor (Bool) -> Void)?
    var onFittingChange: (@MainActor () -> Void)?
    var windowNumber = 1
    var spec: SurfaceWindowSpec
    var level: NSWindow.Level
    var contentSets = 0
    var calls: [String] = []
    var frameSets = 0
    var closed = false
    var hides = 0
    var shows = 0
    var animations: [(opening: Bool, animator: String)] = []
    var animatorIDs: [ObjectIdentifier] = []
    var focuses: [Bool] = []
    var glides: [CGRect] = []
    var minSize: CGSize = .zero
    var ignoresMouse: Bool?
    var restorable: CGRect?
    var content: AnyView?
    var pending: [@MainActor () -> Void] = []

    init(spec: SurfaceWindowSpec) {
        self.spec = spec
        level = spec.level
    }

    func setIgnoresMouse(_ ignores: Bool) { ignoresMouse = ignores }

    func apply(_ spec: SurfaceWindowSpec) {
        self.spec = spec
        level = spec.level
    }

    func setLevel(_ level: NSWindow.Level) { self.level = level }

    func setFrame(_ frame: CGRect, glide: Bool) {
        guard frame != self.frame else { return }
        self.frame = frame
        frameSets += 1
        calls.append("frame")
        if glide { glides.append(frame) }
    }

    func setContent(_ view: AnyView, frame: CGRect, glide: Bool) {
        contentSets += 1
        content = view
        calls.append("content+frame")
        if frame != self.frame {
            self.frame = frame
            frameSets += 1
            if glide { glides.append(frame) }
        }
    }

    func setMinSize(_ size: CGSize) { minSize = size }

    func restoreFrame() -> Bool {
        guard let restorable else { return false }
        frame = restorable
        return true
    }

    func setContent(_ view: AnyView) {
        contentSets += 1
        content = view
        calls.append("content")
    }
    func show(focus: Bool) {
        isShown = true
        shows += 1
    }

    func hide() {
        isShown = false
        hides += 1
    }

    func animate(opening: Bool, focus: Bool, animator: any SurfaceAnimator, geometry: MotionGeometry, scrim: Double?, screen: CGRect, completion: @escaping @MainActor () -> Void) {
        animations.append((opening, animator.name))
        animatorIDs.append(ObjectIdentifier(animator))
        focuses.append(focus)
        if opening { isShown = true }
        pending.append { [weak self] in
            if !opening { self?.isShown = false }
            completion()
        }
    }

    func finishAnimations() {
        let work = pending
        pending = []
        work.forEach { $0() }
    }

    func close() {
        closed = true
        isShown = false
    }
}

@MainActor
final class FakeFactory: HostWindowFactory {
    var made: [FakeWindow] = []
    var auxiliary: [FakeWindow] = []
    var restorable: CGRect?

    func make(spec: SurfaceWindowSpec, content: AnyView) -> any HostWindow {
        let window = FakeWindow(spec: spec)
        window.content = content
        window.restorable = restorable
        made.append(window)
        return window
    }

    func makeAuxiliary(content: AnyView) -> any HostWindow {
        let window = FakeWindow(spec: SurfaceWindowSpec(kind: "overlay", property: { _ in .null }))
        window.content = content
        auxiliary.append(window)
        return window
    }
}

@MainActor
final class RuntimeLink: WindowHostLink {
    weak var runtime: ShellRuntime?
    var finished: [String] = []
    var keys: [String] = []

    func close(_ surfaceID: String, screenKey: String) { runtime?.close(surfaceID, screenKey: screenKey) }

    func surfaceDidFinishOpening(id: String, screenKey: String) {
        runtime?.surfaceDidFinishOpening(id: id, screenKey: screenKey)
    }

    func surfaceDidFinishClosing(id: String, screenKey: String) {
        finished.append(id)
        runtime?.surfaceDidFinishClosing(id: id, screenKey: screenKey)
    }

    func keyPressed(_ chord: String, surfaceID: String, screenKey: String) -> Bool {
        keys.append(chord)
        return false
    }
}

@MainActor
final class ManualTicker: FrameTicker {
    var tick: (@MainActor (TimeInterval) -> Bool)?
    var stops = 0
    func start(_ tick: @escaping @MainActor (TimeInterval) -> Bool) { self.tick = tick }
    func stop() {
        stops += 1
        tick = nil
    }
}

@MainActor
final class HostFixture {
    let factory = FakeFactory()
    let host: WindowHost
    let scheduler = ManualFlushScheduler()
    let assembly: ShellAssembly
    let link = RuntimeLink()
    let folder: URL
    var ir: ConfigIR?
    static let screen = ScreenGeometry(key: "Test 1440x900", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: CGRect(x: 0, y: 0, width: 1440, height: 870))

    var deferred: [@MainActor () -> Void] = []

    init(_ shell: String, css: String = "") throws {
        host = WindowHost(factory: factory)
        var sink: HostFixture?
        host.later = { work in sink?.deferred.append(work) }
        assembly = ShellAssembly(host: host, scheduler: scheduler, filterContext: ShellAssembly.fixedContext(now: Date(timeIntervalSince1970: 1_790_235_660)))
        link.runtime = assembly.runtime
        host.link = link
        host.screens = [Self.screen.key: Self.screen]
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("host-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        sink = self
        try write(shell, css: css)
        let result = PackageResources.load(folder, id: "host")
        ir = result.ir
        host.context = context(result.ir)
        #expect(assembly.runtime.applyLoaded(result, persisted: [:], screens: [Self.screen.key], shell: Record()))
        flush()
    }

    func write(_ shell: String, css: String) throws {
        try ("style \"style.css\"\n" + shell).write(to: folder.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        try css.write(to: folder.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
    }

    func context(_ ir: ConfigIR?) -> RenderContext {
        let sheets = ir.map { StyleSheets.load($0).0 } ?? []
        return RenderContext(styles: StyleResolver(sheets: sheets, environment: StyleSheets.environment(dark: false)), icons: FixtureAppIcons(), trigger: { _, _, _ in })
    }

    @discardableResult
    func reload(_ shell: String, css: String = "") throws -> ConfigLoadResult {
        try write(shell, css: css)
        let result = PackageResources.load(folder, id: "host")
        ir = result.ir ?? ir
        #expect(assembly.runtime.applyLoaded(result, persisted: [:], screens: [Self.screen.key], shell: Record()))
        host.restyle(context(result.ir))
        flush()
        return result
    }

    func flush() {
        for _ in 0..<10 {
            scheduler.runPending()
            let work = deferred
            deferred = []
            work.forEach { $0() }
        }
    }

    func window(_ id: String) -> FakeWindow? {
        host.controllers[SurfaceHost.key(id, Self.screen.key)]?.window as? FakeWindow
    }
}

@MainActor
@Suite("Fensterarten und Properties")
struct SurfaceWindowSpecTests {
    func spec(_ kind: String, _ values: [String: Value] = [:]) -> SurfaceWindowSpec {
        SurfaceWindowSpec(kind: kind, property: { values[$0] ?? .null })
    }

    @Test("Nexus-Panel schliesst per globalem Esc und nimmt keine Tastatur")
    func nexusGlobalEscape() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/configs/apolloshell-default/nexus.kdl")
        let text = try String(contentsOf: url, encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first { $0.hasPrefix("popup \"nexus\"") })
        #expect(line.contains("close-on=\"outside-click global-escape\""))
        #expect(line.contains("keyboard=#false"))
    }

    @Test("Vorgaben je Art nach blocks.md 2.8 und 2.9")
    func defaults() {
        #expect(spec("panel").level == .floating)
        #expect(spec("panel").hideInFullscreen)
        #expect(!spec("panel").keyboard)
        #expect(spec("popup").level == .popUpMenu)
        #expect(spec("popup").keyboard)
        #expect(spec("popup").closeOn == [.outsideClick, .escape, .focusLoss])
        #expect(spec("popup").behavior == [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary])
        #expect(spec("toast").behavior == [.canJoinAllSpaces, .transient, .ignoresCycle])
        #expect(spec("overlay").level.rawValue == NSWindow.Level.popUpMenu.rawValue + 2)
        #expect(spec("overlay").clickThrough == .on)
        #expect(!spec("osd", ["keyboard": .bool(true)]).keyboard)
        #expect(spec("osd").timeout == 2)
        #expect(spec("window").level == .normal)
        #expect(spec("window").behavior == [.moveToActiveSpace])
        #expect(spec("window").styleMask == [.titled, .closable, .resizable])
        #expect(!spec("popup").hideInFullscreen)
    }

    @Test("Properties: Ebene, scrim, close-on, click-through, reserve, motion")
    func properties() {
        #expect(spec("panel", ["layer": .string("desktop")]).level.rawValue == Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        #expect(spec("popup", ["scrim": .number(0.3)]).level.rawValue == NSWindow.Level.popUpMenu.rawValue + 1)
        #expect(spec("popup", ["close-on": .string("escape mouse-leave")]).closeOn == [.escape, .mouseLeave])
        #expect(spec("popup", ["close-on": .list([.string("outside-click")])]).closeOn == [.outsideClick])
        #expect(spec("popup", ["close-on": .string("outside-click global-escape")]).closeOn == [.outsideClick, .globalEscape])
        #expect(spec("toast", ["click-through": .string("auto")]).clickThrough == .auto)
        #expect(spec("panel", ["reserve": .bool(true)]).reserve)
        #expect(!spec("popup", ["reserve": .bool(true)]).reserve)
        #expect(spec("popup", ["anchor": .string("top")]).motion == "slide")
        #expect(spec("popup").motion == "fade")
        #expect(spec("popup", ["motion": .string("grow")]).motion == "grow")
        #expect(spec("osd", ["timeout": .string("1500ms")]).timeout == 1.5)
        #expect(spec("window", ["resizable": .bool(false), "title": .string("Hi")]).styleMask == [.titled, .closable])
        #expect(spec("popup", ["fullscreen": .string("hide")]).hideInFullscreen)
    }

    @Test("overlay deckt den ganzen Bildschirm, toast unten rechts")
    func placementDefaults() {
        let overlay = SurfacePlacement(kind: "overlay", property: { _ in .null }, style: ComputedStyle())
        #expect(overlay.anchor == .fill && overlay.area == .full)
        #expect(SurfacePlacement(kind: "toast", property: { _ in .null }, style: ComputedStyle()).anchor == .bottomRight)
    }

    @Test("overhang ragt um den Radius über verankerte Kanten, safe-area rückt unter die Menüleiste")
    func overhangSafeArea() {
        var placement = SurfacePlacement(anchor: .left, width: CSSLength(44, .points), height: CSSLength(300, .points))
        var spec = spec("panel", ["overhang": .bool(true)])
        let layout = SurfaceLayout.compute(placement: placement, spec: spec, radius: 12, screen: HostFixture.screen, fitting: .zero)
        #expect(layout.frame == CGRect(x: -12, y: 285, width: 56, height: 300))
        #expect(layout.insets.leading == 12)
        #expect(layout.clipTop == 0)
        let hanging = SurfaceLayout.compute(placement: SurfacePlacement(anchor: .top, width: CSSLength(200, .points), height: CSSLength(60, .points)), spec: spec, radius: 12, screen: HostFixture.screen, fitting: .zero)
        #expect(hanging.clipTop == 12)
        #expect(hanging.frame.maxY - hanging.clipTop == HostFixture.screen.visible.maxY)
        placement = SurfacePlacement(anchor: .top, area: .full, width: CSSLength(200, .points), height: CSSLength(60, .points))
        spec = self.spec("panel")
        let top = SurfaceLayout.compute(placement: placement, spec: spec, radius: 0, screen: HostFixture.screen, fitting: .zero)
        #expect(top.insets.top == 30)
        spec.safeArea = false
        #expect(SurfaceLayout.compute(placement: placement, spec: spec, radius: 0, screen: HostFixture.screen, fitting: .zero).insets.top == 0)
    }
}

@MainActor
@Suite("Fenster-Host")
struct WindowHostTests {
    static let shell = """
    panel "bar" anchor="left" reserve=#true { row {} }
    popup "menu" anchor="top" { row {} }
    popup "quick" motion="none" { row {} }
    osd "volume" { row {} }
    window "settings" title="Settings" { row {} }
    overlay "corners" { row {} }
    """
    static let css = "#bar { width: 44px; height: 100%; }"

    @Test("ein Fenster je Oberfläche und Bildschirm, panel sichtbar, popup zu")
    func build() throws {
        let fixture = try HostFixture(Self.shell, css: Self.css)
        #expect(fixture.factory.made.count == 5)
        #expect(fixture.host.stats.windowsCreated == 5)
        #expect(fixture.window("bar")?.isShown == true)
        #expect(fixture.window("bar")?.frame == CGRect(x: 0, y: 0, width: 44, height: 870))
        #expect(fixture.window("menu")?.isShown == false)
        #expect(fixture.window("corners")?.isShown == true)
        #expect(fixture.window("corners")?.frame == HostFixture.screen.frame)
    }

    @Test("Popup auf und zu: Bewegung, kein neues Fenster, Ende meldet die Runtime")
    func openClose() throws {
        let fixture = try HostFixture(Self.shell, css: Self.css)
        let menu = try #require(fixture.window("menu"))
        fixture.assembly.runtime.open("menu", screenKey: nil)
        fixture.flush()
        #expect(menu.isShown)
        #expect(menu.animations.map(\.animator) == ["slide"])
        fixture.assembly.runtime.close("menu")
        fixture.flush()
        #expect(menu.animations.last?.opening == false)
        #expect(fixture.link.finished.isEmpty)
        menu.finishAnimations()
        #expect(!menu.isShown)
        #expect(fixture.link.finished == ["menu"])
        let quick = try #require(fixture.window("quick"))
        fixture.assembly.runtime.toggle("quick")
        fixture.assembly.runtime.toggle("quick")
        #expect(quick.animations.isEmpty)
        #expect(fixture.link.finished == ["menu", "quick"])
        #expect(fixture.host.stats.windowsCreated == 5)
    }

    @Test("surface.opening gilt bis zum Ende der Öffnungsbewegung")
    func openingFlag() throws {
        let fixture = try HostFixture(Self.shell, css: Self.css)
        func opening(_ id: String) -> Value {
            fixture.assembly.store.value(DependencyPath("surface:" + id + "@" + HostFixture.screen.key, ["opening"]))
        }
        let menu = try #require(fixture.window("menu"))
        fixture.assembly.runtime.open("menu", screenKey: nil)
        #expect(opening("menu") == .bool(true))
        fixture.flush()
        #expect(opening("menu") == .bool(true))
        menu.finishAnimations()
        #expect(opening("menu") == .bool(false))
        fixture.assembly.runtime.open("quick", screenKey: nil)
        fixture.flush()
        #expect(opening("quick") == .bool(false))
        fixture.assembly.runtime.open("settings", screenKey: nil)
        fixture.flush()
        #expect(opening("settings") == .bool(false))
    }

    @Test("close-on fragt die Runtime, window-Art schliesst über die Runtime")
    func closeRequest() throws {
        let fixture = try HostFixture(Self.shell, css: Self.css)
        fixture.assembly.runtime.open("settings", screenKey: nil)
        let settings = try #require(fixture.window("settings"))
        #expect(settings.isShown)
        settings.onCloseRequest?()
        #expect(!settings.isShown)
        #expect(fixture.link.finished == ["settings"])
    }

    @Test("reserve meldet den Streifen als Panel-Rand")
    func reserve() throws {
        let fixture = try HostFixture(Self.shell, css: Self.css)
        var reported: [PanelReserve] = []
        fixture.host.onReservesChanged = { reported = $0 }
        try fixture.reload(Self.shell, css: "#bar { width: 60px; height: 100%; }")
        #expect(reported == [PanelReserve(screen: HostFixture.screen.key, edge: .left, size: 60)])
    }

    @Test("Reload mit Änderungen baut kein Fenster neu")
    func reloadKeepsWindows() throws {
        let fixture = try HostFixture(Self.shell, css: Self.css)
        let before = fixture.host.controllers.mapValues { ObjectIdentifier($0.window) }
        let changed = Self.shell.replacingOccurrences(of: "row {}", with: "row { column {} }")
            .replacingOccurrences(of: "anchor=\"top\"", with: "anchor=\"right\"")
        try fixture.reload(changed, css: "#bar { width: 50px; height: 100%; }")
        try fixture.reload(changed + "\npanel \"extra\" { row {} }", css: Self.css)
        try fixture.reload(Self.shell, css: Self.css)
        let after = fixture.host.controllers.mapValues { ObjectIdentifier($0.window) }
        #expect(after == before)
        #expect(fixture.host.stats.windowsCreated == 6)
        #expect(fixture.host.stats.windowsClosed == 1)
        #expect(fixture.window("bar")?.frame.width == 44)
    }

    @Test("Art-Wechsel ersetzt genau dieses Fenster")
    func kindChange() throws {
        let fixture = try HostFixture(Self.shell, css: Self.css)
        let bar = try #require(fixture.window("bar"))
        try fixture.reload(Self.shell.replacingOccurrences(of: "overlay \"corners\"", with: "panel \"corners\""), css: Self.css)
        #expect(fixture.window("bar") === bar)
        #expect(fixture.host.stats.windowsCreated == 6)
    }

    @Test("20 Space-Wechsel: 0 neue Fenster, 0 neu gebaute Oberflächen")
    func spaceChanges() throws {
        let fixture = try HostFixture(Self.shell, css: Self.css)
        let center = NotificationCenter()
        fixture.host.observeSpaces(center)
        let windows = fixture.host.stats.windowsCreated
        let surfaces = fixture.assembly.runtime.stats.surfacesBuilt
        let contents = fixture.factory.made.map(\.contentSets)
        for _ in 0..<20 {
            center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            fixture.flush()
        }
        #expect(fixture.host.stats.spaceChanges == 20)
        #expect(fixture.host.stats.windowsCreated == windows)
        #expect(fixture.host.stats.windowsClosed == 0)
        #expect(fixture.assembly.runtime.stats.surfacesBuilt == surfaces)
        #expect(fixture.factory.made.map(\.contentSets) == contents)
    }

    @Test("Vollbild versteckt Panels, Bildschirmwechsel misst neu ohne neues Fenster")
    func fullscreenAndScreens() throws {
        let fixture = try HostFixture(Self.shell, css: Self.css)
        let bar = try #require(fixture.window("bar"))
        fixture.assembly.runtime.setHiddenByFullscreen(true, screenKey: HostFixture.screen.key)
        #expect(!bar.isShown)
        #expect(fixture.window("corners")?.isShown == true)
        fixture.assembly.runtime.setHiddenByFullscreen(false, screenKey: HostFixture.screen.key)
        #expect(bar.isShown)
        var bigger = HostFixture.screen
        bigger.visible.size.height = 800
        fixture.host.screensChanged([bigger.key: bigger])
        #expect(bar.frame.height == 800)
        fixture.host.screensChanged([:])
        #expect(bar.frame.height == 800)
        #expect(fixture.host.stats.windowsCreated == 5)
    }
}

@MainActor
@Suite("Hooks des Fenster-Hosts")
struct HostHookTests {
    final class Dimmer: BackgroundPainter {
        var calls = 0
        let mode: String
        init(_ mode: String) { self.mode = mode }
        func background(for surface: SurfaceInstance, style: ComputedStyle) -> BackgroundChoice {
            calls += 1
            return mode == "hide" ? .suppressed : .replaced(AnyView(Color.black.opacity(0.4)))
        }
    }

    final class Corners: AuxiliaryWindowOwner {
        let ownerID = "corners"
        func windows(on screen: ScreenGeometry) -> [AuxiliaryWindowSpec] {
            [AuxiliaryWindowSpec(id: "top-left", frame: CGRect(x: screen.frame.minX, y: screen.frame.maxY - 10, width: 10, height: 10), level: .statusBar)]
        }
        func content(for id: String, screen: ScreenGeometry) -> AnyView { AnyView(Color.black) }
    }

    final class Drop: SurfaceAnimator {
        let name = "slide"
        func closedTransform(_ geometry: MotionGeometry) -> CATransform3D { CATransform3DMakeTranslation(0, 100, 0) }
        func transformAnimation(opening: Bool) -> CAAnimation? { nil }
        func fade(opening: Bool) -> (duration: TimeInterval, curve: CAMediaTimingFunction) { (0.1, CAMediaTimingFunction(name: .linear)) }
        func progress(at time: TimeInterval, opening: Bool) -> Double { min(1, time / 0.1) }
        func duration(opening: Bool) -> TimeInterval { 0.1 }
    }

    @Test("SurfaceFrames: Rahmen während der Bewegung je Frame, ohne Beobachter kein Ticker")
    func surfaceFrames() throws {
        let fixture = try HostFixture(WindowHostTests.shell, css: WindowHostTests.css)
        fixture.host.animators.register(SlideAnimator(reduceMotion: { false }))
        fixture.host.animators.register(GrowAnimator(reduceMotion: { false }))
        var tickers: [ManualTicker] = []
        fixture.host.makeTicker = { _ in
            let ticker = ManualTicker()
            tickers.append(ticker)
            return ticker
        }
        fixture.assembly.runtime.open("menu", screenKey: nil)
        #expect(tickers.isEmpty)
        fixture.assembly.runtime.close("menu")
        fixture.window("menu")?.finishAnimations()
        var seen: [CGRect] = []
        let token = fixture.host.frames.observe { key, frame in
            if key.hasPrefix("menu@") { seen.append(frame) }
        }
        fixture.assembly.runtime.open("menu", screenKey: nil)
        let ticker = try #require(tickers.first)
        let open = try #require(fixture.window("menu")).frame
        #expect(ticker.tick?(0) == true)
        #expect(ticker.tick?(0.25) == true)
        #expect(ticker.tick?(0.6) == false)
        #expect(seen.count >= 3)
        #expect(seen[0].minY > open.minY)
        #expect(abs(seen.last!.minY - open.minY) < 0.5)
        token.cancel()
        #expect(!fixture.host.frames.hasObservers)
    }

    @Test("Bewegung reduzieren: slide und grow bleiben am Platz und blenden nur")
    func reducedMotionKeepsFrame() {
        let geometry = MotionGeometry(edge: .top, size: CGSize(width: 200, height: 100), topInset: 24, flipped: false)
        let open = CGRect(x: 10, y: 700, width: 200, height: 100)
        for animator in [SlideAnimator(reduceMotion: { true }), GrowAnimator(reduceMotion: { true })] as [any SurfaceAnimator] {
            #expect(CATransform3DIsIdentity(animator.closedTransform(geometry)))
            #expect(animator.visibleFrame(open: open, geometry: geometry, progress: 0) == open)
        }
        #expect(SlideAnimator(reduceMotion: { false }).visibleFrame(open: open, geometry: geometry, progress: 0).minY > open.minY)
    }

    @Test("Animator als Registry-Eintrag: eigene Umsetzung ersetzt slide")
    func customAnimator() throws {
        let fixture = try HostFixture("popup \"sheet\" motion=\"slide\" { row {} }")
        let drop = Drop()
        fixture.host.animators.register(drop)
        #expect(fixture.host.animators.animator("slide") === drop)
        fixture.assembly.runtime.open("sheet", screenKey: nil)
        #expect(fixture.window("sheet")?.animations.map(\.animator) == ["slide"])
        #expect(fixture.window("sheet")?.animatorIDs == [ObjectIdentifier(drop)])
        let frame = Drop().visibleFrame(open: CGRect(x: 0, y: 0, width: 10, height: 10), geometry: MotionGeometry(edge: .center, size: CGSize(width: 10, height: 10), topInset: 0, flipped: false), progress: 0.5)
        #expect(frame.minY == 50)
        #expect(Set(AnimatorRegistry.builtin().names) == ["fade", "grow", "none", "slide"])
    }

    @Test("BackgroundPainter ersetzt oder unterdrückt den Hintergrund")
    func backgroundPainter() throws {
        let fixture = try HostFixture("panel \"bar\" { row {} }", css: "#bar { background: red; width: 10px; height: 10px; }")
        let surface = try #require(fixture.assembly.runtime.surface("bar", screenKey: HostFixture.screen.key))
        let style = try #require(fixture.host.context).styles.resolve(StyleResolver.subject(for: surface), ancestors: [], parent: nil)
        #expect(style["background"] != nil)
        let hidden = SurfaceBackground.resolve(Dimmer("hide"), surface: surface, style: style)
        #expect(hidden.style["background"] == nil && hidden.painted == nil)
        #expect(hidden.style["width"] != nil)
        let replaced = SurfaceBackground.resolve(Dimmer("replace"), surface: surface, style: style)
        #expect(replaced.style["background"] == nil && replaced.painted != nil)
        #expect(SurfaceBackground.resolve(nil, surface: surface, style: style).style == style)
        let painter = Dimmer("hide")
        fixture.host.backgroundPainter = painter
        fixture.host.restyle(try #require(fixture.host.context))
        #expect(fixture.host.stats.windowsCreated == 1)
        let hosting = NSHostingView(rootView: try #require(fixture.window("bar")?.content))
        _ = hosting.fittingSize
        #expect(painter.calls > 0)
    }

    @Test("Hilfsfenster je Bildschirm, bleiben beim Abgleich, gehen mit dem Bildschirm")
    func auxiliaryWindows() throws {
        let fixture = try HostFixture("panel \"bar\" { row {} }")
        let second = ScreenGeometry(key: "Side 1920x1080", frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), visible: CGRect(x: 1440, y: 0, width: 1920, height: 1050))
        fixture.host.auxiliary.register(Corners(), screens: [HostFixture.screen, second])
        #expect(fixture.factory.auxiliary.count == 2)
        #expect(fixture.factory.auxiliary.allSatisfy { $0.isShown && $0.level == .statusBar })
        fixture.host.screensChanged([HostFixture.screen.key: HostFixture.screen, second.key: second])
        #expect(fixture.host.auxiliary.created == 2)
        fixture.host.screensChanged([HostFixture.screen.key: HostFixture.screen])
        #expect(fixture.factory.auxiliary.filter(\.closed).count == 1)
        fixture.host.auxiliary.unregister("corners", screens: [HostFixture.screen])
        #expect(fixture.host.auxiliary.windows.isEmpty)
    }
}

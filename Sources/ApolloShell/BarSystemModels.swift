import AppKit
import ApolloShellCore
import ApplicationServices
import Carbon.HIToolbox
import CoreAudio
import Observation
import os

// The models behind the stage-3 bar modules: the frontmost app and its
// window title, the keyboard input source, the output volume. All of them
// listen instead of polling (NSWorkspace, accessibility notifications, the
// text input system's notification, CoreAudio listeners), and only while a
// block that shows them stands in a visible bar (`BarDemand`) - without
// such a block they hold no observer at all.

// MARK: - Frontmost app

/// The frontmost app for the window title block, and on request the title of
/// its focused window.
///
/// The app comes from NSWorkspace (a notification, on the main thread, costs
/// nothing). The title needs accessibility: every read is a synchronous
/// request to the other app, which for a hung app waits until the timeout -
/// so it runs on `FrontWindowTitleWorker`'s queue, never on the main thread,
/// the same split as the window guard.
@MainActor
@Observable
final class BarFrontAppModel {
    struct FrontApp: Equatable {
        let pid: pid_t
        let name: String
        let icon: NSImage?
    }

    private(set) var app: FrontApp?
    /// `nil`: not asked for, no permission, or the window has none.
    private(set) var title: String?

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var demand = BarDemand()
    /// Blocks that show the title; only they make the worker run.
    @ObservationIgnored private var titleUsers = 0
    @ObservationIgnored private var activation: NSObjectProtocol?
    @ObservationIgnored private lazy var worker = FrontWindowTitleWorker { [weak self] pid, title in
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // A late answer about the app before is dropped.
                guard let self, self.app?.pid == pid, self.title != title else { return }
                self.title = title
            }
        }
    }
    @ObservationIgnored private var followedPID: pid_t?

    init() {
        live = true
    }

    /// For the preview and the image sample: fixed, never listens.
    init(preview app: FrontApp?, title: String?) {
        live = false
        self.app = app
        self.title = title
    }

    var paused: Bool {
        get { demand.paused }
        set { demand.paused = newValue; sync() }
    }

    func acquire(wantsTitle: Bool) {
        demand.acquire()
        if wantsTitle { titleUsers += 1 }
        sync()
    }

    func release(wantsTitle: Bool) {
        demand.release()
        if wantsTitle { titleUsers = max(titleUsers - 1, 0) }
        sync()
    }

    private func sync() {
        guard live else { return }
        if demand.isActive, activation == nil {
            activation = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.show(running) }
            }
            show(NSWorkspace.shared.frontmostApplication)
        } else if !demand.isActive, let activation {
            NSWorkspace.shared.notificationCenter.removeObserver(activation)
            self.activation = nil
        }
        followTitle()
    }

    private func show(_ running: NSRunningApplication?) {
        let next = running.map {
            FrontApp(pid: $0.processIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? "", icon: $0.icon)
        }
        if next?.pid != app?.pid {
            app = next
            title = nil
        }
        followTitle()
    }

    /// The worker follows the front app while a visible block shows the
    /// title and the permission is there. `AXIsProcessTrusted` is a cheap
    /// local check; asked again on every app switch, so a permission given
    /// later is picked up without polling.
    private func followTitle() {
        let pid = demand.isActive && titleUsers > 0 && AXIsProcessTrusted() ? app?.pid : nil
        guard pid != followedPID else { return }
        followedPID = pid
        if let pid {
            worker.follow(pid)
        } else {
            worker.stop()
            if title != nil { title = nil }
        }
    }
}

/// Reads the focused window's title of one app, on a serial queue of its
/// own, and hears about focus and title changes through an AXObserver.
///
/// The observer's run loop source hangs off the main run loop (a dispatch
/// queue has none), its callback only hops over to the queue - the window
/// guard's pattern (WindowGuard.swift).
///
/// `@unchecked Sendable`: its state is touched only on `queue`.
final class FrontWindowTitleWorker: @unchecked Sendable {
    /// A hung app blocks the queue at most this long (macOS's default is 6 s).
    private static let messagingTimeout: Float = 1

    private let queue = DispatchQueue(label: AppIdentity.scoped("windowtitle"))
    private let onTitle: @Sendable (pid_t, String?) -> Void

    // Only touched on `queue`.
    private var pid: pid_t = 0
    private var app: AXUIElement?
    private var observer: AXObserver?
    /// The window whose title changes are registered.
    private var window: AXUIElement?
    private var lastTitle: String??

    init(onTitle: @escaping @Sendable (pid_t, String?) -> Void) {
        self.onTitle = onTitle
    }

    func follow(_ pid: pid_t) {
        queue.async { self.attach(pid) }
    }

    func stop() {
        queue.async { self.detach() }
    }

    private func attach(_ pid: pid_t) {
        detach()
        self.pid = pid
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        self.app = app
        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let worker = Unmanaged<FrontWindowTitleWorker>.fromOpaque(refcon).takeUnretainedValue()
            worker.queue.async { worker.read() }
        }, &created)
        if status == .success, let created {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(created, app, kAXFocusedWindowChangedNotification as CFString, refcon)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            observer = created
        }
        read()
    }

    private func detach() {
        if let observer {
            if let window { AXObserverRemoveNotification(observer, window, kAXTitleChangedNotification as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        app = nil
        window = nil
        lastTitle = nil
        pid = 0
    }

    /// The focused window's title; moves the title notification along when
    /// the focus went to another window. Reports only real changes.
    private func read() {
        guard let app else { return }
        let focused = AX.element(app, kAXFocusedWindowAttribute as String)
        if let observer, !Self.same(focused, window) {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            if let window { AXObserverRemoveNotification(observer, window, kAXTitleChangedNotification as CFString) }
            if let focused { AXObserverAddNotification(observer, focused, kAXTitleChangedNotification as CFString, refcon) }
            window = focused
        }
        let title = focused.flatMap { AX.string($0, kAXTitleAttribute as String) }
        guard lastTitle != .some(title) else { return }
        lastTitle = .some(title)
        onTitle(pid, title)
    }

    private static func same(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): CFEqual(a, b)
        default: false
        }
    }
}

// MARK: - Keyboard input source

/// The selected keyboard input source and the ones a click cycles through.
///
/// The text input system posts a distributed notification on every switch
/// (keyboard shortcut, menu bar, this block) - no polling. TIS itself is only
/// called on the main thread: several of its functions assert that since
/// macOS 14.
@MainActor
@Observable
final class BarKeyboardModel {
    /// Short name ("DE") and full name ("Swiss German") of the current source.
    private(set) var short = ""
    private(set) var name = ""

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var demand = BarDemand()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let log = Logger(category: "bar")

    init() {
        live = true
    }

    init(preview short: String, name: String) {
        live = false
        self.short = short
        self.name = name
    }

    var paused: Bool {
        get { demand.paused }
        set { demand.paused = newValue; sync() }
    }

    func acquire() { demand.acquire(); sync() }
    func release() { demand.release(); sync() }

    private func sync() {
        guard live else { return }
        if demand.isActive, observer == nil {
            let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
            observer = DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.refresh() }
            }
            refresh()
        } else if !demand.isActive, let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
    }

    /// The short names are worked out across all selectable sources, so two
    /// of the same language get told apart ("EN", "EN2").
    private func refresh() {
        let sources = Self.selectable()
        let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let currentID = current.flatMap { Self.string($0, kTISPropertyInputSourceID) }
        let infos = sources.map(\.info)
        let shorts = InputSourceCycle.abbreviations(for: infos)
        if let index = infos.firstIndex(where: { $0.id == currentID }) {
            set(short: shorts[index], name: infos[index].name)
        } else if let current {
            // An input method's mode or a palette that is not in the cycle.
            let info = Self.info(current)
            set(short: InputSourceCycle.abbreviations(for: [info]).first ?? "?", name: info.name)
        }
    }

    private func set(short: String, name: String) {
        if short != self.short { self.short = short }
        if name != self.name { self.name = name }
    }

    /// Like the next source in the input menu. The display follows from the
    /// notification the switch sets off, not from a guess.
    func selectNext() {
        guard live else { return }
        let sources = Self.selectable()
        let currentID = TISCopyCurrentKeyboardInputSource().flatMap {
            Self.string($0.takeRetainedValue(), kTISPropertyInputSourceID)
        }
        guard let next = InputSourceCycle.next(after: currentID, in: sources.map(\.info.id)),
              let source = sources.first(where: { $0.info.id == next })?.source else { return }
        let status = TISSelectInputSource(source)
        if status != noErr { log.error("Input source switch failed: \(status)") }
    }

    /// Enabled keyboard sources that can be selected - what the input menu
    /// lists. Input methods count by their modes (Kotoeri's Hiragana,
    /// Katakana ...), not by the method itself, as in the menu.
    private static func selectable() -> [(source: TISInputSource, info: InputSourceInfo)] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceIsEnabled as String: true,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        let types: Set<String> = [kTISTypeKeyboardLayout as String, kTISTypeKeyboardInputMode as String,
                                  kTISTypeKeyboardInputMethodWithoutModes as String]
        return list.compactMap { source in
            guard let type = string(source, kTISPropertyInputSourceType), types.contains(type) else { return nil }
            return (source, info(source))
        }
    }

    private static func info(_ source: TISInputSource) -> InputSourceInfo {
        let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
            .map { Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as? [String] ?? [] } ?? []
        return InputSourceInfo(id: string(source, kTISPropertyInputSourceID) ?? "",
                               name: string(source, kTISPropertyLocalizedName) ?? "",
                               languages: languages)
    }

    /// TIS hands properties back unretained ("Get" rule).
    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        TISGetInputSourceProperty(source, key).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
    }
}

// MARK: - Volume

/// Volume, mute and the output device's name for the volume block, on top
/// of the OSD's `VolumeMonitor` (CoreAudio listeners on the default device
/// and on its volume and mute - no polling). Its own monitor, started only
/// on demand: the OSD's one lives in the OSD and knows nothing of the bars.
@MainActor
@Observable
final class BarVolumeModel {
    private(set) var volume: Float = 0
    private(set) var muted = false
    private(set) var deviceName = ""
    private(set) var settable = false

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var demand = BarDemand()
    @ObservationIgnored private var monitor: VolumeMonitor?

    init() {
        live = true
    }

    init(preview volume: Float, muted: Bool, deviceName: String) {
        live = false
        self.volume = volume
        self.muted = muted
        self.deviceName = deviceName
        settable = true
    }

    var paused: Bool {
        get { demand.paused }
        set { demand.paused = newValue; sync() }
    }

    func acquire() { demand.acquire(); sync() }
    func release() { demand.release(); sync() }

    private func sync() {
        guard live else { return }
        if demand.isActive, monitor == nil {
            let monitor = VolumeMonitor()
            monitor.onChange = { [weak self] _, _ in self?.pull() }
            monitor.onDeviceChange = { [weak self] in self?.pull() }
            monitor.start()
            self.monitor = monitor
            pull()
        } else if !demand.isActive, let monitor {
            monitor.stop()
            self.monitor = nil
        }
    }

    private func pull() {
        guard let monitor else { return }
        if monitor.volume != volume { volume = monitor.volume }
        if monitor.muted != muted { muted = monitor.muted }
        if monitor.volumeSettable != settable { settable = monitor.volumeSettable }
        let name = monitor.deviceName ?? ""
        if name != deviceName { deviceName = name }
    }

    /// Scroll: whole 5 % steps; the display follows from the listener.
    func step(by steps: Int) {
        guard let monitor, steps != 0 else { return }
        monitor.setVolume(VolumeStep.stepped(monitor.volume, by: steps))
    }

    func toggleMute() {
        guard let monitor else { return }
        monitor.setMuted(!monitor.muted)
    }
}

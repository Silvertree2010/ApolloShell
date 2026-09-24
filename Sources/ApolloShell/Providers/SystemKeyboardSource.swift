import AppKit
import Carbon
import ApolloProviders

@MainActor
final class SystemKeyboardSource: KeyboardSource {
    private var observer: NSObjectProtocol?
    private var monitors: [Any] = []

    var current: KeyboardInputSource? {
        TISCopyCurrentKeyboardInputSource().map { Self.describe($0.takeRetainedValue()) } ?? nil
    }

    var sources: [KeyboardInputSource] {
        Self.selectable().compactMap(Self.describe)
    }

    var capsLock: Bool { NSEvent.modifierFlags.contains(.capsLock) }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        stopObserving()
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        observer = DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { _ in
            MainActor.assumeIsolated { handler() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            MainActor.assumeIsolated { handler() }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stopObserving() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    func select(_ id: String) -> Bool {
        guard let source = Self.selectable().first(where: { Self.string($0, kTISPropertyInputSourceID) == id }) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    private static func selectable() -> [TISInputSource] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    private static func describe(_ source: TISInputSource) -> KeyboardInputSource? {
        guard let id = string(source, kTISPropertyInputSourceID) else { return nil }
        let name = string(source, kTISPropertyLocalizedName) ?? id
        let language = languages(source).first ?? ""
        let short = language.isEmpty ? String(name.prefix(2)).uppercased() : String(language.prefix(2)).uppercased()
        return KeyboardInputSource(id: id, name: name, short: short)
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func languages(_ source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
        return (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]) ?? []
    }
}

import AppKit
import ApolloShellCore
import os

@MainActor
final class MediaKeyTap {
    var onKey: (SystemKey, _ fine: Bool, _ down: Bool) -> Bool = { _, _, _ in false }

    private let log = Logger(category: "osd")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Timer?

    var isActive: Bool { tap != nil }

    func setEnabled(_ on: Bool) {
        on ? start() : stop()
    }

    private func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            retry?.invalidate()
            retry = .once(after: 5, owner: self) { $0.start() }
            return
        }
        let mask = CGEventMask(1) << 14
        let ref = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: mediaKeyCallback, userInfo: ref)
        else {
            log.error("Media-Key-Tap nicht angelegt")
            return
        }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        log.notice("Media-Key-Tap an")
    }

    private func stop() {
        retry?.invalidate()
        retry = nil
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        log.notice("Media-Key-Tap aus")
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func press(_ key: SystemKey, fine: Bool, down: Bool) -> Bool {
        onKey(key, fine, down)
    }
}

private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(info).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard let e = NSEvent(cgEvent: event), e.subtype.rawValue == 8,
          let key = SystemKey(data1: e.data1) else { return Unmanaged.passUnretained(event) }
    let down = SystemKey.isDown(data1: e.data1)
    let fine = e.modifierFlags.contains([.shift, .option])
    let mine = MainActor.assumeIsolated { tap.press(key, fine: fine, down: down) }
    return mine ? nil : Unmanaged.passUnretained(event)
}

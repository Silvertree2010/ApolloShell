import AppKit
import ApolloShellCore
import ApplicationServices
import Observation
import os
import ScreenCaptureKit

/// Other apps' status items, mirrored from Apple's menu bar (spec topbar.md,
/// "Menüs fremder Statussymbole").
///
/// - Which and where: accessibility (`AXMenus.statusItems`), ordered by the
///   core (`StatusItemOrder`) - left to right as in Apple's bar.
/// - What they look like: ScreenCaptureKit captures each item's window on
///   its own, transparent, even while our bar covers it. Needs the Screen
///   Recording permission; without it (or with Apple's bar hidden, when the
///   windows lie off screen) an item shows its title or its app's icon.
///   Grey glyphs become templates and take the bar's colour.
/// - A click: an item with an NSMenu gets that menu read and drawn by us,
///   under our icon; its entries are pressed in the closed original. An item
///   with a popover or a window of its own can only be pressed - it opens
///   where Apple's bar has the item (the popover window can not be moved
///   from outside, measured 23.09.).
///
/// Only while a visible block shows them (`BarDemand`): every 4 seconds a
/// cheap look at the status windows (their frames, no permission needed);
/// a full read when they changed or every 20 seconds, new images every 8.
@MainActor
@Observable
final class StatusItemsModel {
    struct Item: Identifiable, Equatable {
        let record: StatusItemRecord
        /// Captured from Apple's bar; `nil` until then or without permission.
        var image: NSImage?
        /// A grey glyph: drawn in the bar's colour instead of its own.
        var template = false
        /// ApolloShell's own item (Nexus): opens Nexus directly.
        var isOwn = false
        /// Fallback without an image.
        var appIcon: NSImage?

        var id: String { record.id }
    }

    private(set) var items: [Item] = []
    /// The item whose menu is open right now.
    private(set) var openID: String?
    /// Our own item: Nexus opens through the shell, not through AX to
    /// ourselves.
    @ObservationIgnored var onOwnItem: @MainActor () -> Void = {}
    /// Where our own item (Nexus) stands in Apple's bar, in screen
    /// coordinates; `nil` while it is hidden. Read on the main thread - never
    /// through accessibility (see `AXMenus.statusItems`).
    @ObservationIgnored var ownItemFrame: @MainActor () -> NSRect? = { nil }

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var demand = BarDemand()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var lastSignature: [CGRect] = []
    @ObservationIgnored private var lastList = Date.distantPast
    @ObservationIgnored private var lastCapture = Date.distantPast
    @ObservationIgnored private let log = Logger(category: "statusitems")

    static let tick: TimeInterval = 4
    static let listInterval: TimeInterval = 20
    static let captureInterval: TimeInterval = 8

    init() {
        live = true
    }

    /// For the preview and the image samples: fixed items, never reads.
    init(preview items: [Item]) {
        live = false
        self.items = items
    }

    var paused: Bool {
        get { demand.paused }
        set { demand.paused = newValue; sync() }
    }

    func acquire() { demand.acquire(); sync() }
    func release() { demand.release(); sync() }

    private func sync() {
        guard live else { return }
        if demand.isActive, timer == nil {
            let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tickNow() }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    // A new app puts its item up a moment after it launched.
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1.5))
                        self?.refresh()
                    }
                })
            }
            refresh()
        } else if !demand.isActive, let timer {
            timer.invalidate()
            self.timer = nil
            for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            observers = []
        }
    }

    private func tickNow() {
        let signature = Self.windowSignature()
        let now = Date()
        if signature != lastSignature || now.timeIntervalSince(lastList) >= Self.listInterval {
            refresh()
        } else if now.timeIntervalSince(lastCapture) >= Self.captureInterval {
            capture()
        }
    }

    /// Reads the items anew, then their images.
    func refresh() {
        guard live, !busy else { return }
        busy = true
        lastSignature = Self.windowSignature()
        lastList = Date()
        Task { @MainActor in
            let own = ProcessInfo.processInfo.processIdentifier
            var raw = await AXMenus.statusItems()
            if let frame = ownItemFrame(), let main = NSScreen.screens.first {
                // Screen coordinates (y up from the main screen's bottom) to
                // accessibility's (y down from its top).
                raw.append(StatusItemRecord(pid: own, bundleID: Bundle.main.bundleIdentifier, index: 0,
                                            frame: CGRect(x: frame.minX, y: main.frame.maxY - frame.maxY,
                                                          width: frame.width, height: frame.height),
                                            label: "Nexus"))
            }
            let records = StatusItemOrder.mirrored(raw)
            let old = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let next = records.map { record in
                var item = old[record.id].map { Item(record: record, image: $0.image, template: $0.template,
                                                    isOwn: $0.isOwn, appIcon: $0.appIcon) }
                    ?? Item(record: record)
                item.isOwn = record.pid == own
                if item.appIcon == nil { item.appIcon = NSRunningApplication(processIdentifier: record.pid)?.icon }
                return item
            }
            if next != items { items = next }
            busy = false
            capture()
        }
    }

    /// New images for the items, where the permission allows it.
    private func capture() {
        guard live, !items.isEmpty, CGPreflightScreenCaptureAccess() else { return }
        lastCapture = Date()
        let frames = items.map { ($0.id, $0.record.frame) }
        Task { @MainActor in
            let images = await StatusItemCapture.images(for: frames)
            var next = items
            for index in next.indices {
                guard let image = images[next[index].id] else { continue }
                let picture = NSImage(cgImage: image.image, size: image.size)
                picture.isTemplate = image.monochrome
                next[index].image = picture
                next[index].template = image.monochrome
            }
            items = next
        }
    }

    /// The frames of the status windows on screen - cheap, and changes
    /// whenever an item comes, goes, moves or changes its width.
    private static func windowSignature() -> [CGRect] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { window -> CGRect? in
            guard (window[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.statusWindow)),
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        .sorted { $0.minX < $1.minX }
    }

    // MARK: - Click

    func click(_ item: Item, below view: NSView) {
        guard live else { return }
        if item.isOwn {
            onOwnItem()
            return
        }
        guard AXIsProcessTrusted() else {
            AXMenuBuilder.popUp(AXMenuBuilder.permissionMenu(), below: view)
            return
        }
        let pid = item.record.pid
        let index = item.record.index
        Task { @MainActor in
            if let nodes = await AXMenus.statusItemMenu(pid: pid, index: index) {
                log.notice("status item \(item.id, privacy: .public): menu of \(nodes.count, privacy: .public), anchored: \(view.window != nil, privacy: .public)")
                let menu = AXMenuBuilder.menu(nodes) { [log] path in
                    Task {
                        let pressed = await AXMenus.pressStatusItem(pid: pid, index: index, path: path)
                        log.notice("status item \(item.id, privacy: .public) entry \(path.last?.title ?? "", privacy: .public) pressed: \(pressed, privacy: .public)")
                    }
                }
                openID = item.id
                AXMenuBuilder.popUp(menu, below: view)
                openID = nil
            } else {
                // A popover or a window: only the app can show it, at its item.
                let pressed = await AXMenus.pressStatusItem(pid: pid, index: index, path: [])
                log.notice("status item \(item.id, privacy: .public) pressed in place: \(pressed, privacy: .public)")
            }
        }
    }
}

/// The ScreenCaptureKit part: each status window captured on its own.
enum StatusItemCapture {
    struct Captured: @unchecked Sendable {
        let image: CGImage
        let size: NSSize
        let monochrome: Bool
    }

    private static let log = Logger(category: "statusitems")

    /// By item id; items without a window on screen are missing.
    static func images(for items: [(id: String, frame: CGRect)]) async -> [String: Captured] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            log.notice("no shareable content: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
        let windows = content.windows.filter { $0.windowLayer == Int(CGWindowLevelForKey(.statusWindow)) }
        var result: [String: Captured] = [:]
        for item in items {
            guard let match = StatusItemOrder.window(for: item.frame, among: windows.map(\.frame)) else { continue }
            let window = windows[match]
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = max(Int(window.frame.width * scale), 1)
            configuration.height = max(Int(window.frame.height * scale), 1)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                result[item.id] = Captured(image: image, size: window.frame.size, monochrome: monochrome(image))
            } catch {
                log.notice("capture failed for \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return result
    }

    private static func monochrome(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn && StatusItemTint.isMonochrome(rgba: pixels)
    }
}

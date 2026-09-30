import AppKit
import ApolloProviders
import ApolloShellCore
import ApplicationServices
import os
import ScreenCaptureKit

@MainActor
final class SystemStatusItemsSource: StatusItemsSource {
    static let shared = SystemStatusItemsSource()
    static let tick: TimeInterval = 4
    static let listInterval: TimeInterval = 20
    static let captureInterval: TimeInterval = 8

    struct Item {
        var record: StatusItemRecord
        var png: Data?
        var version = 0
        var monochrome = false
        var kind: String?
    }

    struct OwnItem {
        var frame: CGRect
        var image: NSImage
        var open: @MainActor () -> Void
    }

    var own: @MainActor () -> OwnItem? = { nil }
    private var ownOpen: (@MainActor () -> Void)?
    private var ownPNG: Data?
    private var items: [Item] = []
    private var handler: (@MainActor ([StatusItemState]) -> Void)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var busy = false
    private var lastSignature: [CGRect] = []
    private var lastList = Date.distantPast
    private var lastCapture = Date.distantPast
    private let log = Logger(category: "statusitems")

    func start(_ handler: @escaping @MainActor ([StatusItemState]) -> Void) {
        self.handler = handler
        guard timer == nil else { return deliver() }
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickNow() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1.5))
                    self?.refresh()
                }
            })
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
        handler = nil
    }

    private var icons: [pid_t: Data] = [:]

    func imageData(_ id: String) -> Data? {
        guard let item = items.first(where: { $0.record.id == id }) else { return nil }
        if AXMenus.isOwn(item.record.pid) { return ownPNG }
        return item.png ?? (item.record.title.isEmpty ? appIcon(item.record.pid) : nil)
    }

    private func appIcon(_ pid: pid_t) -> Data? {
        if let cached = icons[pid] { return cached }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let bitmap else { return nil }
        bitmap.size = NSSize(width: 16, height: 16)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(origin: .zero, size: bitmap.size))
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])
        icons[pid] = data
        return data
    }

    func item(_ id: String) -> StatusItemRecord? {
        items.first { $0.record.id == id }?.record
    }

    func click(_ id: String) async -> Bool {
        guard let record = item(id) else { return false }
        if AXMenus.isOwn(record.pid) {
            ownOpen?()
            return true
        }
        return await AXMenus.pressStatusItem(pid: record.pid, index: record.index, path: [])
    }

    func menu(_ id: String) async -> [AppMenuNode]? {
        guard let record = item(id) else { return nil }
        if AXMenus.isOwn(record.pid) { return nil }
        let nodes = await AXMenus.statusItemMenu(pid: record.pid, index: record.index)
        if let index = items.firstIndex(where: { $0.record.id == id }) {
            let kind = nodes == nil ? "popover" : "menu"
            if items[index].kind != kind { items[index].kind = kind; deliver() }
        }
        return nodes
    }

    func press(_ id: String, path: [AXMenuStep]) {
        guard let record = item(id) else { return }
        Task { _ = await AXMenus.pressStatusItem(pid: record.pid, index: record.index, path: path) }
    }

    static func png(_ image: NSImage) -> Data? {
        let scale: CGFloat = 2
        let size = image.size
        guard size.width > 0, size.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    private func deliver() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        handler?(items.map { item in
            if item.record.pid == ownPID {
                return StatusItemState(id: item.record.id, app: item.record.bundleID, name: item.record.name, hasImage: ownPNG != nil, kind: "menu", monochrome: true)
            }
            return StatusItemState(id: item.record.id, app: item.record.bundleID, name: item.record.name, title: item.record.title,
                            hasImage: item.png != nil || item.record.title.isEmpty, imageVersion: item.version, kind: item.kind, monochrome: item.png != nil && item.monochrome)
        })
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

    func refresh() {
        guard !busy else { return }
        busy = true
        lastSignature = Self.windowSignature()
        lastList = Date()
        Task { @MainActor in
            var raw = await AXMenus.statusItems()
            if let mine = own(), let main = NSScreen.screens.first {
                ownOpen = mine.open
                if ownPNG == nil { ownPNG = Self.png(mine.image) }
                raw.append(StatusItemRecord(pid: ProcessInfo.processInfo.processIdentifier, bundleID: Bundle.main.bundleIdentifier, index: 0,
                                            frame: CGRect(x: mine.frame.minX, y: main.frame.maxY - mine.frame.maxY, width: mine.frame.width, height: mine.frame.height),
                                            label: "ApolloShell"))
            }
            let records = StatusItemOrder.mirrored(raw)
            let old = Dictionary(items.map { ($0.record.id, $0) }, uniquingKeysWith: { a, _ in a })
            items = records.map { record in
                var item = old[record.id] ?? Item(record: record)
                item.record = record
                return item
            }
            busy = false
            deliver()
            capture()
        }
    }

    private func capture() {
        guard !items.isEmpty, CGPreflightScreenCaptureAccess() else { return }
        lastCapture = Date()
        let frames = items.map { ($0.record.id, $0.record.frame) }
        Task { @MainActor in
            let images = await StatusItemCapture.images(for: frames)
            var changed = false
            for index in items.indices {
                guard let image = images[items[index].record.id] else { continue }
                if items[index].png != image.png || items[index].monochrome != image.monochrome {
                    items[index].png = image.png
                    items[index].monochrome = image.monochrome
                    items[index].version += 1
                    changed = true
                }
            }
            if changed { deliver() }
        }
    }

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
}

enum StatusItemCapture {
    struct Captured: @unchecked Sendable {
        let png: Data
        let monochrome: Bool
    }

    private static let log = Logger(category: "statusitems")

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
                let rep = NSBitmapImageRep(cgImage: image)
                rep.size = window.frame.size
                guard let png = rep.representation(using: .png, properties: [:]) else { continue }
                result[item.id] = Captured(png: png, monochrome: monochrome(image))
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

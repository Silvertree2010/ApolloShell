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

    func imageData(_ id: String) -> Data? {
        items.first { $0.record.id == id }?.png
    }

    func item(_ id: String) -> StatusItemRecord? {
        items.first { $0.record.id == id }?.record
    }

    func click(_ id: String) async -> Bool {
        guard let record = item(id) else { return false }
        return await AXMenus.pressStatusItem(pid: record.pid, index: record.index, path: [])
    }

    func menu(_ id: String) async -> [AppMenuNode]? {
        guard let record = item(id) else { return nil }
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

    private func deliver() {
        handler?(items.map { item in
            StatusItemState(id: item.record.id, app: item.record.bundleID, name: item.record.name, title: item.record.title,
                            hasImage: item.png != nil, imageVersion: item.version, kind: item.kind, monochrome: item.monochrome)
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
            let records = StatusItemOrder.mirrored(await AXMenus.statusItems())
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

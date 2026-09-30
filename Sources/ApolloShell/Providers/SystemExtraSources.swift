import AppKit
import CoreWLAN
import ImageIO
import Network
import ApolloProviders
import ApolloShellCore
import os

@MainActor
final class SystemClipboardSource: ClipboardSource {
    var changeCount: Int { NSPasteboard.general.changeCount }

    func read() -> ClipboardContent {
        let pasteboard = NSPasteboard.general
        return ClipboardContent(types: pasteboard.types?.map(\.rawValue) ?? [], text: pasteboard.string(forType: .string))
    }
}

@MainActor
final class SystemRecentFilesSource: RecentFilesSource {
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?

    func read(since: Date, limit: Int, _ completion: @escaping @MainActor ([RecentFile]) -> Void) {
        stop()
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemLastUsedDate >= %@ AND kMDItemContentType != 'com.apple.application-bundle'", since as NSDate)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let query = self.query else { return }
                let files = Self.collect(query, limit: limit)
                self.stop()
                completion(files)
            }
        }
        self.query = query
        query.start()
    }

    private func stop() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private static func collect(_ query: NSMetadataQuery, limit: Int) -> [RecentFile] {
        query.disableUpdates()
        var result: [RecentFile] = []
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let used = item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date else { continue }
            if path.contains("/.") || path.contains("/Library/") { continue }
            result.append(RecentFile(path: path, name: FileManager.default.displayName(atPath: path), date: used))
            if result.count == limit { break }
        }
        return result
    }
}

@MainActor
final class SystemDrivesSource: DrivesSource {
    private var observers: [NSObjectProtocol] = []
    private let log = Logger(category: "drives")

    func volumes() -> [DriveInfo] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsEjectableKey,
                                      .volumeIsRemovableKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable != false,
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }
            if url.path.hasPrefix("/System/Volumes") { return nil }
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0
            return DriveInfo(name: values.volumeLocalizedName ?? url.lastPathComponent, path: url.path, total: Double(total), free: Double(free),
                             ejectable: (values.volumeIsEjectable ?? false) || (values.volumeIsRemovable ?? false))
        }
    }

    func observe(_ handler: @escaping @MainActor () -> Void) {
        stopObserving()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            })
        }
    }

    func stopObserving() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    func eject(_ path: String) -> Bool {
        guard volumes().contains(where: { $0.path == path }) else { return false }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: path))
            return true
        } catch {
            log.error("Eject failed: \((error as NSError).code, privacy: .public)")
            return false
        }
    }
}

enum ThumbnailData {
    static func png(_ path: String, side: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: side]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

@MainActor
final class SystemPhotosSource: PhotosSource {
    private var cache: [String: Data] = [:]

    func pictures(in folder: String, _ completion: @escaping @MainActor ([String]) -> Void) {
        Task.detached(priority: .utility) {
            let paths = PhotoFolder.pictures(in: folder).map(\.path)
            await MainActor.run { completion(paths) }
        }
    }

    func thumbnail(_ path: String) -> Data? {
        if let hit = cache[path] { return hit }
        guard let data = ThumbnailData.png(path, side: 1200) else { return nil }
        if cache.count > 64 { cache.removeAll() }
        cache[path] = data
        return data
    }
}

@MainActor
final class SystemNetworkInfoSource: NetworkInfoSource {
    private var probe: NWConnection?

    func link() -> NetworkLink {
        let interfaces = Self.addresses()
        let wifi = CWWiFiClient.shared().interface()
        if let name = wifi?.interfaceName, let address = interfaces[name] {
            return NetworkLink(kind: .wifi, name: wifi?.ssid(), localAddress: address)
        }
        if let wired = interfaces.filter({ $0.key.hasPrefix("en") }).sorted(by: { $0.key < $1.key }).first {
            return NetworkLink(kind: .wired, name: nil, localAddress: wired.value)
        }
        return NetworkLink(kind: .none, name: nil, localAddress: nil)
    }

    private static func addresses() -> [String: String] {
        var result: [String: String] = [:]
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else { return result }
        defer { freeifaddrs(first) }
        for pointer in sequence(first: start, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: entry.ifa_name)
            if result[name] == nil { result[name] = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        }
        return result
    }

    func measureLatency(_ completion: @escaping @MainActor (Double?) -> Void) {
        probe?.cancel()
        let start = Date()
        let connection = NWConnection(host: "1.1.1.1", port: 443, using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let ms = (Date().timeIntervalSince(start) * 1000).rounded()
                connection.cancel()
                Task { @MainActor in completion(ms) }
            case .failed, .waiting:
                connection.cancel()
                Task { @MainActor in completion(nil) }
            default:
                break
            }
        }
        probe = connection
        connection.start(queue: .global(qos: .utility))
    }

    func fetchPublicAddress(_ completion: @escaping @MainActor (String?) -> Void) {
        Task {
            guard let url = URL(string: "https://api.ipify.org") else { return completion(nil) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            guard let (data, _) = try? await URLSession.shared.data(for: request) else { return completion(nil) }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            completion(text.count <= 45 && !text.isEmpty ? text : nil)
        }
    }
}

@MainActor
final class SystemDisplaySource: DisplaySource {
    private typealias Getter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (UInt32, Float) -> Int32

    private static let displayServices: (get: Getter, set: Setter)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness")
        else { return nil }
        return (unsafeBitCast(get, to: Getter.self), unsafeBitCast(set, to: Setter.self))
    }()

    func brightness() -> Double? {
        guard let displayServices = Self.displayServices else { return nil }
        var value: Float = 0
        return displayServices.get(CGMainDisplayID(), &value) == 0 ? Double(value) : nil
    }

    func setBrightness(_ value: Double) -> Bool {
        guard let displayServices = Self.displayServices else { return false }
        var ok = false
        for id in Self.activeDisplayIDs() where displayServices.set(id, Float(value)) == 0 { ok = true }
        return ok
    }

    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [CGMainDisplayID()] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [CGMainDisplayID()] }
        return ids
    }
}

@MainActor
final class SystemWallpaperSource: WallpaperSource {
    private var cache: [String: Data] = [:]

    func appleWallpapers() -> [AppleWallpaper] {
        AppleWallpaper.all()
    }

    func current() -> String? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)?.path
    }

    func set(_ path: String, screen: String?) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let screens = NSScreen.screens.filter { screen == nil || ScreenInfo.key(name: $0.localizedName, frame: $0.frame) == screen }
        guard !screens.isEmpty else { return false }
        var ok = true
        for target in screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: target, options: [:])
            } catch {
                ok = false
            }
        }
        return ok
    }

    func thumbnail(_ path: String) -> Data? {
        if let hit = cache[path] { return hit }
        guard let data = ThumbnailData.png(path, side: 128) else { return nil }
        cache[path] = data
        return data
    }
}

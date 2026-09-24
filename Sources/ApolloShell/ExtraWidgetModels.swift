import AppKit
import ApolloShellCore
import CoreWLAN
import ImageIO
import Network
import Observation
import OSLog

// The models behind the widgets of 09/23. Each one only works while it has
// to: the files, the connection, the drives and the photos while the
// dashboard is open (`DashboardExtras.start`), the timer and the clipboard
// history also closed - a timer has to ring, and a history has to see what
// was copied in between.

/// Everything the new widgets draw from, in one place for `WidgetContext`.
@MainActor
final class DashboardExtras {
    let timer: ShellTimer
    let clipboard: ClipboardHistory
    let files: RecentFilesModel
    let network: NetworkInfoModel
    let drives: DrivesModel
    let photos: PhotoFrames

    init(timer: ShellTimer = .shared, clipboard: ClipboardHistory = .shared, files: RecentFilesModel = RecentFilesModel(),
         network: NetworkInfoModel = NetworkInfoModel(), drives: DrivesModel = DrivesModel(),
         photos: PhotoFrames = PhotoFrames()) {
        self.timer = timer
        self.clipboard = clipboard
        self.files = files
        self.network = network
        self.drives = drives
        self.photos = photos
    }

    /// The dashboard opens (or a page is shown): start what its widgets need.
    func start(for widgets: [WidgetInstance]) {
        let kinds = Set(widgets.map(\.kind))
        if kinds.contains(.recentFiles) { files.start() }
        if kinds.contains(.networkInfo) {
            network.refresh(publicAddress: widgets.contains { $0.kind == .networkInfo && $0.options.publicAddress != false })
        }
        if kinds.contains(.drives) { drives.start() }
        if kinds.contains(.clipboard) { clipboard.start() }
    }

    func stop() {
        files.stop()
        drives.stop()
    }
}

// MARK: - Timer

/// The one timer of the shell: the dashboard widget, the control centre card
/// and the bar all show and steer the same. It rings at the end even with
/// every panel closed (`onFinish`: a toast and a sound, wired in the app).
@MainActor
@Observable
final class ShellTimer {
    static let shared = ShellTimer()

    private(set) var state = ShellTimerState()
    @ObservationIgnored var onFinish: (ShellTimerState) -> Void = { _ in }
    @ObservationIgnored private var alarm: Timer?
    /// A fixed moment for image samples.
    @ObservationIgnored var fixedNow: Date?

    var now: Date { fixedNow ?? Date() }

    func set(mode: ShellTimerState.Mode, minutes: Int? = nil) {
        guard mode != state.mode || state.isIdle else { return }
        state.set(mode: mode, length: minutes.map { TimeInterval($0 * 60) })
        schedule()
    }

    /// The widget's own minutes, as long as nothing runs.
    func prepare(minutes: Int) {
        guard state.isIdle, state.mode == .timer, state.length != TimeInterval(minutes * 60) else { return }
        state.set(mode: .timer, length: TimeInterval(minutes * 60))
    }

    func toggle() {
        if state.isRunning { state.pause(at: now) } else { state.start(at: now) }
        schedule()
    }

    func reset() {
        state.reset()
        schedule()
    }

    /// Plus or minus whole minutes on an idle timer.
    func adjust(minutes: Int) {
        guard state.isIdle, state.mode == .timer else { return }
        let next = max(1, min(600, Int(state.length / 60) + minutes))
        state.set(mode: .timer, length: TimeInterval(next * 60))
    }

    private func schedule() {
        alarm?.invalidate()
        alarm = nil
        guard state.isRunning, let remaining = state.remaining(at: now) else { return }
        let timer = Timer(timeInterval: max(remaining, 0.05), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.ring() }
        }
        RunLoop.main.add(timer, forMode: .common)
        alarm = timer
    }

    private func ring() {
        let finished = state
        state.finish()
        onFinish(finished)
    }

    static func preview(_ state: (ShellTimer) -> Void, now: Date) -> ShellTimer {
        let timer = ShellTimer()
        timer.fixedNow = now
        state(timer)
        return timer
    }
}

// MARK: - Clipboard

/// The last copied texts. Watches the general pasteboard's change count
/// twice a second (macOS has no notification for it) - comparing a number,
/// nearly free. Skips what password managers mark as secret; keeps
/// everything in memory only, nothing goes to disk.
@MainActor
@Observable
final class ClipboardHistory {
    static let shared = ClipboardHistory()

    private(set) var list = ClipboardList()
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var lastChange = NSPasteboard.general.changeCount
    /// What we put there ourselves: not a new entry, only a move to the top.
    @ObservationIgnored private var ownChange: Int?

    func start() {
        guard poll == nil else { return }
        lastChange = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    func stop() {
        poll?.invalidate()
        poll = nil
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        guard lastChange != ownChange else { return }
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard ClipboardList.records(types: types), let text = pasteboard.string(forType: .string) else { return }
        list.add(text)
    }

    /// Back onto the clipboard, ready to paste.
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        ownChange = pasteboard.changeCount
        lastChange = pasteboard.changeCount
        list.add(text)
    }

    func remove(_ text: String) { list.remove(text) }
    func clear() { list.clear() }

    static func preview(_ texts: [String]) -> ClipboardHistory {
        let history = ClipboardHistory()
        for text in texts.reversed() { history.list.add(text) }
        return history
    }
}

// MARK: - Recent files

struct RecentFile: Identifiable, Equatable {
    let url: URL
    let name: String
    let used: Date
    var id: URL { url }
}

/// Files and folders used in the last seven days, from Spotlight
/// (`kMDItemLastUsedDate`) - no permission needed, it is the index the Finder's
/// "Recents" uses too. Queried on opening, not kept live.
@MainActor
@Observable
final class RecentFilesModel {
    static let limit = 16
    private(set) var files: [RecentFile] = []
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observer: NSObjectProtocol?

    func start() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        let since = Date().addingTimeInterval(-7 * 86_400) as NSDate
        query.predicate = NSPredicate(format: "kMDItemLastUsedDate >= %@ AND kMDItemContentType != 'com.apple.application-bundle'", since)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.collect() }
        }
        self.query = query
        query.start()
    }

    func stop() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func collect() {
        guard let query else { return }
        query.disableUpdates()
        var result: [RecentFile] = []
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let used = item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date else { continue }
            // Hidden and Library files are the apps' business, not the user's.
            if path.contains("/.") || path.contains("/Library/") { continue }
            let url = URL(fileURLWithPath: path)
            result.append(RecentFile(url: url, name: FileManager.default.displayName(atPath: path), used: used))
            if result.count == Self.limit { break }
        }
        files = result
        query.stop()
    }

    func open(_ file: RecentFile) { NSWorkspace.shared.open(file.url) }
    func reveal(_ file: RecentFile) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }

    static func preview(_ files: [RecentFile]) -> RecentFilesModel {
        let model = RecentFilesModel()
        model.files = files
        return model
    }
}

// MARK: - Connection

/// Wi-Fi name, local and public address, and how fast a server answers.
/// Refreshed on opening. The Wi-Fi name needs the location permission on
/// current macOS; without it the widget says "Wi-Fi" instead of guessing.
@MainActor
@Observable
final class NetworkInfoModel {
    enum Link: Equatable { case wifi(String?), wired, none }

    private(set) var link: Link = .none
    private(set) var localAddress: String?
    private(set) var publicAddress: String?
    /// Milliseconds to open a connection to 1.1.1.1:443.
    private(set) var latency: Int?
    @ObservationIgnored private var publicFetchedAt: Date?
    @ObservationIgnored private var probe: NWConnection?

    func refresh(publicAddress wantsPublic: Bool) {
        let interfaces = Self.addresses()
        let wifi = CWWiFiClient.shared().interface()
        if let name = wifi?.interfaceName, let address = interfaces[name] {
            link = .wifi(wifi?.ssid())
            localAddress = address
        } else if let wired = interfaces.first(where: { $0.key.hasPrefix("en") }) {
            link = .wired
            localAddress = wired.value
        } else {
            link = .none
            localAddress = nil
        }
        measureLatency()
        if wantsPublic, publicFetchedAt.map({ Date().timeIntervalSince($0) > 600 }) ?? true { fetchPublic() }
        if !wantsPublic { publicAddress = nil }
    }

    /// IPv4 per interface, up and not loopback.
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
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
                              NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: entry.ifa_name)
            if result[name] == nil { result[name] = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        }
        return result
    }

    private func measureLatency() {
        probe?.cancel()
        let start = Date()
        let connection = NWConnection(host: "1.1.1.1", port: 443, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                connection.cancel()
                Task { @MainActor in self?.latency = ms }
            case .failed, .waiting:
                connection.cancel()
                Task { @MainActor in self?.latency = nil }
            default: break
            }
        }
        probe = connection
        connection.start(queue: .global(qos: .utility))
    }

    /// ipify answers with the plain address and keeps no logs (its own words).
    private func fetchPublic() {
        publicFetchedAt = Date()
        Task { [weak self] in
            var request = URLRequest(url: URL(string: "https://api.ipify.org")!)
            request.timeoutInterval = 5
            guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= 45, !text.isEmpty else { return }
            self?.publicAddress = text
        }
    }

    static func preview(link: Link, local: String?, public address: String?, latency: Int?) -> NetworkInfoModel {
        let model = NetworkInfoModel()
        model.link = link
        model.localAddress = local
        model.publicAddress = address
        model.latency = latency
        return model
    }
}

// MARK: - Drives

struct DriveInfo: Identifiable, Equatable {
    let url: URL
    let name: String
    let total: Int64
    let free: Int64
    let ejectable: Bool
    var id: URL { url }
    var usedFraction: Double { total > 0 ? Double(total - free) / Double(total) : 0 }
}

/// The mounted volumes; while open it follows mounting and ejecting.
@MainActor
@Observable
final class DrivesModel {
    private(set) var drives: [DriveInfo] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private let log = Logger(category: "drives")

    func start() {
        refresh()
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func stop() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    func refresh() {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsEjectableKey,
                                      .volumeIsRemovableKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        drives = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable != false,
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }
            // The system volume's snapshot sits under /System/Volumes: not a drive of its own.
            if url.path.hasPrefix("/System/Volumes") { return nil }
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0
            return DriveInfo(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent, total: Int64(total),
                             free: free, ejectable: (values.volumeIsEjectable ?? false) || (values.volumeIsRemovable ?? false))
        }
    }

    func eject(_ drive: DriveInfo) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: drive.url)
        } catch {
            log.error("Eject failed: \((error as NSError).code, privacy: .public)")
        }
        refresh()
    }

    func reveal(_ drive: DriveInfo) { NSWorkspace.shared.open(drive.url) }

    static func preview(_ drives: [DriveInfo]) -> DrivesModel {
        let model = DrivesModel()
        model.drives = drives
        return model
    }
}

// MARK: - Photos

/// The pictures of a folder for the photo frame, and their thumbnails -
/// read once per folder, the thumbnails loaded off the main thread at the
/// size the widget needs at most.
@MainActor
@Observable
final class PhotoFrames {
    private(set) var images: [URL: NSImage] = [:]
    @ObservationIgnored private var lists: [String: [URL]] = [:]
    @ObservationIgnored private var loading: Set<URL> = []

    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "webp"]
    static let defaultFolder = "~/Pictures"

    /// The pictures of a folder (first level only), sorted by name.
    func pictures(in folder: String?) -> [URL] {
        let path = NSString(string: folder?.isEmpty == false ? folder! : Self.defaultFolder).expandingTildeInPath
        if let hit = lists[path] { return hit }
        let contents = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path),
                                                                     includingPropertiesForKeys: nil,
                                                                     options: [.skipsHiddenFiles])) ?? []
        let pictures = contents.filter { Self.extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        lists[path] = pictures
        return pictures
    }

    func image(_ url: URL) -> NSImage? {
        if let image = images[url] { return image }
        guard !loading.contains(url) else { return nil }
        loading.insert(url)
        Task.detached(priority: .utility) {
            let thumbnail = Self.thumbnail(url, side: 1200)
            await MainActor.run { [weak self] in
                self?.loading.remove(url)
                if let thumbnail { self?.images[url] = NSImage(cgImage: thumbnail, size: .zero) }
            }
        }
        return nil
    }

    nonisolated private static func thumbnail(_ url: URL, side: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: side]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func preview(folder: String, images: [NSImage]) -> PhotoFrames {
        let model = PhotoFrames()
        let path = NSString(string: folder).expandingTildeInPath
        let urls = images.indices.map { URL(fileURLWithPath: "\(path)/sample-\($0).png") }
        model.lists[path] = urls
        for (url, image) in zip(urls, images) { model.images[url] = image }
        return model
    }
}

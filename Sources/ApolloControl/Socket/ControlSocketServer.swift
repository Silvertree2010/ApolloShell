import Foundation

public final class ControlSocketServer: @unchecked Sendable {
    public let path: String
    private let service: any ControlService
    private let queue = DispatchQueue(label: "apollo.control.accept")
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var source: (any DispatchSourceRead)?
    private var connections: [ObjectIdentifier: ControlConnection] = [:]

    public init(path: String, service: any ControlService) {
        self.path = path
        self.service = service
    }

    public func start() throws {
        _ = try SocketAddress.make(path)
        try clearStaleSocket()
        try createParentFolder()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlSocketError.system("socket", errno) }
        guard try SocketAddress.bind(fd, path) == 0 else {
            let code = errno
            close(fd)
            throw ControlSocketError.system("bind", code)
        }
        guard chmod(path, 0o600) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw ControlSocketError.system("chmod", code)
        }
        guard listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw ControlSocketError.system("listen", code)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        lock.withLock {
            listener = fd
            self.source = source
        }
        source.resume()
    }

    public func stop() {
        let (source, open) = lock.withLock { () -> ((any DispatchSourceRead)?, [ControlConnection]) in
            let result = (self.source, Array(connections.values))
            self.source = nil
            listener = -1
            connections = [:]
            return result
        }
        guard let source else { return }
        source.cancel()
        unlink(path)
        for connection in open {
            connection.shutdown()
        }
    }

    private func clearStaleSocket() throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK else { throw ControlSocketError.occupied(path) }
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(probe) }
        if try SocketAddress.connect(probe, path) == 0 {
            throw ControlSocketError.alreadyRunning(path)
        }
        unlink(path)
    }

    private func createParentFolder() throws {
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty, !FileManager.default.fileExists(atPath: parent) else { return }
        do {
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw ControlSocketError.system("mkdir", EACCES)
        }
    }

    private func acceptPending() {
        let fd = lock.withLock { listener }
        guard fd >= 0 else { return }
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            SocketAddress.noSigPipe(client)
            SocketAddress.sendTimeout(client, seconds: 5)
            let connection = ControlConnection(fd: client, service: service) { [weak self] finished in
                guard let self else { return }
                _ = self.lock.withLock { self.connections.removeValue(forKey: ObjectIdentifier(finished)) }
            }
            lock.withLock { connections[ObjectIdentifier(connection)] = connection }
            connection.start()
        }
    }
}

final class ControlConnection: @unchecked Sendable {
    private let fd: Int32
    private let service: any ControlService
    private let queue = DispatchQueue(label: "apollo.control.connection")
    private let lock = NSLock()
    private var buffer = LineBuffer()
    private var source: (any DispatchSourceRead)?
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var nextTask = 0
    private var active = 0
    private var streaming: Set<Int> = []
    private var inputClosed = false
    private var suspended = false
    private var closed = false
    private let onFinish: @Sendable (ControlConnection) -> Void

    init(fd: Int32, service: any ControlService, onFinish: @escaping @Sendable (ControlConnection) -> Void) {
        self.fd = fd
        self.service = service
        self.onFinish = onFinish
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        let fd = self.fd
        source.setCancelHandler { close(fd) }
        lock.withLock { self.source = source }
        source.resume()
    }

    func shutdown() {
        let (source, running, wasSuspended) = lock.withLock { () -> ((any DispatchSourceRead)?, [Task<Void, Never>], Bool) in
            closed = true
            let result = (self.source, Array(tasks.values), suspended)
            self.source = nil
            tasks = [:]
            suspended = false
            return result
        }
        for task in running { task.cancel() }
        source?.cancel()
        if wasSuspended { source?.resume() }
        onFinish(self)
    }

    private func inputEnded() {
        let (idle, streams) = lock.withLock { () -> (Bool, [Task<Void, Never>]) in
            inputClosed = true
            guard active > 0 else { return (true, []) }
            if let source, !suspended {
                source.suspend()
                suspended = true
            }
            return (false, streaming.compactMap { tasks[$0] })
        }
        if idle { shutdown() }
        for task in streams { task.cancel() }
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard count > 0 else {
            if count < 0, errno == EINTR || errno == EAGAIN { return }
            if count == 0 {
                inputEnded()
            } else {
                shutdown()
            }
            return
        }
        let lines = buffer.append(chunk[..<count])
        guard !buffer.overflowed else {
            _ = write(ControlResponse(id: nil, outcome: .failure("Request line too long.")))
            shutdown()
            return
        }
        for line in lines {
            handle(line)
        }
    }

    private func handle(_ line: String) {
        switch ControlRequest.parse(line) {
        case .failure(let error):
            _ = write(ControlResponse(id: error.id, outcome: .failure(error.message)))
        case .success(let request):
            let key = lock.withLock { () -> Int in
                nextTask += 1
                active += 1
                return nextTask
            }
            let task = Task { [weak self] in
                guard let self else { return }
                await self.serve(request, key: key)
                let drained = self.lock.withLock { () -> Bool in
                    self.tasks.removeValue(forKey: key)
                    self.streaming.remove(key)
                    self.active -= 1
                    return self.inputClosed && self.active == 0 && !self.closed
                }
                if drained { self.shutdown() }
            }
            lock.withLock {
                if closed { task.cancel() } else { tasks[key] = task }
            }
        }
    }

    private func serve(_ request: ControlRequest, key: Int) async {
        switch await service.reply(to: request) {
        case .success(let value):
            _ = write(ControlResponse(id: request.id, outcome: .success(value)))
        case .failure(let message):
            _ = write(ControlResponse(id: request.id, outcome: .failure(message)))
        case .stream(let stream):
            let ended = lock.withLock { () -> Bool in
                guard !inputClosed else { return true }
                streaming.insert(key)
                return false
            }
            guard !ended else { return }
            for await value in stream {
                guard write(ControlResponse(id: request.id, outcome: .success(value))) else { break }
            }
        }
    }

    private func write(_ response: ControlResponse) -> Bool {
        lock.withLock {
            guard !closed else { return false }
            return SocketAddress.writeAll(fd, response.line + "\n")
        }
    }
}

import Foundation

/// Unix-domain sockets for the bridge ⇄ app link. The socket file is 0600 in
/// the user's Library and peers must run as the same user.
enum UnixSocket {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func withAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    private static func noSigpipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    static func connect(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        noSigpipe(fd)
        guard withAddress(path, { Darwin.connect(fd, $0, $1) }) == 0 else { close(fd); return nil }
        return fd
    }

    static func listen(_ path: String) throws -> Int32 {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if let other = connect(path) {
            close(other)
            throw Failure(message: "Another copy of Halo is already connected to Claude.")
        }
        unlink(path)   // left behind by a crash
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(message: "Couldn’t create a socket (\(String(cString: strerror(errno)))).") }
        guard withAddress(path, { Darwin.bind(fd, $0, $1) }) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw Failure(message: "Couldn’t listen at \(path) (\(reason)).")
        }
        chmod(path, 0o600)
        guard Darwin.listen(fd, 8) == 0 else { close(fd); unlink(path); throw Failure(message: "Couldn’t listen for Claude.") }
        return fd
    }

    /// Writes everything, retrying partial writes.
    @discardableResult
    static func write(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard var p = raw.baseAddress else { return true }
            var left = raw.count
            while left > 0 {
                let n = Darwin.write(fd, p, left)
                if n < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    return false
                }
                left -= n
                p = p.advanced(by: n)
            }
            return true
        }
    }

    /// Accepts the uid check: only processes of this user may talk to Halo.
    static func peerIsSameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    static func prepareAccepted(_ fd: Int32) { noSigpipe(fd) }
}

/// Splits a byte stream into newline-terminated lines.
struct LineBuffer {
    private var buffer = Data()

    mutating func append(_ bytes: UnsafeRawBufferPointer) -> [Data] {
        buffer.append(contentsOf: bytes)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            if !line.isEmpty { lines.append(Data(line)) }
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }
}

/// The app side: accepts bridge connections.
final class MCPListener: @unchecked Sendable {
    let path: String
    private let fd: Int32
    private let source: DispatchSourceRead

    init(path: String, onAccept: @escaping @Sendable (Int32) -> Void) throws {
        self.path = path
        fd = try UnixSocket.listen(path)
        let fd = fd
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "halo.mcp.accept"))
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            guard UnixSocket.peerIsSameUser(client) else { close(client); return }
            UnixSocket.prepareAccepted(client)
            onAccept(client)
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
    }

    func stop() {
        source.cancel()
        unlink(path)
    }
}

/// One bridge (one Claude client) talking to the app.
final class MCPConnection: @unchecked Sendable {
    private let fd: Int32
    private let source: DispatchSourceRead
    private let writes = DispatchQueue(label: "halo.mcp.write")
    private var lines = LineBuffer()
    private var closed = false

    init(fd: Int32, onLine: @escaping @Sendable (Data) -> Void, onClose: @escaping @Sendable () -> Void) {
        self.fd = fd
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "halo.mcp.read"))
        source.setEventHandler { [unowned self] in
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            guard n > 0 else { source.cancel(); return }
            for line in chunk.withUnsafeBytes({ lines.append(UnsafeRawBufferPointer(rebasing: $0[..<n])) }) { onLine(line) }
        }
        source.setCancelHandler { [writes] in
            writes.sync { _ = Darwin.close(fd) }
            onClose()
        }
        source.resume()
    }

    func send(_ data: Data) {
        writes.async { [fd] in UnixSocket.write(fd, data) }
    }

    func close() {
        guard !closed else { return }
        closed = true
        source.cancel()
    }
}

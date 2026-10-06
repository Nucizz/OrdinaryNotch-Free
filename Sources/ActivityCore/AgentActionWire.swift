import Foundation
import Darwin

/// Local, length-prefixed JSON. Both ends must belong to the current macOS user.
public enum AgentActionWire {
    public static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OrdinaryNotch/Actions/input.sock")
    }
    public static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw Failure.unavailable }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }
    public static func connect(_ path: String, timeout: Int = 5) throws -> Int32 {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else { throw Failure.unavailable }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.unavailable }
        configure(fd, timeout: timeout)
        do {
            var address = try address(path)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard result == 0, sameUser(fd) else { throw Failure.unavailable }
            return fd
        } catch { close(fd); throw error }
    }
    public static func configure(_ fd: Int32, timeout: Int) {
        var seconds = timeval(tv_sec: timeout, tv_usec: 0), one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &seconds, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &seconds, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }
    public static func sameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0, gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }
    public static func send(_ value: [String: Any], to fd: Int32) throws {
        let body = try JSONSerialization.data(withJSONObject: value)
        guard body.count <= 8 * 1024 * 1024 else { throw Failure.invalid }
        var length = UInt32(body.count).littleEndian
        var data = withUnsafeBytes(of: &length) { Data($0) }; data.append(body)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw Failure.unavailable }; offset += count
            }
        }
    }
    public static func receive(from fd: Int32) throws -> [String: Any] {
        let header = try read(4, fd: fd)
        let count = header.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard count > 0, count <= 8 * 1024 * 1024 else { throw Failure.invalid }
        guard let value = try JSONSerialization.jsonObject(with: read(count, fd: fd)) as? [String: Any] else { throw Failure.invalid }
        return value
    }
    private static func read(_ count: Int, fd: Int32) throws -> Data {
        var result = Data(count: count)
        try result.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let read = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), count - offset)
                guard read > 0 else { throw Failure.unavailable }; offset += read
            }
        }
        return result
    }
    public enum Failure: LocalizedError {
        case unavailable, invalid, expired
        public var errorDescription: String? {
            switch self {
            case .unavailable: return "The agent connection is unavailable. Open the task and answer there."
            case .invalid: return "This prompt format is not supported. Open the task to continue."
            case .expired: return "This request is no longer waiting for an answer."
            }
        }
    }
}

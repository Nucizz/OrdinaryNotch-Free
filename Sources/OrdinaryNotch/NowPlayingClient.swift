import AppKit

struct NowPlayingSnapshot: Decodable {
    let bundleIdentifier: String
    let parentApplicationBundleIdentifier: String?
    let title: String
    let artist: String?
    let playing: Bool
    let durationMicros: Double?
    var elapsedTimeMicros: Double?
    var timestampEpochMicros: Double?
    let playbackRate: Double?
    let artworkData: String?
    var album: String? = nil

    var duration: Double { max(0, durationMicros ?? 0) / 1_000_000 }
    func position(at date: Date) -> Double {
        let elapsed = max(0, elapsedTimeMicros ?? 0) / 1_000_000
        let delta = timestampEpochMicros.map { max(0, date.timeIntervalSince1970 - $0 / 1_000_000) } ?? 0
        let value = elapsed + (playing ? delta * max(0, playbackRate ?? 1) : 0)
        return duration > 0 ? min(duration, value) : value
    }
    static func decodeEvent(_ data: Data) throws -> NowPlayingSnapshot? {
        // Inspect the envelope before decoding: an empty payload explicitly clears playback.
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "data", json["diff"] as? Bool == false,
              let payload = json["payload"] as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        if payload.isEmpty { return nil }
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}

/// Playback-state notifications can arrive before a player's new timestamp/position.
struct NowPlayingTimeline {
    private var reported: NowPlayingSnapshot?
    private(set) var snapshot: NowPlayingSnapshot?
    mutating func update(_ next: NowPlayingSnapshot?, at now: Date) {
        defer { reported = next }
        guard var next else { snapshot = nil; return }
        if let reported, let current = snapshot,
           reported.bundleIdentifier == next.bundleIdentifier, reported.title == next.title,
           reported.artist == next.artist,
           reported.timestampEpochMicros == next.timestampEpochMicros,
           reported.elapsedTimeMicros == next.elapsedTimeMicros {
            if reported.playing != next.playing {
                next.elapsedTimeMicros = current.position(at: now) * 1_000_000
                next.timestampEpochMicros = now.timeIntervalSince1970 * 1_000_000
            } else {
                next.elapsedTimeMicros = current.elapsedTimeMicros
                next.timestampEpochMicros = current.timestampEpochMicros
            }
        }
        snapshot = next
    }
}

/// Newline framing is independent of pipe read boundaries; artwork can span many chunks.
struct NowPlayingFrames {
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        guard buffer.count <= 16 * 1024 * 1024 else { buffer.removeAll(); throw CocoaError(.fileReadTooLarge) }
        var frames: [Data] = []
        while let end = buffer.firstIndex(of: 10) {
            let frame = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            if !frame.isEmpty { frames.append(frame) }
        }
        return frames
    }
}

private final class NowPlayingPipe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ordinary.now-playing.decode", qos: .utility)
    private var frames = NowPlayingFrames()
    func consume(_ data: Data, receive: @escaping @Sendable (Result<NowPlayingSnapshot?, Error>) -> Void) {
        queue.async {
            do {
                for frame in try self.frames.append(data) { receive(Result { try NowPlayingSnapshot.decodeEvent(frame) }) }
            } catch { receive(.failure(error)) }
        }
    }
}

@MainActor
final class NowPlayingClient {
    private var process: Process?
    private var output: Pipe?
    private var generation = UUID()
    private var retryAfter = Date.distantPast
    private var commands: [UUID: Process] = [:]
    private var resources: URL? { Bundle.main.resourceURL }
    private var script: URL? { resources?.appendingPathComponent("mediaremote-adapter.pl") }
    private var framework: URL? { resources?.appendingPathComponent("MediaRemoteAdapter.framework") }

    func start(receive: @escaping @MainActor (Result<NowPlayingSnapshot?, Error>) -> Void) -> Bool {
        guard let script, let framework,
              FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: framework.path) else { return false }
        if process?.isRunning == true || Date() < retryAfter { return true }
        generation = UUID()
        let token = generation
        let process = Process(), output = Pipe(), decoder = NowPlayingPipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path, "stream", "--no-diff", "--micros", "--debounce=80"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            decoder.consume(data) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard self?.generation == token else { return }
                    receive(result)
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.output?.fileHandleForReading.readabilityHandler = nil
                self.output = nil; self.process = nil
                self.retryAfter = Date().addingTimeInterval(3)
                receive(.failure(CocoaError(.executableRuntimeMismatch)))
            }
        }
        self.process = process; self.output = output
        do { try process.run() }
        catch {
            output.fileHandleForReading.readabilityHandler = nil
            self.process = nil; self.output = nil
            retryAfter = Date().addingTimeInterval(3)
            receive(.failure(error))
        }
        return true
    }

    func send(_ command: String, completion: @escaping @MainActor (Bool) -> Void) {
        guard let number = ["playpause": 2, "next track": 4, "previous track": 5][command],
              let script, let framework else { completion(false); return }
        let process = Process(), id = UUID()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path, "send", String(number)]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        commands[id] = process
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard self?.commands.removeValue(forKey: id) != nil else { return }
                completion(process.terminationStatus == 0)
            }
        }
        do { try process.run() }
        catch { commands[id] = nil; completion(false); return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if let pending = self?.commands[id], pending.isRunning { pending.terminate() }
        }
    }
    func stop() {
        generation = UUID()
        output?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning { process.terminate() }
        for process in commands.values where process.isRunning { process.terminate() }
        commands.removeAll(); output = nil; process = nil
    }
}

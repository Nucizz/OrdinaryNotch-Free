import Foundation

struct LyricsTrack: Hashable, Sendable {
    let title: String
    let artist: String
    let duration: Int
    let album: String?
    init?(title: String, artist: String, duration: Double, album: String? = nil) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty, duration.isFinite, duration > 0, duration < 86400 else { return nil }
        self.title = title; self.artist = artist; self.duration = Int(duration.rounded())
        let album = album?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.album = album?.isEmpty == false ? album : nil
    }
}

struct LyricLine: Equatable, Sendable {
    let time: Double
    let text: String
}

enum TimedLyrics {
    static func parse(_ lrc: String) -> [LyricLine] {
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d+):([0-5]\d)(?:[.:](\d{1,3}))?\]"#)
        let offsetTag = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let wordTag = try! NSRegularExpression(pattern: #"<\d+:[0-5]\d(?:\.\d{1,3})?>"#)
        let source = lrc as NSString
        let offsetMatch = offsetTag.firstMatch(in: lrc, range: NSRange(location: 0, length: source.length))
        let offset = offsetMatch.flatMap { Double(source.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        var byTime: [Double: [String]] = [:]
        for raw in lrc.components(separatedBy: .newlines) {
            let line = raw as NSString
            let matches = timestamp.matches(in: raw, range: NSRange(location: 0, length: line.length))
            guard let last = matches.last else { continue }
            let content = line.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            let text = wordTag.stringByReplacingMatches(in: content, range: NSRange(location: 0, length: (content as NSString).length), withTemplate: "")
            for match in matches {
                guard let minutes = Double(line.substring(with: match.range(at: 1))),
                      let seconds = Double(line.substring(with: match.range(at: 2))) else { continue }
                let fraction = match.range(at: 3).location == NSNotFound ? 0 : Double("0." + line.substring(with: match.range(at: 3))) ?? 0
                let time = max(0, minutes * 60 + seconds + fraction - offset)
                guard time.isFinite else { continue }
                if byTime[time]?.contains(text) != true { byTime[time, default: []].append(text) }
            }
        }
        return byTime.keys.sorted().map { LyricLine(time: $0, text: byTime[$0]!.joined(separator: "\n")) }
    }

    static func current(in lines: [LyricLine], at position: Double) -> LyricLine? {
        guard position.isFinite, position >= 0 else { return nil }
        var lower = 0, upper = lines.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lines[middle].time <= position { lower = middle + 1 } else { upper = middle }
        }
        return lower > 0 ? lines[lower - 1] : nil
    }
}

enum LyricsSource: String, Sendable {
    case lrclib = "LRCLIB", musixmatch = "Musixmatch"
}

enum LyricsResult: Equatable, Sendable {
    case synced([LyricLine], source: LyricsSource = .lrclib), unavailable, instrumental
}
protocol LyricsServing: Sendable {
    func fetch(_ track: LyricsTrack) async throws -> LyricsResult
}

/// Fetches only after the user enables lyrics. Requests contain track metadata, never audio or account tokens.
actor LyricsService: LyricsServing {
    private let session: URLSession
    private var cache: [LyricsTrack: LyricsResult] = [:]
    private var cacheOrder: [LyricsTrack] = []
    private var nextRequestAt = Date.distantPast
    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    static func request(for track: LyricsTrack) -> URLRequest {
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: track.title),
                         URLQueryItem(name: "artist_name", value: track.artist),
                         URLQueryItem(name: "duration", value: String(track.duration))]
        if let album = track.album { url.queryItems?.append(URLQueryItem(name: "album_name", value: album)) }
        var request = URLRequest(url: url.url!, timeoutInterval: 12)
        request.setValue("OrdinaryNotch/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func fetch(_ track: LyricsTrack) async throws -> LyricsResult {
        if let result = cache[track] { return result }
        let delay = nextRequestAt.timeIntervalSinceNow
        guard delay < 2 else { throw URLError(.resourceUnavailable) }
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        nextRequestAt = Date().addingTimeInterval(0.5)
        let (data, response) = try await session.data(for: Self.request(for: track))
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 429 {
            let header = response.value(forHTTPHeaderField: "Retry-After") ?? ""
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let seconds = Double(header) ?? formatter.date(from: header)?.timeIntervalSinceNow ?? 60
            nextRequestAt = Date().addingTimeInterval(max(1, seconds))
            throw URLError(.resourceUnavailable)
        }
        let result: LyricsResult
        if response.statusCode == 404 { result = .unavailable }
        else {
            guard response.statusCode == 200, data.count <= 1_048_576 else { throw URLError(.badServerResponse) }
            result = try Self.decode(data, for: track)
        }
        cache[track] = result; cacheOrder.append(track)
        if cacheOrder.count > 32 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
        return result
    }

    static func decode(_ data: Data, for track: LyricsTrack) throws -> LyricsResult {
        struct Record: Decodable {
            let trackName: String
            let artistName: String
            let albumName: String?
            let duration: Double
            let instrumental: Bool
            let syncedLyrics: String?
        }
        let record = try JSONDecoder().decode(Record.self, from: data)
        func key(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
        guard key(record.trackName) == key(track.title), key(record.artistName) == key(track.artist),
              abs(record.duration - Double(track.duration)) <= 2 else { return .unavailable }
        // Different releases can share title and duration but use different lyric timing.
        // Do not silently substitute another album when the player identifies this one.
        if let album = track.album {
            guard let recordedAlbum = record.albumName, key(recordedAlbum) == key(album) else { return .unavailable }
        }
        if record.instrumental { return .instrumental }
        let lines = TimedLyrics.parse(record.syncedLyrics ?? "")
        return lines.contains(where: { !$0.text.isEmpty }) ? .synced(lines) : .unavailable
    }
}

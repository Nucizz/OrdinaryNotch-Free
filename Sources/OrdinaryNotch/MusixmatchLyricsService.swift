import Foundation

/// Official API client. Each instance owns one key and its in-memory cache.
actor MusixmatchLyricsService: LyricsServing {
    private let apiKey: String
    private let session: URLSession
    private let fallback: (any LyricsServing)?
    private var nextRequestAt = Date.distantPast
    private var cache: [LyricsTrack: LyricsResult] = [:]
    private var cacheOrder: [LyricsTrack] = []

    init(apiKey: String, session: URLSession? = nil, fallback: (any LyricsServing)? = LyricsService()) {
        self.apiKey = apiKey
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: LyricsRedirectPolicy(), delegateQueue: nil)
        self.fallback = fallback
    }

    static func request(track: LyricsTrack, apiKey: String, trackID: Int? = nil) -> URLRequest {
        let method = trackID == nil ? "matcher.track.get" : "track.subtitle.get"
        var url = URLComponents(string: "https://api.musixmatch.com/ws/1.1/" + method)!
        var items = [URLQueryItem(name: "apikey", value: apiKey), URLQueryItem(name: "format", value: "json")]
        if let trackID {
            items += [URLQueryItem(name: "track_id", value: String(trackID)),
                      URLQueryItem(name: "subtitle_format", value: "lrc"),
                      URLQueryItem(name: "f_subtitle_length", value: String(track.duration)),
                      URLQueryItem(name: "f_subtitle_length_max_deviation", value: "2")]
        } else {
            items += [URLQueryItem(name: "q_track", value: track.title),
                      URLQueryItem(name: "q_artist", value: track.artist)]
        }
        url.queryItems = items
        var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("OrdinaryNotch/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func fetch(_ track: LyricsTrack) async throws -> LyricsResult {
        try Task.checkCancellation()
        if let value = cache[track] { return value }
        let primaryResult: LyricsResult
        do {
            let metadata = try await load(Self.request(track: track, apiKey: apiKey))
            if let match = try Self.match(metadata, for: track) {
                if match.instrumental { primaryResult = .instrumental }
                else {
                    primaryResult = try Self.decode(await load(Self.request(track: track, apiKey: apiKey, trackID: match.id)), for: track)
                }
            } else { primaryResult = .unavailable }
        } catch {
            try Task.checkCancellation()
            guard fallback != nil else { throw error }
            primaryResult = .unavailable
        }
        try Task.checkCancellation()
        let result: LyricsResult
        if primaryResult == .unavailable, let fallback { result = try await fallback.fetch(track) }
        else { result = primaryResult }
        try Task.checkCancellation()
        cache[track] = result; cacheOrder.append(track)
        if cacheOrder.count > 32 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
        return result
    }

    private func load(_ request: URLRequest) async throws -> Data {
        let delay = nextRequestAt.timeIntervalSinceNow
        guard delay < 2 else { throw URLError(.resourceUnavailable) }
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        nextRequestAt = Date().addingTimeInterval(0.5)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, data.count <= 1_048_576 else { throw URLError(.badServerResponse) }
        if response.statusCode == 429 {
            nextRequestAt = Date().addingTimeInterval(max(1, Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60))
            throw URLError(.resourceUnavailable)
        }
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? [String: Any],
           let header = message["header"] as? [String: Any], header["status_code"] as? Int == 429 {
            nextRequestAt = Date().addingTimeInterval(60)
            throw URLError(.resourceUnavailable)
        }
        return data
    }

    private static func body(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any], let header = message["header"] as? [String: Any],
              header["status_code"] as? Int == 200,
              let body = message["body"] as? [String: Any] else { throw URLError(.badServerResponse) }
        return body
    }

    static func match(_ data: Data, for track: LyricsTrack) throws -> (id: Int, instrumental: Bool)? {
        guard let metadata = try body(data)["track"] as? [String: Any],
              let id = metadata["track_id"] as? Int, id > 0,
              let title = metadata["track_name"] as? String, let artist = metadata["artist_name"] as? String else { return nil }
        func key(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        guard key(title) == key(track.title), key(artist) == key(track.artist), (metadata["restricted"] as? Int ?? 0) == 0 else { return nil }
        if let album = track.album {
            guard let value = metadata["album_name"] as? String, key(value) == key(album) else { return nil }
        }
        if let duration = metadata["track_length"] as? Double, duration > 0, abs(duration - Double(track.duration)) > 2 { return nil }
        return (id, metadata["instrumental"] as? Int == 1)
    }

    static func decode(_ data: Data, for track: LyricsTrack) throws -> LyricsResult {
        guard let subtitle = try body(data)["subtitle"] as? [String: Any],
              (subtitle["restricted"] as? Int ?? 0) == 0,
              let duration = subtitle["subtitle_length"] as? Double, abs(duration - Double(track.duration)) <= 2,
              let lrc = subtitle["subtitle_body"] as? String else { return .unavailable }
        let lines = TimedLyrics.parse(lrc)
        guard lines.contains(where: { !$0.text.isEmpty }), lines.allSatisfy({ $0.time <= Double(track.duration) + 2 }) else { return .unavailable }
        return .synced(lines, source: .musixmatch)
    }
}

/// Do not forward a user's key through redirects, including to another HTTPS host.
private final class LyricsRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

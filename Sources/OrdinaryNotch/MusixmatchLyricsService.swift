import Foundation

/// Uses the desktop API documented by Paxsenix0/MusixMatch-Lyrics.
/// Independent native client: verified HTTPS, memory-only tokens and strict recording matching.
actor MusixmatchLyricsService: LyricsServing {
    private let session: URLSession
    private let fallback: (any LyricsServing)?
    private var token: (value: String, expires: Date)?
    private var nextRequestAt = Date.distantPast
    private var cache: [LyricsTrack: LyricsResult] = [:]
    private var cacheOrder: [LyricsTrack] = []
    private enum Failure: Error { case unauthorized, unavailable }

    init(session: URLSession = URLSession(configuration: .ephemeral), fallback: (any LyricsServing)? = LyricsService()) {
        self.session = session; self.fallback = fallback
    }

    static func request(track: LyricsTrack? = nil, token: String? = nil) -> URLRequest {
        let method = track == nil ? "token.get" : "macro.subtitles.get"
        var url = URLComponents(string: "https://apic-desktop.musixmatch.com/ws/1.1/" + method)!
        var items = [URLQueryItem(name: "app_id", value: "web-desktop-app-v1.0")]
        if let track {
            items += [URLQueryItem(name: "format", value: "json"),
                      URLQueryItem(name: "namespace", value: "lyrics_richsynched"),
                      URLQueryItem(name: "subtitle_format", value: "lrc"),
                      URLQueryItem(name: "q_track", value: track.title),
                      URLQueryItem(name: "q_artist", value: track.artist),
                      URLQueryItem(name: "q_artists", value: track.artist),
                      URLQueryItem(name: "q_album", value: track.album ?? ""),
                      URLQueryItem(name: "q_duration", value: String(track.duration)),
                      URLQueryItem(name: "f_subtitle_length", value: String(track.duration)),
                      URLQueryItem(name: "f_subtitle_length_max_deviation", value: "2"),
                      URLQueryItem(name: "usertoken", value: token)]
        }
        url.queryItems = items
        var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("OrdinaryNotch/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AWSELBCORS=0; AWSELB=0;", forHTTPHeaderField: "Cookie")
        return request
    }

    func fetch(_ track: LyricsTrack) async throws -> LyricsResult {
        try Task.checkCancellation()
        if let value = cache[track] { return value }
        let primaryResult: LyricsResult
        do { primaryResult = try await primary(track) }
        catch {
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

    private func primary(_ track: LyricsTrack) async throws -> LyricsResult {
        for attempt in 0..<2 {
            do {
                let value = try await accessToken()
                return try Self.decode(await load(Self.request(track: track, token: value)), for: track)
            } catch Failure.unauthorized {
                token = nil
                if attempt == 1 { throw Failure.unauthorized }
            } catch Failure.unavailable { return .unavailable }
        }
        return .unavailable
    }

    private func accessToken() async throws -> String {
        if let token, token.expires > Date() { return token.value }
        let message = try Self.message(await load(Self.request()))
        guard let value = (message["body"] as? [String: Any])?["user_token"] as? String, !value.isEmpty else {
            throw URLError(.badServerResponse)
        }
        token = (value, Date().addingTimeInterval(600))
        return value
    }

    private func load(_ request: URLRequest) async throws -> Data {
        let delay = nextRequestAt.timeIntervalSinceNow
        guard delay < 2 else { throw URLError(.resourceUnavailable) }
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        nextRequestAt = Date().addingTimeInterval(0.5)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 429 {
            let header = response.value(forHTTPHeaderField: "Retry-After") ?? ""
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let delay = Double(header) ?? formatter.date(from: header)?.timeIntervalSinceNow ?? 60
            nextRequestAt = Date().addingTimeInterval(max(1, delay))
            throw URLError(.resourceUnavailable)
        }
        if [401, 403].contains(response.statusCode) { throw Failure.unauthorized }
        if response.statusCode == 404 { throw Failure.unavailable }
        guard response.statusCode == 200, data.count <= 1_048_576 else { throw URLError(.badServerResponse) }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? [String: Any],
           let header = message["header"] as? [String: Any], header["status_code"] as? Int == 429 {
            nextRequestAt = Date().addingTimeInterval(60)
            throw URLError(.resourceUnavailable)
        }
        return data
    }

    private static func message(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.badServerResponse) }
        return try message(object)
    }
    private static func message(_ object: [String: Any]) throws -> [String: Any] {
        guard let message = object["message"] as? [String: Any], let header = message["header"] as? [String: Any],
              let status = header["status_code"] as? Int else { throw URLError(.badServerResponse) }
        if [401, 403].contains(status) { throw Failure.unauthorized }
        if status == 404 { throw Failure.unavailable }
        guard status == 200 else { throw URLError(.badServerResponse) }
        return message
    }

    static func decode(_ data: Data, for track: LyricsTrack) throws -> LyricsResult {
        let response = try message(data)
        guard let body = response["body"] as? [String: Any], let calls = body["macro_calls"] as? [String: Any],
              let matching = calls["matcher.track.get"] as? [String: Any] else { return .unavailable }
        let matched = try message(matching)
        guard let metadata = (matched["body"] as? [String: Any])?["track"] as? [String: Any],
              let title = metadata["track_name"] as? String, let artist = metadata["artist_name"] as? String else { return .unavailable }
        func key(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        guard key(title) == key(track.title), key(artist) == key(track.artist), (metadata["restricted"] as? Int ?? 0) == 0 else { return .unavailable }
        if let album = track.album {
            guard let value = metadata["album_name"] as? String, key(value) == key(album) else { return .unavailable }
        }
        if let duration = metadata["track_length"] as? Double, duration > 0, abs(duration - Double(track.duration)) > 2 { return .unavailable }
        if metadata["instrumental"] as? Int == 1 { return .instrumental }
        guard let subtitles = calls["track.subtitles.get"] as? [String: Any] else { return .unavailable }
        let lyrics = try message(subtitles)
        guard let list = (lyrics["body"] as? [String: Any])?["subtitle_list"] as? [[String: Any]] else { return .unavailable }
        for item in list {
            guard let subtitle = item["subtitle"] as? [String: Any],
                  (subtitle["restricted"] as? Int ?? 0) == 0,
                  let duration = subtitle["subtitle_length"] as? Double, abs(duration - Double(track.duration)) <= 2,
                  let lrc = subtitle["subtitle_body"] as? String else { continue }
            let lines = TimedLyrics.parse(lrc)
            guard lines.contains(where: { !$0.text.isEmpty }), lines.allSatisfy({ $0.time <= Double(track.duration) + 2 }) else { continue }
            return .synced(lines, source: .musixmatch)
        }
        return .unavailable
    }
}

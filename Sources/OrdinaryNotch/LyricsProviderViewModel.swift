import Combine
import Foundation

@MainActor
final class LyricsProviderViewModel: ObservableObject {
    @Published var keyDraft = ""
    @Published private(set) var hasKey = false
    @Published private(set) var message: String?
    private let store: any LyricsKeyStoring
    private let lyrics: LyricsViewModel
    private let makeService: (String?) -> any LyricsServing
    private var loaded = false

    init(lyrics: LyricsViewModel, store: any LyricsKeyStoring = LyricsKeyStore(),
         makeService: @escaping (String?) -> any LyricsServing = { key in
             if let key { return MusixmatchLyricsService(apiKey: key) }
             return LyricsService()
         }) {
        self.lyrics = lyrics; self.store = store; self.makeService = makeService
    }
    func load() {
        guard !loaded else { return }
        loaded = true
        do {
            let key = try store.load()
            hasKey = key != nil
            lyrics.setService(makeService(key))
        } catch {
            message = "Couldn’t read your saved key. LRCLIB is in use. Paste your key to save it again."
        }
    }
    func save() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= 512, !key.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            message = "Paste a valid Musixmatch API key."
            return
        }
        do {
            try store.save(key)
            loaded = true; hasKey = true; keyDraft = ""
            lyrics.setService(makeService(key))
            message = "Key saved. Musixmatch is tried first, with LRCLIB as a fallback."
        } catch { message = "Couldn’t save the key in Keychain. Your lyrics provider has not changed." }
    }
    func remove() {
        do {
            try store.remove()
            loaded = true; hasKey = false; keyDraft = ""
            lyrics.setService(makeService(nil))
            message = "Key removed. Lyrics now come from LRCLIB."
        } catch { message = "Couldn’t remove the key from Keychain. Try again." }
    }
}

import SwiftUI

struct LyricsProviderSettingsView: View {
    @ObservedObject var model: LyricsProviderViewModel
    var body: some View {
        SettingsSection("Lyrics source", symbol: "text.quote", note: "Lyrics come from LRCLIB by default and may be inaccurate or incomplete. Add a Musixmatch API key to try its official API first. Your key needs access to synced lyrics.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SettingsSecureField(title: "Musixmatch API key",
                        placeholder: model.hasKey ? "Replace Musixmatch API key" : "Musixmatch API key (optional)",
                        text: $model.keyDraft, submit: model.save).frame(height: 30)
                    Button("Save") { model.save() }
                        .disabled(model.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if model.hasKey { Button("Remove") { model.remove() } }
                }
                Text(model.message ?? (model.hasKey ? "Key saved in Keychain. LRCLIB is used when Musixmatch has no synced lyrics available." : "No key required for LRCLIB. Your optional Musixmatch key is stored in Keychain."))
                    .font(.system(size: 11)).foregroundStyle(SettingsStyle.secondary).fixedSize(horizontal: false, vertical: true)
                Link("Get a Musixmatch API key", destination: URL(string: "https://developer.musixmatch.com/")!)
                    .font(.system(size: 11))
            }.padding(12)
        }
    }
}

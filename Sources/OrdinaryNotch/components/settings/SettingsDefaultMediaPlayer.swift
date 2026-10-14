import SwiftUI
import UniformTypeIdentifiers

struct SettingsDefaultMediaPlayer: View {
    @ObservedObject var preferences: PreferencesViewModel
    var body: some View {
        SettingsSection("Playback", symbol: "play.circle", note: "Play resumes a paused track first. When no track is available, it opens your default player and tries to resume its queue. You may need to sign in or choose a track first. Web players need Accessibility access for their Play control.") {
            SettingsRow("Default player") {
                Picker("Default player", selection: $preferences.values.defaultMediaPlayer) {
                    ForEach(DefaultMediaPlayer.allCases, id: \.self) { player in Text(player.title).tag(player) }
                }.labelsHidden().frame(width: 180)
            }
            if preferences.values.defaultMediaPlayer == .other {
                SettingsDivider()
                SettingsRow("Application", detail: "Choose an installed music app or web app. Its playback controls must be accessible to macOS.") {
                    Button(preferences.values.defaultMediaApplicationPath == nil ? "Choose App…" : preferences.values.defaultMediaSelection.title) {
                        let panel = NSOpenPanel()
                        panel.title = "Choose a music player"
                        panel.allowedContentTypes = [.application]
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.begin { response in
                            guard response == .OK, let url = panel.url else { return }
                            preferences.values.defaultMediaApplicationPath = url.path
                        }
                    }.lineLimit(1)
                }
            }
        }
    }
}

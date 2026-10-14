import SwiftUI

struct NotchAudioOutputButton: View {
    @ObservedObject var music: MusicViewModel

    var body: some View {
        NotchMenuButton(title: "Audio Output", value: music.outputName ?? "",
            hint: "Choose audio output. Current: \(music.outputName ?? "None")",
            appearance: .plain,
            isPresented: $music.isOutputMenuOpen, items: music.outputMenuItems) {
                Image(systemName: music.outputSymbol)
                    .font(AppFont.symbol).foregroundStyle(music.accentColor)
                    .frame(width: NotchControlMetrics.size, height: NotchControlMetrics.size)
            }
            .alert("Couldn’t Change Audio Output", isPresented: Binding(
                get: { music.outputSelectionError != nil },
                set: { if !$0 { music.outputSelectionError = nil } })) {
                    Button("Close", role: .cancel) { music.outputSelectionError = nil }
                } message: {
                    Text(music.outputSelectionError ?? "")
                }
    }
}

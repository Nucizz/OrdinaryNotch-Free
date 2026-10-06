import SwiftUI

struct ClipboardHistoryCommand: View {
    @ObservedObject var model: ClipboardViewModel
    var show: () -> Void
    var body: some View {
        Button("Clipboard History", action: show)
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(!model.enabled)
    }
}


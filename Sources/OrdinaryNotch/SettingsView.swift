import SwiftUI
struct FreeSettingsView: View {
    @ObservedObject var model: NotchViewModel
    let showClipboard: () -> Void
    var body: some View { FreeSettingsContent(preferences: model.preferences, permissions: model.permissions, actions: model.agentActions, showClipboard: showClipboard) }
}
private struct FreeSettingsContent: View {
    @ObservedObject var preferences: PreferencesViewModel
    @ObservedObject var permissions: PermissionsViewModel
    @ObservedObject var actions: AgentActionViewModel
    let showClipboard: () -> Void
    @State private var tab = "General"
    var body: some View {
        TabView(selection: $tab) {
            Form {
                Toggle("Show menu bar icon", isOn: $preferences.values.showMenuBarIcon)
                Toggle("Reduce motion", isOn: $preferences.values.reduceMotion)
                Toggle("Remember last tab", isOn: $preferences.values.rememberLastTab)
                Picker("Collapsed notch", selection: $preferences.values.notchActivityPresentation) { ForEach(NotchActivityPresentation.allCases, id: \.self) { Text($0.title).tag($0) } }
                Toggle("Developer mode", isOn: $preferences.values.showDeveloperMenu)
                if preferences.values.showDeveloperMenu {
                    Picker("Display override", selection: $preferences.values.developerDisplayOverride) { ForEach(DeveloperDisplayOverride.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("Highlight physical notch", isOn: $preferences.values.highlightPhysicalNotch)
                    ForEach(AgentPromptPreview.allCases) { sample in Button("Preview " + sample.rawValue) { actions.preview(sample) } }
                }
            }.tabItem { Text("General") }.tag("General")
            Form {
                Toggle("Show paused media", isOn: $preferences.values.showPausedMedia)
                Picker("Lyrics", selection: $preferences.values.lyricsPresentation) { ForEach(LyricsPresentation.allCases, id: \.self) { Text($0.title).tag($0) } }
                Slider(value: $preferences.values.lyricsTimingOffset, in: -5...5, step: 0.1) { Text("Lyrics timing") }
                Text(String(format: "Lyrics offset: %.1f seconds", preferences.values.lyricsTimingOffset))
            }.tabItem { Text("Media") }.tag("Media")
            Form {
                Picker("Code & AI", selection: Binding(get: { preferences.values.selectedCodeLayout }, set: { preferences.values.codeLayout = $0 })) { ForEach(CodeLayout.allCases) { Text($0.title).tag($0) } }
                Toggle("Show questions and approvals", isOn: $preferences.values.passAgentQuestions)
                Button(permissions.claudeHooks ? "Disable Claude hooks" : "Enable Claude hooks") { permissions.toggleHooks() }
                if let error = permissions.hookError { Text(error).foregroundStyle(.red) }
            }.tabItem { Text("Code & AI") }.tag("Code")
            Form {
                Toggle("Clipboard history", isOn: $preferences.values.clipboardHistoryEnabled)
                Text("Session-only text and links. Press ⌘⇧V to open history. Quitting clears saved entries.")
                Button("Show Clipboard History", action: showClipboard).disabled(!preferences.values.clipboardHistoryEnabled)
                Toggle("Low battery notices", isOn: $preferences.values.batteryLowAlerts)
                Toggle("Charging notices", isOn: $preferences.values.batteryChargingAlerts)
                Toggle("Fully charged notices", isOn: $preferences.values.batteryFullAlerts)
                Toggle("Temperature notices", isOn: $preferences.values.thermalAlerts)
            }.tabItem { Text("Utilities") }.tag("Utilities")
            Form {
                Button("Camera permission") { permissions.requestCamera() }
                Button("Calendar permission") { permissions.requestAgenda(.calendar) }
                Button("Reminders permission") { permissions.requestAgenda(.reminders) }
                Button("Accessibility permission") { permissions.requestAccessibility() }
                Button("Request missing permissions") { permissions.requestAll() }.disabled(permissions.requestInProgress)
                if let error = permissions.error { Text(error).foregroundStyle(.red) }
                Text("Ordinary Notch Free · MIT license\nFree features only. No premium services or commercial update feed.").font(.caption)
            }.tabItem { Text("Privacy & About") }.tag("Privacy")
        }.padding(20).frame(width: 650, height: 540)
    }
}

import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", layout = "Customize Tabs", media = "Media", timer = "Clock"
    case code = "Code & AI", clipboard = "Files & Clipboard", fans = "Temperature", camera = "Camera", permissions = "Privacy"
    var id: String { rawValue }
    var tab: NotchTab? {
        switch self {
        case .media: .overview; case .timer: .focus; case .code: .codex
        case .clipboard: .shelf; case .fans: .fans; case .camera: .mirror
        default: nil
        }
    }
}
struct FreeSettingsView: View {
    @ObservedObject var model: NotchViewModel
    let showClipboard: () -> Void
    @State private var page: SettingsPage = .general
    @State private var direction: CGFloat = 1
    private var camera: CameraViewModel { model.settingsCamera }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(model: NotchViewModel, showClipboard: @escaping () -> Void, initialPage: SettingsPage = .general) {
        self.model = model; self.showClipboard = showClipboard
        _page = State(initialValue: initialPage)
    }
    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { page }, set: { next in
                direction = (SettingsPage.allCases.firstIndex(of: next) ?? 0) >= (SettingsPage.allCases.firstIndex(of: page) ?? 0) ? 1 : -1
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { page = next }
            })) {
                ForEach(SettingsPage.allCases) { item in
                    Label { Text(item.rawValue) } icon: { SettingsMenuIcon(page: item) }.tag(item)
                }
            }.listStyle(.sidebar).frame(width: 188)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(page.rawValue).font(.title2.bold())
                    if let tab = page.tab { preview(tab) }
                    FreeSettingsControls(page: page, model: model, showClipboard: showClipboard)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .id(page)
                    .transition(.asymmetric(insertion: .offset(x: direction * 32), removal: .offset(x: direction * -32)))
            }.scrollIndicators(.hidden).clipped()
        }
        .frame(minWidth: 830, minHeight: 640)
        .onChange(of: page) { _, page in if page == .camera { camera.start() } else { camera.stop() } }
        .onDisappear { camera.stop() }
    }
    private func preview(_ tab: NotchTab) -> some View {
        let width = model.expandedWidth
        let contentHeight = tab == .mirror ? (width - 2 * model.contentPadding) * 9 / 16 + 16 + NotchGeometry.detailHeadingHeight + NotchGeometry.detailContentGap : max(NotchGeometry.expandedSize.height - model.headerHeight, 134)
        return GeometryReader { geometry in
            let scale = min(1, geometry.size.width / width)
            NotchTabContentView(tab: tab, model: model, previewCamera: camera)
                .padding(.horizontal, model.contentPadding).padding(.vertical, 8)
                .frame(width: width, height: contentHeight)
                .background { NotchContentBackdrop(tab: tab, albumColors: model.music.artwork != nil ? model.music.waveformColors : nil) }
                .background(.black, in: RoundedRectangle(cornerRadius: 22))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .foregroundStyle(.white).environment(\.colorScheme, .dark)
                .environment(\.notchIsPreview, true).disabled(true)
                .scaleEffect(scale, anchor: .top)
                .frame(width: geometry.size.width, height: contentHeight * scale, alignment: .top)
        }.aspectRatio(width / contentHeight, contentMode: .fit).accessibilityLabel("Live \(tab.title) preview")
    }
}
private struct FreeSettingsControls: View {
    let page: SettingsPage
    @ObservedObject var model: NotchViewModel
    let showClipboard: () -> Void
    var body: some View {
        Controls(page: page, preferences: model.preferences, permissions: model.permissions,
                 actions: model.agentActions, lyricsProvider: model.lyricsProvider, showClipboard: showClipboard)
    }
    private struct Controls: View {
        let page: SettingsPage
        @ObservedObject var preferences: PreferencesViewModel
        @ObservedObject var permissions: PermissionsViewModel
        @ObservedObject var actions: AgentActionViewModel
        @ObservedObject var lyricsProvider: LyricsProviderViewModel
        let showClipboard: () -> Void
        @ViewBuilder var body: some View {
            switch page {
            case .general:
                SettingsSection("Appearance", note: "Choose how the notch opens and which activities stay visible.") {
                    SettingsRow("Show menu bar icon") { Toggle("Show menu bar icon", isOn: $preferences.values.showMenuBarIcon).labelsHidden() }
                    SettingsRow("Open on hover") { Toggle("Open on hover", isOn: $preferences.values.openOnHover).labelsHidden() }
                    SettingsRow("Haptic feedback") { Toggle("Haptic feedback", isOn: $preferences.values.hapticFeedback).labelsHidden() }
                    SettingsRow("Reduce motion") { Toggle("Reduce motion", isOn: $preferences.values.reduceMotion).labelsHidden() }
                    SettingsRow("Full-screen apps") { Picker("Full-screen apps", selection: $preferences.values.fullScreenVisibility) { ForEach(FullScreenVisibility.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden() }
                    SettingsRow("Lock-screen activity") { Picker("Lock-screen activity", selection: $preferences.values.lockScreenActivity) { ForEach(LockScreenActivityMode.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden() }
                    SettingsRow("Collapsed notch") { Picker("Collapsed notch", selection: $preferences.values.notchActivityPresentation) { ForEach(NotchActivityPresentation.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden() }
                }
            case .layout:
                SettingsSection("Opening Tab", note: "Choose the first tab shown when the notch opens.") {
                    SettingsRow("Remember last tab") { Toggle("Remember last tab", isOn: $preferences.values.rememberLastTab).labelsHidden() }
                    SettingsRow("Starting tab") { Picker("Starting tab", selection: $preferences.values.startingTab) { ForEach(NotchTab.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden() }
                }
                SettingsSection("Tab Arrangement", note: "Arrange the buttons on either side of the notch. Each side fits five buttons.") {
                    ForEach(NotchTab.allCases, id: \.self) { tab in
                        SettingsRow(tab.title) {
                            Toggle("Show \(tab.title)", isOn: Binding(get: { !preferences.values.hiddenTabs.contains(tab.rawValue) }, set: { shown in
                                if shown { preferences.values.hiddenTabs.remove(tab.rawValue) } else { preferences.values.hiddenTabs.insert(tab.rawValue) }
                            })).labelsHidden()
                            Picker("Position of \(tab.title)", selection: Binding(get: { preferences.values.tabLayout.wing(of: tab.rawValue) }, set: { preferences.values.tabLayout.place(tab.rawValue, in: $0) })) {
                                ForEach(NotchWing.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.labelsHidden().frame(width: 90)
                            Button { preferences.values.tabLayout.move(tab.rawValue, by: -1) } label: { Image(systemName: "chevron.left") }.disabled(!preferences.values.tabLayout.canMove(tab.rawValue, by: -1)).help("Move left")
                            Button { preferences.values.tabLayout.move(tab.rawValue, by: 1) } label: { Image(systemName: "chevron.right") }.disabled(!preferences.values.tabLayout.canMove(tab.rawValue, by: 1)).help("Move right")
                        }
                    }
                }
            case .media:
                SettingsDefaultMediaPlayer(preferences: preferences)
                LyricsProviderSettingsView(model: lyricsProvider)
                SettingsSection("Lyrics & Activities", note: "Paused tracks can remain in the notch. On-screen lock-screen playback remains available while paused.") {
                    SettingsRow("Show paused media in notch") { Toggle("Show paused media", isOn: $preferences.values.showPausedMedia).labelsHidden() }
                    SettingsRow("Lyrics") { Picker("Lyrics", selection: $preferences.values.lyricsPresentation) { ForEach(LyricsPresentation.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden() }
                    SettingsRow("Lyrics timing") { Slider(value: $preferences.values.lyricsTimingOffset, in: -5...5, step: 0.1).frame(width: 150); Text(String(format: "%.1f s", preferences.values.lyricsTimingOffset)).monospacedDigit() }
                }
            case .timer:
                SettingsSection("Timer Presets", note: "Edit hours, minutes, and seconds. Click a preset in the notch to start it in Apple Clock.") {
                    ForEach(0..<9) { index in
                        SettingsDurationRow(title: "Preset \(index + 1)", seconds: $preferences.values.timerPresets[index])
                    }
                }
            case .code:
                SettingsSection("Personal Accounts", note: "Show activity from your original GPT and Claude apps.") {
                    SettingsRow("Layout") { Picker("Layout", selection: Binding(get: { preferences.values.selectedCodeLayout }, set: { preferences.values.codeLayout = $0 })) { ForEach(CodeLayout.allCases) { Text($0.title).tag($0) } }.labelsHidden() }
                    SettingsRow("Questions and approvals") { Toggle("Questions and approvals", isOn: $preferences.values.passAgentQuestions).labelsHidden() }
                    SettingsRow("Claude Code") { Button(permissions.claudeHooks ? "Disable hooks" : "Enable hooks") { permissions.toggleHooks() } }
                    if let error = permissions.hookError { Text(error).foregroundStyle(.red) }
                }
            case .clipboard:
                SettingsSection("Clipboard History", note: "Session-only text and links. Press ⌘⇧V to open history. Quitting clears saved entries.") {
                    SettingsRow("Record copied items") { Toggle("Record copied items", isOn: $preferences.values.clipboardHistoryEnabled).labelsHidden() }
                    SettingsRow("History") { Button("Show Clipboard History", action: showClipboard).disabled(!preferences.values.clipboardHistoryEnabled) }
                }
            case .fans:
                SettingsSection("Temperature", note: "Free reads temperatures and fan speeds. macOS controls cooling.") {
                    SettingsRow("Temperature notices") { Toggle("Temperature notices", isOn: $preferences.values.thermalAlerts).labelsHidden() }
                }
                SettingsSection("Battery Notices", note: "Choose which power changes appear in the notch.") {
                    SettingsRow("Low battery") { Toggle("Low battery", isOn: $preferences.values.batteryLowAlerts).labelsHidden() }
                    SettingsRow("Charging") { Toggle("Charging", isOn: $preferences.values.batteryChargingAlerts).labelsHidden() }
                    SettingsRow("Fully charged") { Toggle("Fully charged", isOn: $preferences.values.batteryFullAlerts).labelsHidden() }
                }
            case .camera:
                SettingsSection("Camera", note: "The preview uses your camera while this page is open. The notch can take a photo or hand the camera to Photo Booth.") {
                    Button("Camera permission") { permissions.requestCamera() }
                }
            case .permissions:
                SettingsSection("Permissions", note: "Enable only the integrations you use. Clock control and clipboard paste require Accessibility.") {
                    Button("Camera permission") { permissions.requestCamera() }
                    Button("Calendar permission") { permissions.requestAgenda(.calendar) }
                    Button("Reminders permission") { permissions.requestAgenda(.reminders) }
                    Button("Accessibility permission") { permissions.requestAccessibility() }
                    if let error = permissions.error { Text(error).foregroundStyle(.red) }
                }
                Text("Ordinary Notch Free · MIT license").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

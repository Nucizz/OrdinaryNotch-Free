import SwiftUI

private let mint = Color(red: 0.67, green: 0.94, blue: 0.76)
private let clockOrange = Color(nsColor: .systemOrange)
private let muted = Color.white.opacity(0.42)

struct NotchView: View {
    @ObservedObject var model: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || model.preferences.values.reduceMotion }
    private var silhouette: NotchSilhouette {
        // The main island grows around a fixed center. The satellite is a separate layer.
        model.isIsland ? NotchSilhouette(shoulder: 0, bottom: 0, island: true) : model.silhouette
    }
    private var lyricsTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .offset(y: -14).combined(with: .opacity),
            removal: .offset(y: -14).combined(with: .opacity))
    }
    var body: some View {
        VStack(spacing: 0) {
            if model.welcomeVisible {
                Color.clear.frame(height: model.headerHeight)
            } else {
            ZStack {
                CompactView(model: model, music: model.music)
                    .frame(width: model.isIsland ? model.islandActivityLayout.mainWidth : model.compactWidth, height: model.compactHeight)
                    .opacity(model.surfaceExpanded ? 0 : 1)
                    .animation(NotchMotion.compact(expanded: model.surfaceExpanded, reduceMotion: reduceMotion), value: model.surfaceExpanded)
                    .allowsHitTesting(!model.surfaceExpanded)
                    .accessibilityHidden(model.surfaceExpanded)
                header
                    .padding(.horizontal, model.contentPadding)
                    .frame(width: model.expandedSurfaceWidth)
                    .opacity(model.surfaceExpanded ? 1 : 0)
                    .animation(NotchMotion.header(expanded: model.surfaceExpanded, reduceMotion: reduceMotion), value: model.surfaceExpanded)
                    .allowsHitTesting(model.surfaceExpanded)
                    .accessibilityHidden(!model.surfaceExpanded)
            }
            .frame(height: model.compactHeight)
            .contentShape(Rectangle())
            .onTapGesture { if !model.surfaceExpanded { model.expandFromClick() } }
            .pointingCursor(!model.surfaceExpanded)
            }
            if model.compactAlertActive {
                briefAlert
                    .padding(.horizontal, model.contentPadding)
                    .frame(width: model.surfaceSize.width, height: NotchGeometry.alertContentHeight)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { if !model.surfaceExpanded { model.expandFromClick() } }
                    .pointingCursor(!model.surfaceExpanded)
                    .transition(.opacity)
            }
            expandedContent
                .frame(width: model.expandedSurfaceWidth, height: max(0, model.pageHeight - model.headerHeight))
                .frame(height: model.surfaceExpanded ? max(0, model.pageHeight - model.headerHeight) : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(model.surfaceExpanded)
                .accessibilityHidden(!model.surfaceExpanded)
            if model.integratedLyricsVisible {
                LyricsView(model: model.music.lyrics)
                    .frame(width: model.mainSurfaceWidth, height: 44)
                    .transition(lyricsTransition)
            }
        }
        .frame(width: model.mainSurfaceWidth, height: model.surfaceSize.height, alignment: .top)
        .background(.black)
        .clipShape(silhouette)
        .overlay(alignment: .top) {
            if model.isIsland {
                // Keep the simulated cutout empty even while controls animate between wings.
                Color.black.frame(width: model.reservedNotchWidth, height: model.compactHeight)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .contentShape(silhouette)
        .dropDestination(for: URL.self) { urls, _ in
            guard model.isTabVisible(.shelf), !model.transientActive else { return false }
            let accepted = model.fileShelf.add(urls)
            if accepted { openFileShelf() }
            return accepted
        } isTargeted: { targeted in
            if targeted && model.isTabVisible(.shelf) && !model.transientActive {
                openFileShelf()
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : (model.surfaceExpanded ? NotchGeometry.openSpring : NotchGeometry.closeSpring), value: model.surfaceExpanded)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : NotchGeometry.openSpring, value: model.compactAlertActive)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : NotchGeometry.openSpring, value: model.lyricsVisible)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : NotchGeometry.openSpring, value: model.preferences.values.lyricsPresentation)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : NotchGeometry.openSpring, value: model.preferences.values.notchActivityPresentation)
        .animation(reduceMotion ? nil : NotchGeometry.openSpring, value: model.isIsland ? model.islandActivityLayout.mainWidth : model.compactWidth)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : NotchGeometry.openSpring, value: model.expandedHeight)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : NotchGeometry.openSpring, value: model.expandedSurfaceWidth)
        .frame(width: model.canvasSize.width, height: model.canvasSize.height, alignment: .top)
        .background(alignment: .top) { detachedIsland }
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                if model.floatingLyricsVisible {
                    FloatingLyricsView(music: model.music, notchWidth: model.mainSurfaceWidth)
                        .frame(width: model.floatingLyricsWidth)
                        .transition(lyricsTransition)
                }
            }
            .frame(width: max(model.mainSurfaceWidth, 400) + 48, height: 112, alignment: .top)
            .clipped() // The reveal emerges below the notch without tinting its black surface.
            .offset(y: model.floatingLyricsTop)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.24), value: model.floatingLyricsVisible)
            .animation(reduceMotion ? nil : NotchGeometry.openSpring, value: model.floatingLyricsTop)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .environment(\.notchReduceMotion, reduceMotion)
    }
    @ViewBuilder private var detachedIsland: some View {
        if model.isIsland,
           let off = model.islandActivityLayout.placements.first(where: { $0.primary.region == .offIsland }) {
            Button {
                model.expandFromClick()
                model.selectTab(off.activity.detailTab)
            } label: {
                off.activity.primary(in: model)
                    .font(AppFont.label).monospacedDigit()
                    .frame(width: model.islandActivityLayout.detachedWidth, height: model.compactHeight)
                    .background(.black, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .offset(x: off.primary.offset)
            // Stay in place while the main island grows over this capsule.
            .opacity(model.islandSatelliteVisible ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.12).delay(0.12), value: model.islandSatelliteVisible)
            .allowsHitTesting(model.islandSatelliteVisible)
            .accessibilityHidden(!model.islandSatelliteVisible)
            .accessibilityLabel("Open \(off.activity.title)")
            .help("Open \(off.activity.title)")
        }
    }
    private func openFileShelf() {
        model.expandFromClick()
        if model.expanded { model.selectTab(.shelf) }
    }
    @ViewBuilder private var briefAlert: some View {
        if let notice = model.battery.notice { BatteryNoticeView(notice: notice) }
        else if let notice = model.thermal.notice { ThermalNoticeView(notice: notice) }
    }
    var expandedContent: some View {
        ZStack {
            if model.welcomeVisible {
                NotchWelcomeView(reduceMotion: reduceMotion, getStarted: model.startFromWelcome)
            } else if let prompt = model.agentActions.current {
                AgentPromptView(model: model.agentActions, prompt: prompt, openTask: { task in
                    model.codexMonitor.openTask(task)
                    return model.codexMonitor.navigationError == nil
                }, maximumHeight: model.maximumPromptHeight, navigationError: model.codexMonitor.navigationError).id(prompt.id)
            } else {
                tabDetails
                    .id(model.detailTab)
                    .transition(NotchMotion.replacement(reduceMotion: reduceMotion))
            }
        }
        .animation(NotchMotion.content(reduceMotion: reduceMotion), value: model.detailTab)
        .opacity(model.surfaceExpanded ? 1 : 0)
        .offset(y: reduceMotion || model.surfaceExpanded ? 0 : -6)
        .scaleEffect(reduceMotion || model.surfaceExpanded ? 1 : 0.985, anchor: .top)
        .animation(NotchMotion.details(expanded: model.surfaceExpanded, reduceMotion: reduceMotion), value: model.surfaceExpanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if !model.welcomeVisible {
                NotchContentBackdrop(tab: model.detailTab)
                    .padding(.horizontal, -model.contentPadding)
                    .padding(.bottom, -8)
                    .opacity(model.surfaceExpanded ? 1 : 0)
                    .animation(.easeOut(duration: reduceMotion ? 0.10 : 0.20), value: model.surfaceExpanded)
            }
        }
        // The physical notch's sides begin after its shoulders. Keep the light
        // eight points inside those sides, matching the bottom border.
        .padding(.horizontal, model.contentPadding)
        .padding(.vertical, 8)
    }
    @ViewBuilder private var tabDetails: some View {
        switch model.detailTab {
        case .overview: overview
        case .focus: FocusView(model: model)
        case .shelf: FileShelfView(model: model.fileShelf)
        case .codex: CodeLayoutView(channels: model.codeChannels, dashboard: model.codeDashboard, now: model.now,
                                   visible: model.expanded, openTask: model.codexMonitor.openTask,
                                   openProvider: model.openCodeProvider, navigationError: model.codexMonitor.navigationError)
        case .mirror: MirrorView(camera: model.camera)
        case .fans: FanTabView(service: model.fans)

        }
    }
    var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: headerSlotSpacing) {
                tabSlot(.overview)
                tabSlot(.focus)
                tabSlot(.codex)
                tabSlot(.shelf)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: model.reservedNotchWidth + 8)
            HStack(spacing: headerSlotSpacing) {
                tabSlot(.fans)
                tabSlot(.mirror)
                Button { model.pinned.toggle() } label: {
                    Image(systemName: model.pinned ? "pin.fill" : "pin")
                        .foregroundStyle(model.pinned ? .white : muted).frame(width: headerSlotWidth, height: 26)
                }.buttonStyle(NotchHoverButtonStyle()).help(model.pinned ? "Unpin panel" : "Keep expanded")
                    .accessibilityLabel(model.pinned ? "Unpin panel" : "Keep expanded")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    private var headerWingWidth: CGFloat { (model.expandedWidth - 2 * model.contentPadding - model.reservedNotchWidth - 8) / 2 }
    private var headerSlotWidth: CGFloat { min(32, max(20, (headerWingWidth - 18) / 4)) }
    private var headerSlotSpacing: CGFloat { min(6, max(0, (headerWingWidth - 4 * headerSlotWidth) / 3)) }
    private var emptyHeaderSlot: some View {
        Color.clear.frame(width: headerSlotWidth, height: 26).allowsHitTesting(false).accessibilityHidden(true)
    }
    @ViewBuilder private func tabSlot(_ tab: NotchViewModel.Tab) -> some View {
        if model.isTabVisible(tab) || (tab == .codex && !model.agentActions.prompts.isEmpty) { tabButton(tab) }
        else { emptyHeaderSlot }
    }
    func tabButton(_ tab: NotchViewModel.Tab) -> some View {
        Button {
            model.activateTab(tab)
            if tab == .codex && !model.agentActions.prompts.isEmpty { model.agentActions.showPending() }
        } label: {
            Image(systemName: icon(tab)).renderingMode(.template).symbolRenderingMode(.monochrome)
                .foregroundStyle(model.detailTab == tab ? .white : muted)
                .font(AppFont.body)
                .frame(width: headerSlotWidth, height: 26)
                .background(model.detailTab == tab ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: NotchGeometry.tabCornerRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if tab == .codex && !model.agentActions.prompts.isEmpty {
                        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9))
                            .foregroundStyle(.black, .orange).allowsHitTesting(false)
                    }
                }
        }.buttonStyle(NotchHoverButtonStyle(cornerRadius: NotchGeometry.tabCornerRadius))
            .help(tabTitle(tab)).accessibilityLabel(tabTitle(tab))
    }
    private func tabTitle(_ tab: NotchViewModel.Tab) -> String {
        switch tab {
        case .overview: "Media"
        case .focus: "Timer & Clock"
        case .codex: model.agentActions.prompts.isEmpty ? "Code & AI" : "Code & AI — Answer agent requests"
        case .fans: "Fan Status"
        default: tab.rawValue
        }
    }
    func icon(_ tab: NotchViewModel.Tab) -> String {
        switch tab { case .overview: "music.note"; case .focus: "timer"; case .codex: "chevron.left.forwardslash.chevron.right"; case .shelf: "tray"; case .mirror: "web.camera"; case .fans: "fan" }
    }
    var overview: some View {
        HStack(alignment: .top, spacing: model.isIsland ? 12 : 18) {
            MusicView(music: model.music).frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.white.opacity(0.09)).frame(width: 1).padding(.vertical, 4)
            AgendaView(agenda: model.agenda, full: false).frame(width: model.isIsland ? 160 : NotchGeometry.detailSidebarWidth)
        }
    }
}

struct CompactView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var music: MusicViewModel
    @Environment(\.notchReduceMotion) private var reduceMotion
    var body: some View {
        let layout = model.isIsland ? model.islandActivityLayout : model.compactLayout
        // Stable activity identity preserves media animation when priority changes its wing.
        ZStack {
            ForEach(layout.placements.filter { !model.isIsland || $0.primary.region != .offIsland }) { placement in
                placement.activity.primary(in: model)
                    .monospacedDigit()
                    .frame(width: placement.primary.width,
                           height: max(20, model.compactHeight - 2 * NotchGeometry.compactContentInset),
                           alignment: placement.activity == .media || placement.primary.region == .offIsland ? .center : (placement.primary.side == .left ? .leading : .trailing))
                    .transition(activityTransition)
                    .offset(x: placement.primary.offset)
                if let secondary = placement.secondary {
                    placement.activity.secondary(in: model)
                        .frame(width: secondary.width)
                        .transition(activityTransition)
                        .offset(x: secondary.offset)
                }
            }
        }
        .font(AppFont.label)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : NotchGeometry.openSpring, value: layout.placements.map(\.activity))
    }
    private var activityTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85))
    }
}

struct Artwork: View {
    @Environment(\.notchReduceMotion) private var reduceMotion
    let image: NSImage?
    var size: CGFloat = 90
    var cornerRadius: CGFloat = NotchGeometry.insetRadius(NotchGeometry.expandedBottomRadius, padding: NotchGeometry.expandedContentPadding - NotchGeometry.expandedShoulder)
    var body: some View {
        ZStack {
            Color.white.opacity(image == nil ? 0.16 : 0.06)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .id(ObjectIdentifier(image)).transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(NotchMotion.content(reduceMotion: reduceMotion), value: image.map(ObjectIdentifier.init))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .circular))
    }
}

struct MusicView: View {
    @ObservedObject var music: MusicViewModel
    @Environment(\.notchReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: NotchGeometry.detailContentGap) {
            ZStack(alignment: .leading) {
                DetailHeading {
                    if let icon = music.sourceIcon {
                        Image(nsImage: icon).resizable().scaledToFit()
                            .frame(width: NotchGeometry.detailIconSize, height: NotchGeometry.detailIconSize)
                            .clipped()
                    } else { Image(systemName: "music.note") }
                } title: { Text(music.sourceTitle) } accessory: { EmptyView() }
                .id(music.sourceIdentity)
                .transition(NotchMotion.replacement(reduceMotion: reduceMotion))
            }.frame(height: NotchGeometry.detailHeadingHeight)
                .animation(NotchMotion.content(reduceMotion: reduceMotion), value: music.sourceIdentity)
            HStack(spacing: 14) {
                Artwork(image: music.artwork)
                VStack(alignment: .leading, spacing: 4) {
                    ZStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(music.title).font(AppFont.title).lineLimit(1)
                            Text(music.artist).font(AppFont.subtitle).foregroundStyle(music.accentColor.opacity(0.8)).lineLimit(1)
                        }
                        .id(music.contentIdentity)
                        .transition(NotchMotion.replacement(reduceMotion: reduceMotion))
                    }
                    .animation(NotchMotion.content(reduceMotion: reduceMotion), value: music.contentIdentity)
                    if music.hasTrack {
                        AccentProgress(value: music.position / max(1, music.duration), color: music.accentColor)
                        HStack {
                            Text(ClockFormat.format(music.position.rounded(.down))); Spacer(); Text(ClockFormat.format(music.duration.rounded(.down)))
                        }.font(AppFont.label).foregroundStyle(music.accentColor.opacity(0.75))
                        HStack(spacing: 8) {
                            HStack(spacing: 14) {
                                transport("backward.end.fill", "Previous track", "previous track")
                                transport(music.isPlaying ? "pause.fill" : "play.fill", "Play or pause", "playpause", large: true)
                                transport("forward.end.fill", "Next track", "next track")
                            }.fixedSize()
                            Spacer(minLength: 8)
                            Button { music.lyrics.toggle() } label: {
                                Image(systemName: music.lyrics.enabled ? "mic.fill" : "mic")
                                    .font(AppFont.symbol).frame(width: 24, height: 24)
                                    .foregroundStyle(music.lyrics.enabled ? music.accentColor : .white.opacity(0.65))
                                    .background(music.lyrics.enabled ? Color.white.opacity(0.14) : .clear, in: Circle())
                            }
                            .buttonStyle(NotchHoverButtonStyle())
                            .help(music.lyrics.enabled ? "Hide lyrics" : "Show synced lyrics")
                            .accessibilityLabel("Synced lyrics")
                            .accessibilityValue(music.lyrics.enabled ? "On" : "Off")
                            HStack(spacing: 5) {
                                Image(systemName: "airplayaudio").fixedSize()
                                MarqueeText(text: music.outputName, color: music.accent.withAlphaComponent(0.75))
                                    .frame(height: 14)
                            }
                                .font(AppFont.label)
                                .foregroundStyle(music.accentColor.opacity(0.75))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.09), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                                .help("System audio output: \(music.outputName)")
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("System audio output: \(music.outputName)")

                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if music.error != nil {
                        Text("Playback unavailable").font(AppFont.label).foregroundStyle(.orange).help(music.error ?? "")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func transport(_ symbol: String, _ label: String, _ command: String, large: Bool = false) -> some View {
        Button { music.command(command) } label: {
            Image(systemName: symbol).font(large ? AppFont.largeSymbol : AppFont.symbol).frame(width: large ? 30 : 24, height: 24)
                .contentShape(Rectangle())
        }.buttonStyle(NotchHoverButtonStyle()).foregroundStyle(music.accentColor).help(label).accessibilityLabel(label)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View { Text(text).font(AppFont.label).tracking(1.8).foregroundStyle(muted) }
}
struct AccentProgress: View {
    let value: Double
    let color: Color
    var fraction: Double { value.isFinite ? min(1, max(0, value)) : 0 }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(color).frame(width: geometry.size.width * fraction)
            }
        }.frame(height: 4)
            .accessibilityElement(children: .ignore).accessibilityLabel("Progress")
            .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
struct NotchButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.button)
            .foregroundStyle(prominent ? Color.black : .white)
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? clockOrange : .white.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(prominent ? 0 : 0.08), lineWidth: 0.5)
                    }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .modifier(NotchHoverEffect(pressed: configuration.isPressed))
    }
}


struct FocusView: View {
    @ObservedObject var model: NotchViewModel
    @State private var showError = false
    @Environment(\.notchReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: NotchGeometry.detailContentGap) {
                DetailHeading {
                    Image(systemName: "timer")
                } title: { Text("Timer") } accessory: {
                    if model.clock.timers.count > 1 {
                        Button("\(model.clock.timers.count) timers") { model.clock.openClock() }
                            .font(AppFont.label).buttonStyle(NotchHoverButtonStyle()).foregroundStyle(muted)
                            .help("Open Clock to choose a timer")
                    }
                    if model.clock.isControlling { ProgressView().controlSize(.mini) }
                    if let error = model.clock.commandError {
                        Button { showError.toggle() } label: { Image(systemName: "exclamationmark.circle").foregroundStyle(clockOrange) }
                            .buttonStyle(NotchHoverButtonStyle()).accessibilityLabel("Clock access details")
                            .help(error)
                            .popover(isPresented: $showError) {
                                Text(error).font(AppFont.body).padding(16).frame(width: 300).fixedSize(horizontal: false, vertical: true)
                            }
                    }
                }
                ZStack(alignment: .top) {
                    if let timer = model.clock.primaryTimer {
                        VStack(spacing: NotchGeometry.detailContentGap) {
                            Spacer(minLength: 0)
                            counter(ClockFormat.format(timer.value(at: model.now)), detail: timer.isPaused ? "Paused · \(timer.title)" : timer.title)
                            Spacer(minLength: 0)
                            HStack(spacing: 8) {
                                Button("Stop") { model.clock.control(.stopTimer) }
                                    .buttonStyle(NotchButtonStyle()).accessibilityLabel("Stop timer")
                                Button {
                                    model.clock.control(timer.isPaused ? .resumeTimer : .pauseTimer)
                                } label: {
                                    Label(timer.isPaused ? "Resume" : "Pause", systemImage: timer.isPaused ? "play.fill" : "pause.fill")
                                        .frame(minWidth: 64)
                                }.buttonStyle(NotchButtonStyle(prominent: true))
                                    .disabled(timer.state == 4).accessibilityLabel(timer.isPaused ? "Resume timer" : "Pause timer")
                            }.frame(height: 28)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(timer.id)
                        .transition(NotchMotion.replacement(reduceMotion: reduceMotion))
                    } else {
                        TimerPresetGrid(presets: model.preferences.values.timerPresets,
                                        visible: model.expanded && model.detailTab == .focus) {
                            model.clock.control(.startTimer($0))
                        }
                        .transition(NotchMotion.replacement(reduceMotion: reduceMotion))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(NotchMotion.content(reduceMotion: reduceMotion), value: model.clock.primaryTimer?.id)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(.white.opacity(0.09)).frame(width: 1).padding(.vertical, 4)
            VStack(spacing: NotchGeometry.detailContentGap) {
                DetailHeading("Stopwatch", systemImage: "stopwatch")
                Spacer(minLength: 0)
                if model.hasStopwatch {
                    counter(ClockFormat.format(model.clock.stopwatch.value(at: model.now).rounded(.down)),
                            detail: model.clock.stopwatch.isRunning ? "Running" : "Paused")
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Button(model.clock.stopwatch.isRunning ? "Stop" : "Reset") { model.clock.control(.stopStopwatch) }
                            .buttonStyle(NotchButtonStyle())
                            .accessibilityLabel("Stop and reset stopwatch").help("Stop and reset the stopwatch")
                        Button {
                            model.clock.control(model.clock.stopwatch.isRunning ? .pauseStopwatch : .startStopwatch)
                        } label: {
                            Label(model.clock.stopwatch.isRunning ? "Pause" : "Resume", systemImage: model.clock.stopwatch.isRunning ? "pause.fill" : "play.fill")
                                .frame(minWidth: 64)
                        }.buttonStyle(NotchButtonStyle(prominent: true))
                            .accessibilityLabel(model.clock.stopwatch.isRunning ? "Pause stopwatch" : "Resume stopwatch")
                    }.frame(height: 28)
                } else {
                    Button { model.clock.control(.startStopwatch) } label: {
                        Label("Start", systemImage: "play.fill").frame(minWidth: 84)
                    }.buttonStyle(NotchButtonStyle(prominent: true))
                        .accessibilityLabel("Start stopwatch").help("Start stopwatch")
                        .frame(maxWidth: .infinity).frame(height: 30)
                    Spacer(minLength: 0)
                }
            }.frame(width: NotchGeometry.detailSidebarWidth).frame(maxHeight: .infinity, alignment: .topLeading)
        }.disabled(model.clock.isControlling)
        .onChange(of: model.clock.commandError) { _, value in showError = value != nil }
    }
    private func counter(_ value: String, detail: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(AppFont.counter).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(detail).font(AppFont.label).foregroundStyle(muted).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
}

struct AgendaView: View {
    @ObservedObject var agenda: AgendaViewModel
    var full: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: NotchGeometry.detailContentGap) {
            DetailHeading {
                Image(systemName: "calendar")
            } title: { Text("TODAY") } accessory: {
                Text(Date(), format: .dateTime.month(.abbreviated).day()).font(AppFont.button).foregroundStyle(Color(nsColor: .controlAccentColor))
            }
            if !agenda.calendarGranted && !agenda.remindersGranted {
                Text("Your day, at a glance.").font(AppFont.button)
                Button(agenda.connecting ? "Connecting…" : "Connect Calendar & Reminders") { agenda.connect() }.buttonStyle(NotchButtonStyle()).disabled(agenda.connecting)
            } else if agenda.items.isEmpty {
                Text("Your day looks clear").font(AppFont.settingsBody)
                Text("Enjoy a little breathing room.").font(AppFont.subtitle).foregroundStyle(muted)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(agenda.items.prefix(50))) { item in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2).fill(item.isReminder ? Color.orange.opacity(0.8) : mint).frame(width: 3, height: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(AppFont.body).lineLimit(1)
                                    HStack(spacing: 4) {
                                        if item.isReminder { Image(systemName: "checklist"); Text("Reminder") }
                                        if item.allDay { Text("All day") }
                                        else if let date = item.date { Text(date, format: .dateTime.hour().minute()) }
                                    }.font(AppFont.label).foregroundStyle(muted)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            if let message = agenda.message { Text(message).font(AppFont.label).foregroundStyle(.orange) }
            if full && (!agenda.calendarGranted || !agenda.remindersGranted) && (agenda.calendarGranted || agenda.remindersGranted) {
                Button("Manage missing access") { agenda.connect() }.buttonStyle(NotchButtonStyle())
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MirrorView: View {
    @ObservedObject var camera: CameraViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: NotchGeometry.detailContentGap) {
            DetailHeading("Camera", systemImage: "web.camera")
            preview
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.04))
            if let session = camera.session, camera.running {
                CameraPreview(session: session)
            } else if camera.isStarting {
                ProgressView().controlSize(.small)
            } else if !camera.message.isEmpty {
                Text(camera.message).font(AppFont.subtitle).foregroundStyle(muted)
                    .multilineTextAlignment(.center).padding(20)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

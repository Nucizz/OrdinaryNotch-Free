import AppKit
import Combine
import Foundation

@MainActor
final class NotchViewModel: ObservableObject {
    private let isPreview: Bool
    let preferences: PreferencesViewModel
    var openSettings: () -> Void = {}
    var expandFromClick: () -> Void = {}
    var canPresentNotices: () -> Bool = { true }
    let battery = BatteryViewModel()
    let thermal = ThermalAlertsViewModel()
    var compactAlertActive: Bool { !welcomeVisible && (battery.active || thermal.active) }
    var transientActive: Bool { welcomeVisible || compactAlertActive }
    var surfaceExpanded: Bool { expanded || welcomeVisible }
    @Published private(set) var welcomeVisible = false
    private let welcomeBuildID: String
    private var welcomePending: Bool
    func showWelcomeIfNeeded() {
        guard welcomePending, !welcomeVisible else { return }
        welcomeVisible = true
        preferences.markWelcomeShown(for: welcomeBuildID)
    }
    func startFromWelcome() {
        guard welcomeVisible else { return }
        dismissWelcome()
        openSettings()
    }
    func dismissWelcome() {
        guard welcomePending || welcomeVisible else { return }
        welcomePending = false
        preferences.markWelcomeShown(for: welcomeBuildID)
        deferWelcome()
    }
    func deferWelcome() {
        guard welcomeVisible else { return }
        welcomeVisible = false
    }
    @Published var expanded = false
    @Published var pinned = false
    @Published var notchWidth: CGFloat = 180
    @Published var physicalCompactHeight: CGFloat = 32
    @Published var displaySafeAreaTop: CGFloat = 0
    @Published var availableExpandedWidth: CGFloat = NotchGeometry.expandedSize.width
    @Published var availableDisplayHeight: CGFloat = 900
    var maximumPromptHeight: CGFloat { max(160, availableDisplayHeight - surfaceTopInset - headerHeight - 64) }
    @Published var displayStyle: NotchStyle = .notch
    var effectiveDisplayStyle: NotchStyle {
        (preferences.values.showDeveloperMenu ? preferences.values.developerDisplayOverride.style : nil) ?? displayStyle
    }
    var isIsland: Bool { effectiveDisplayStyle == .island }
    var reservedNotchWidth: CGFloat { isIsland ? NotchGeometry.islandCenterWidth : (notchWidth > 0 ? notchWidth : 180) }
    var surfaceTopInset: CGFloat { isIsland ? displaySafeAreaTop + NotchGeometry.islandTopInset : 0 }
    var contentPadding: CGFloat { isIsland ? 24 : NotchGeometry.expandedContentPadding }
    var headerHeight: CGFloat { compactHeight }
    var compactHeight: CGFloat {
        get { isIsland ? NotchGeometry.islandCompactHeight : (notchWidth > 0 ? physicalCompactHeight : 32) }
        set { physicalCompactHeight = newValue }
    }
    /// Apply the selected display's reported cutout, including external-display changes.
    func updateDisplayGeometry(frame: CGRect, safeAreaTop: CGFloat, left: CGRect?, right: CGRect?, scale: CGFloat) {
        let cutout = PhysicalNotchBounds.cutout(screen: frame, safeAreaTop: safeAreaTop, left: left, right: right)
        displayStyle = cutout == nil ? .island : .notch
        availableDisplayHeight = frame.height
        displayScale = scale
        displaySafeAreaTop = safeAreaTop
        notchWidth = cutout.map { $0.width + 4 } ?? 0
        physicalCompactHeight = cutout?.height ?? NotchGeometry.islandCompactHeight
        availableExpandedWidth = min(NotchGeometry.expandedSize.width, frame.width - 48)
    }

    var expandedWidth: CGFloat {
        get { min(availableExpandedWidth, isIsland ? NotchGeometry.islandExpandedWidth : NotchGeometry.expandedSize.width) }
        set { availableExpandedWidth = newValue }
    }
    var silhouette: NotchSilhouette {
        NotchSilhouette(shoulder: surfaceExpanded ? NotchGeometry.expandedShoulder : NotchGeometry.compactShoulder,
                        bottom: surfaceExpanded ? NotchGeometry.expandedBottomRadius : NotchGeometry.compactBottomRadius,
                        island: isIsland, detachedWidth: compactLayout.detachedWidth,
                        detachedGap: compactLayout.detachedWidth > 0 ? NotchGeometry.islandSeparation : 0)
    }
    var expandedSurfaceWidth: CGFloat { expandedWidth }
    var alertSurfaceWidth: CGFloat { min(expandedWidth, max(NotchGeometry.alertWidth, reservedNotchWidth + 64, compactWidth)) }
    var pageHeight: CGFloat {
        if welcomeVisible { return headerHeight + 168 }
        if agentActions.current != nil { return headerHeight + agentActions.promptHeight }
        switch tab {
        case .mirror: return compactHeight + (expandedWidth - 2 * contentPadding) * 9 / 16 + 16 + NotchGeometry.detailHeadingHeight + NotchGeometry.detailContentGap
        case .overview, .focus, .codex, .shelf, .fans: return max(NotchGeometry.expandedSize.height, compactHeight + 134)
        }
    }
    var lyricsVisible: Bool {
        music.lyrics.enabled && !music.lyrics.hiddenForCurrentTrack && music.hasTrack && music.isPlaying && !transientActive && agentActions.current == nil &&
            (!surfaceExpanded || tab == .overview)
    }
    var integratedLyricsVisible: Bool { lyricsVisible && preferences.values.lyricsPresentation == .integrated }
    var floatingLyricsVisible: Bool { lyricsVisible && preferences.values.lyricsPresentation == .floating }
    var lyricsHeight: CGFloat { integratedLyricsVisible ? 44 : 0 }
    var floatingLyricsTop: CGFloat { surfaceSize.height }
    var floatingLyricsWidth: CGFloat { min(expandedWidth, 400) }
    var expandedHeight: CGFloat { pageHeight + (compactAlertActive ? NotchGeometry.alertContentHeight : 0) + lyricsHeight }
    var displayScale: CGFloat = 2
    // Reserve brief-alert space even while collapsed so Mirror never clips when an alert arrives.
    var canvasSize: CGSize { NotchGeometry.pixelAlignedSize(CGSize(width: expandedWidth + 2 * NotchGeometry.canvasMargin, height: max(expandedHeight, compactHeight + 356, compactHeight + (expandedWidth - 2 * contentPadding) * 9 / 16 + 40 + NotchGeometry.detailHeadingHeight + NotchGeometry.detailContentGap + NotchGeometry.alertContentHeight)), scale: displayScale) }
    var hasMusic: Bool { music.hasTrack }
    var hasStopwatch: Bool { clock.stopwatch.isRunning || clock.stopwatch.elapsed > 0 }
    var hasClock: Bool { clock.primaryTimer != nil || hasStopwatch }
    var hasActivity: Bool { hasMusic || hasClock || codex.isRunning }
    var compactActivities: [CompactActivity] {
        Array(preferences.values.orderedActivities.filter {
            !preferences.values.hiddenActivities.contains($0.rawValue) && $0.isActive(in: self)
        }.prefix(2))
    }
    var usesIslandActivityLayout: Bool { isIsland && !surfaceExpanded && !compactAlertActive }
    var compactLayout: CompactActivityLayout {
        let activities = compactActivities
        return CompactActivityLayout(contents: activities.map { $0.content(in: self, paired: !usesIslandActivityLayout && activities.count > 1) },
                                     centerWidth: reservedNotchWidth,
                                     minimumWidth: isIsland ? (integratedLyricsVisible ? min(expandedWidth, 400) : NotchGeometry.islandIdleWidth) : 0,
                                     style: usesIslandActivityLayout ? .island : .notch,
                                     presentation: isIsland ? .detailed : preferences.values.notchActivityPresentation)
    }
    /// Keep the collapsed island coordinates stable while its main container expands.
    var islandActivityLayout: CompactActivityLayout {
        CompactActivityLayout(contents: compactActivities.map { $0.content(in: self, paired: false) },
            centerWidth: reservedNotchWidth,
            minimumWidth: integratedLyricsVisible ? min(expandedWidth, 400) : NotchGeometry.islandIdleWidth,
            style: .island)
    }
    var islandSatelliteVisible: Bool { usesIslandActivityLayout }
    private var textWidths: [String: CGFloat] = [:]
    func compactTextWidth(_ text: String) -> CGFloat {
        if let cached = textWidths[text] { return cached }
        let measured = (text as NSString).size(withAttributes: [.font: AppFont.compactNS]).width.rounded(.up) + 2
        if textWidths.count >= 128 { textWidths.removeAll(keepingCapacity: true) }
        textWidths[text] = measured
        return measured
    }
    var compactWidth: CGFloat { compactLayout.width }
    // Content coordinates stay anchored to the camera; the bounds extend to the right.
    var compactContentOffset: CGFloat { -compactLayout.detachedSpan / 2 }
    var surfaceOffset: CGFloat { compactLayout.detachedSpan / 2 }
    var mainSurfaceWidth: CGFloat { surfaceSize.width - compactLayout.detachedSpan }
    var surfaceSize: CGSize {
        CGSize(width: surfaceExpanded ? expandedSurfaceWidth : (compactAlertActive ? alertSurfaceWidth : (integratedLyricsVisible && !isIsland ? min(expandedWidth, max(compactWidth, 400)) : compactWidth)),
               height: surfaceExpanded ? expandedHeight : compactHeight + (compactAlertActive ? NotchGeometry.alertContentHeight : 0) + lyricsHeight)
    }
    @Published var tab: Tab = .overview
    @Published var now = Date()
    let clock = ClockViewModel()
    let fileShelf = FileShelfViewModel()
    let clipboard = ClipboardViewModel()
    let codexMonitor = CodeViewModel()
    let agentActions = AgentActionViewModel()
    var codex: CodexActivity {
        codeDashboard.compactActivity(at: now) ?? .idle
    }
    var codeChannels: [CodeChannel] { preferences.values.codeChannels }
    private var monitoredSelection: CodeSelection {
        let providers = Set(codeChannels.map(\.provider))
        return providers.count > 1 ? .both : (providers.contains(.claude) ? .claude : .codex)
    }
    private var monitoredAccount: CodeAccountFilter { .personal }
    private var cachedCode: (revision: UInt64, channels: [CodeChannel], dashboard: CodeDashboard)?
    var codeDashboard: CodeDashboard {
        let channels = codeChannels
        if let cachedCode, cachedCode.revision == codexMonitor.revision, cachedCode.channels == channels {
            return cachedCode.dashboard
        }
        let source = codexMonitor.dashboard.tasks.isEmpty
            ? CodeDashboard(tasks: codexMonitor.activity.state == "idle" ? [] : [CodeTask(id: "preview", provider: .codex, activity: codexMonitor.activity)])
            : codexMonitor.dashboard
        let tasks = channels.flatMap { source.forChannel($0).tasks }
        let result = CodeDashboard(tasks: tasks, selection: monitoredSelection, account: monitoredAccount, profileIDs: source.profileIDs)
        cachedCode = (codexMonitor.revision, channels, result)
        return result
    }
    func openCodeProvider() { ApplicationNavigationService.openProvider(codeProvider) }
    func openCodeProvider(_ provider: CodeProvider) { ApplicationNavigationService.openProvider(provider) }
    var codeProvider: CodeProvider { codeDashboard.compactProvider ?? codeDashboard.provider }
    let music: MusicViewModel
    let agenda: AgendaViewModel
    let permissions: PermissionsViewModel
    let camera: CameraViewModel
    let fans = FanViewModel()
    let bridgeFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OrdinaryNotch")
    var ticker: Timer?
    var ticks = 0
    enum Tab: String, CaseIterable { case overview = "Overview", focus = "Clock", codex = "Codex", shelf = "File Shelf", fans = "Fans", mirror = "Mirror" }

    private var subscriptions = Set<AnyCancellable>()
    init(preferences: PreferencesViewModel? = nil, isPreview: Bool = false, music: MusicViewModel? = nil) {
        self.preferences = preferences ?? PreferencesViewModel()
        self.isPreview = isPreview
        self.music = music ?? MusicViewModel(); self.camera = CameraViewModel()
        let agendaService = AgendaService()
        self.agenda = AgendaViewModel(service: agendaService, observeChanges: !isPreview)
        self.permissions = PermissionsViewModel(agenda: agendaService)
        welcomeBuildID = WelcomeService.currentBuildID
        welcomePending = !self.preferences.hasShownWelcome(for: welcomeBuildID)
        for publisher in [self.music.objectWillChange, camera.objectWillChange, agenda.objectWillChange, clock.objectWillChange, codexMonitor.objectWillChange, agentActions.objectWillChange, fans.objectWillChange, battery.objectWillChange, thermal.objectWillChange] {
            publisher.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        }
        self.preferences.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        self.preferences.$values.map(\.lyricsTimingOffset).removeDuplicates().sink { [weak self] offset in
            self?.music.lyrics.setTimingOffset(offset)
        }.store(in: &subscriptions)
        self.preferences.$values.map(\.passAgentQuestions).removeDuplicates().sink { [weak self] enabled in
            self?.agentActions.setEnabled(enabled)
        }.store(in: &subscriptions)
    }
    func isTabVisible(_ tab: Tab) -> Bool { true }
    private var lastExpandedTab: Tab = .overview
    private var closingTab: Tab = .overview
    // Logical navigation resets immediately; outgoing content keeps its identity while fading.
    var detailTab: Tab { expanded ? tab : closingTab }
    func setExpanded(_ value: Bool, selecting requestedTab: Tab? = nil) {
        guard expanded != value else {
            if value, let requestedTab { selectTab(requestedTab) }
            return
        }
        if !value { closingTab = tab }
        expanded = value
        if value {
            let next = requestedTab ?? (preferences.values.rememberLastTab ? lastExpandedTab : .overview)
            selectTab(isTabVisible(next) ? next : .overview)
        } else {
            lastExpandedTab = tab == .mirror ? .overview : tab
            // Camera always returns to Home after collapsing.
            selectTab(.overview)
            pinned = false
        }
    }
    private var pinBeforeMirror: Bool?
    private var tabBeforeMirror: Tab = .overview
    func activateTab(_ next: Tab) {
        if next == .mirror && tab == .mirror {
            selectTab(isTabVisible(tabBeforeMirror) ? tabBeforeMirror : .overview)
        } else { selectTab(next) }
    }
    func selectTab(_ next: Tab) {
        guard isTabVisible(next) else { return }
        if next == .mirror && tab != .mirror { tabBeforeMirror = tab }
        tab = next
        if next == .fans { fans.refresh() }
        if next == .overview { agenda.refresh() }
        if next == .mirror {
            if pinBeforeMirror == nil { pinBeforeMirror = pinned }
            pinned = true
            camera.start()
        } else {
            camera.stop()
            if let previous = pinBeforeMirror { pinned = previous; pinBeforeMirror = nil }
        }
    }
    func start() {
        guard ticker == nil else { return }
        readActivity(); clock.refresh(); music.refresh(); agenda.refresh(); fans.refresh()
        ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
    }
    func tick() {
        let current = Date(); ticks += 1
        if Int(current.timeIntervalSince1970) != Int(now.timeIntervalSince1970) { now = current }
        battery.tick(at: current, values: preferences.values, canPresent: canPresentNotices() && !thermal.active)
        thermal.tick(snapshot: fans.snapshot, at: current, enabled: preferences.values.thermalAlerts, canPresent: canPresentNotices() && !battery.active)
        if !music.lyrics.enabled && (expanded && tab == .overview || ticks % 4 == 0) { music.updatePosition() }
        if ticks % 2 == 0 { clock.refresh() }
        readActivity()
        if ticks % 8 == 0 { music.refresh(); fans.refresh() }
        if ticks % 240 == 0 { agenda.refresh() }
    }
    func readActivity() {
        if !isPreview { agentActions.refresh(tasks: codeDashboard.tasks, channels: codeChannels) }
        codexMonitor.refresh(bridge: bridgeFolder.appendingPathComponent("activity.json"), selection: monitoredSelection, account: monitoredAccount)
    }
}

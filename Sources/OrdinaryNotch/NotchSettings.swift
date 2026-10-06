import Foundation

enum DeveloperDisplayOverride: String, Codable, CaseIterable {
    case automatic, island, notch
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .island: "Force Dynamic Island"
        case .notch: "Force Dynamic Notch"
        }
    }
    var style: NotchStyle? {
        switch self { case .automatic: nil; case .island: .island; case .notch: .notch }
    }
}

enum NotchActivityPresentation: String, Codable, CaseIterable {
    case compact, detailed
    var title: String { self == .compact ? "Compact" : "Detailed" }
    var detail: String {
        switch self {
        case .compact: "When two activities are active, show only their primary content in the notch wings."
        case .detailed: "Show both primary and secondary content in the notch wings."
        }
    }
}

enum LyricsPresentation: String, Codable, CaseIterable {
    case integrated, floating
    var title: String { self == .integrated ? "Inside Notch" : "Floating Below" }
    var detail: String {
        self == .integrated
            ? "Lyrics add a row at the bottom of the notch. Use the mic button beside the audio output to show or hide them."
            : "Lyrics float below the notch with an album-colored gradient and soft shadow, without enlarging the notch."
    }
}

struct NotchSettings: Codable, Equatable {
    var showDeveloperMenu = false
    var developerDisplayOverride: DeveloperDisplayOverride = .automatic
    var highlightPhysicalNotch = false
    var showMenuBarIcon = true
    var openOnHover = true
    var openDelay = 0.10
    var closeDelay = 0.15
    var restoreFocus = true
    var rememberLastTab = false
    var reduceMotion = false
    var clipboardHistoryEnabled = false
    var thermalAlerts = true
    var batteryLowAlerts = false
    var batteryChargingAlerts = false
    var batteryFullAlerts = false
    var codeSelection: CodeSelection = .codex
    var codeAccount: CodeAccountFilter = .personal
    var codeLayout: CodeLayout?
    var passAgentQuestions = true
    var showPausedMedia = true
    var lyricsPresentation: LyricsPresentation = .integrated
    var lyricsTimingOffset: Double = 0
    var activityOrder = CompactActivity.allCases.map(\.rawValue)
    var notchActivityPresentation: NotchActivityPresentation = .detailed
    private var activityOrderVersion = 1
    var orderedActivities: [CompactActivity] { activityOrder.compactMap(CompactActivity.init(rawValue:)) }
    var hiddenActivities: Set<String> = []
    var timerPresets = [30, 60, 180, 300, 600, 900, 1200, 1800, 3600]
    var timerPresetsUseSeconds = true

    init() {}
    private enum CodingKeys: String, CodingKey {
        case clipboardHistoryEnabled
        case showDeveloperMenu, highlightPhysicalNotch, developerDisplayOverride
        case showMenuBarIcon, openOnHover, openDelay, closeDelay, restoreFocus, rememberLastTab, reduceMotion
        case thermalAlerts
        case showPausedMedia, lyricsPresentation, lyricsTimingOffset, activityOrder, activityOrderVersion, hiddenActivities, timerPresets, timerPresetsUseSeconds
        case batteryLowAlerts, batteryChargingAlerts, batteryFullAlerts
        case codeSelection, codeAccount, codeLayout, passAgentQuestions
        case notchActivityPresentation
    }
    init(from decoder: Decoder) throws {
        self.init()
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        lyricsTimingOffset = try saved.decodeIfPresent(Double.self, forKey: .lyricsTimingOffset) ?? 0
        lyricsPresentation = (try saved.decodeIfPresent(String.self, forKey: .lyricsPresentation)).flatMap(LyricsPresentation.init(rawValue:)) ?? .integrated
        clipboardHistoryEnabled = try saved.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? false
        showDeveloperMenu = try saved.decodeIfPresent(Bool.self, forKey: .showDeveloperMenu) ?? showDeveloperMenu
        developerDisplayOverride = (try saved.decodeIfPresent(String.self, forKey: .developerDisplayOverride)).flatMap(DeveloperDisplayOverride.init(rawValue:)) ?? .automatic
        highlightPhysicalNotch = try saved.decodeIfPresent(Bool.self, forKey: .highlightPhysicalNotch) ?? false
        showMenuBarIcon = try saved.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? showMenuBarIcon
        openOnHover = try saved.decodeIfPresent(Bool.self, forKey: .openOnHover) ?? openOnHover
        openDelay = try saved.decodeIfPresent(Double.self, forKey: .openDelay) ?? openDelay
        closeDelay = try saved.decodeIfPresent(Double.self, forKey: .closeDelay) ?? closeDelay
        restoreFocus = try saved.decodeIfPresent(Bool.self, forKey: .restoreFocus) ?? restoreFocus
        rememberLastTab = try saved.decodeIfPresent(Bool.self, forKey: .rememberLastTab) ?? rememberLastTab
        reduceMotion = try saved.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? reduceMotion
        thermalAlerts = try saved.decodeIfPresent(Bool.self, forKey: .thermalAlerts) ?? true
        batteryLowAlerts = try saved.decodeIfPresent(Bool.self, forKey: .batteryLowAlerts) ?? batteryLowAlerts
        batteryChargingAlerts = try saved.decodeIfPresent(Bool.self, forKey: .batteryChargingAlerts) ?? batteryChargingAlerts
        batteryFullAlerts = try saved.decodeIfPresent(Bool.self, forKey: .batteryFullAlerts) ?? batteryFullAlerts
        codeAccount = (try saved.decodeIfPresent(String.self, forKey: .codeAccount)).flatMap(CodeAccountFilter.init(rawValue:)) ?? .personal
        codeSelection = (try saved.decodeIfPresent(String.self, forKey: .codeSelection)).flatMap(CodeSelection.init(rawValue:)) ?? .codex
        codeLayout = (try saved.decodeIfPresent(String.self, forKey: .codeLayout)).flatMap(CodeLayout.init(rawValue:))
        passAgentQuestions = try saved.decodeIfPresent(Bool.self, forKey: .passAgentQuestions) ?? passAgentQuestions
        showPausedMedia = try saved.decodeIfPresent(Bool.self, forKey: .showPausedMedia) ?? showPausedMedia
        activityOrder = try saved.decodeIfPresent([String].self, forKey: .activityOrder) ?? activityOrder
        notchActivityPresentation = (try saved.decodeIfPresent(String.self, forKey: .notchActivityPresentation))
            .flatMap(NotchActivityPresentation.init(rawValue:)) ?? .detailed
        let savedOrderVersion = try saved.decodeIfPresent(Int.self, forKey: .activityOrderVersion) ?? 0
        if savedOrderVersion == 0, activityOrder == ["media", "timer", "stopwatch", "codex"] {
            activityOrder = CompactActivity.allCases.map(\.rawValue)
        }
        activityOrderVersion = max(1, savedOrderVersion)
        hiddenActivities = try saved.decodeIfPresent(Set<String>.self, forKey: .hiddenActivities) ?? hiddenActivities
        if let savedPresets = try saved.decodeIfPresent([Int].self, forKey: .timerPresets) {
            let storedAsSeconds = try saved.decodeIfPresent(Bool.self, forKey: .timerPresetsUseSeconds) ?? false
            timerPresets = storedAsSeconds ? savedPresets : savedPresets.map { $0 * 60 }
        }
        timerPresetsUseSeconds = true
    }

    func normalized() -> NotchSettings {
        var result = self
        let defaults = NotchSettings()
        var seen: Set<String> = []
        result.activityOrder = (activityOrder + defaults.activityOrder).filter {
            defaults.activityOrder.contains($0) && seen.insert($0).inserted
        }
        result.hiddenActivities.formIntersection(defaults.activityOrder)
        result.lyricsTimingOffset = lyricsTimingOffset.isFinite ? min(5, max(-5, lyricsTimingOffset)) : 0
        result.openDelay = openDelay.isFinite ? min(1, max(0, openDelay)) : defaults.openDelay
        result.closeDelay = closeDelay.isFinite ? min(2, max(0.1, closeDelay)) : defaults.closeDelay
        result.timerPresets = timerPresets.count == 9 ? timerPresets.map { min(10_800, max(30, ($0 / 30) * 30)) } : defaults.timerPresets
        result.timerPresetsUseSeconds = true
        return result
    }
}

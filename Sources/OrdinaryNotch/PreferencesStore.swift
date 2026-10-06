import Foundation

@MainActor
final class PreferencesStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }
    func hasShownWelcome(for buildID: String) -> Bool {
        defaults.string(forKey: "notch.welcome.shownBuild") == buildID
    }
    func markWelcomeShown(for buildID: String) {
        defaults.set(buildID, forKey: "notch.welcome.shownBuild")
    }
    func load() -> NotchSettings {
        guard let data = defaults.data(forKey: "notch.preferences.v1"),
              let values = try? JSONDecoder().decode(NotchSettings.self, from: data) else { return .init() }
        return values
    }
    func save(_ values: NotchSettings) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: "notch.preferences.v1")
    }
}

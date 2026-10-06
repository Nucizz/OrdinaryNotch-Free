import FanCore
import Foundation
import Combine

@MainActor
final class PreferencesViewModel: ObservableObject {
    typealias Values = NotchSettings


    static let storageKey = "notch.preferences.v1"
    private let storage: PreferencesStore
    @Published var values: Values {
        didSet {
            guard values != oldValue else { return }
            storage.save(values.normalized())
        }
    }

    init(defaults: UserDefaults = .standard) {
        storage = PreferencesStore(defaults: defaults)
        values = storage.load().normalized()
    }

    func setActivity(_ activity: CompactActivity, visible: Bool) {
        if visible { values.hiddenActivities.remove(activity.rawValue) }
        else { values.hiddenActivities.insert(activity.rawValue) }
    }
    func reset() { values = Values() }
    func hasShownWelcome(for buildID: String) -> Bool { storage.hasShownWelcome(for: buildID) }
    func markWelcomeShown(for buildID: String) { storage.markWelcomeShown(for: buildID) }
    func moveActivity(_ activity: CompactActivity, by offset: Int) {
        guard let index = values.activityOrder.firstIndex(of: activity.rawValue),
              values.activityOrder.indices.contains(index + offset) else { return }
        values.activityOrder.swapAt(index, index + offset)
    }
}

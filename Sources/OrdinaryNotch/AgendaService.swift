import AppKit
import Combine
import EventKit

struct AgendaAccess: Equatable {
    var calendar = false
    var reminders = false
}
enum AgendaKind: Hashable { case calendar, reminders }

@MainActor
protocol AgendaServing: AnyObject {
    var access: CurrentValueSubject<AgendaAccess, Never> { get }
    var changes: PassthroughSubject<Void, Never> { get }
    func refreshAuthorization()
    func request(_ kind: AgendaKind) async throws
    func fetchItems() async -> [AgendaItem]
}

/// One EventKit store serves Home and Settings. All store operations use its serial queue.
@MainActor
final class AgendaService: AgendaServing {
    let access = CurrentValueSubject<AgendaAccess, Never>(AgendaAccess())
    let changes = PassthroughSubject<Void, Never>()
    private let worker = EventKitWorker()
    private var subscriptions = Set<AnyCancellable>()
    private var requesting = Set<EKEntityType>()
    private var recentGrants: [AgendaKind: Date] = [:]
    init() {
        refreshAuthorization()
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAuthorization(); self?.changes.send() }
            .store(in: &subscriptions)
    }
    private func currentAccess() -> AgendaAccess {
        func granted(_ entity: EKEntityType, _ kind: AgendaKind) -> Bool {
            let status = EKEventStore.authorizationStatus(for: entity)
            return status == .fullAccess || (status == .notDetermined && recentGrants[kind].map { Date() < $0 } == true)
        }
        return AgendaAccess(calendar: granted(.event, .calendar), reminders: granted(.reminder, .reminders))
    }
    func refreshAuthorization() {
        guard requesting.isEmpty else { return }
        let value = currentAccess()
        if access.value != value { access.send(value) }
    }
    func request(_ kind: AgendaKind) async throws {
        let entity: EKEntityType = kind == .calendar ? .event : .reminder
        guard !requesting.contains(entity) else { return }
        let status = EKEventStore.authorizationStatus(for: entity)
        if status == .fullAccess { refreshAuthorization(); return }
        if status == .denied || status == .restricted {
            ApplicationNavigationService.openPrivacy(kind == .calendar ? "Calendars" : "Reminders")
            refreshAuthorization(); return
        }
        requesting.insert(entity)
        do {
            let granted = try await worker.request(entity)
            requesting.remove(entity)
            recentGrants[kind] = granted ? Date().addingTimeInterval(10) : nil
            // The completion result is authoritative even before the global cache catches up.
            var value = currentAccess()
            if kind == .calendar { value.calendar = granted } else { value.reminders = granted }
            if access.value != value { access.send(value) }
            changes.send()
        } catch {
            requesting.remove(entity); refreshAuthorization(); throw error
        }
    }
    func fetchItems() async -> [AgendaItem] { await worker.fetch(access.value) }
}

private final class EventKitWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ordinary.agenda", qos: .utility)
    private let store = EKEventStore()
    func request(_ entity: EKEntityType) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let completed: (Bool, Error?) -> Void = { granted, error in
                    self.queue.async {
                        if granted { self.store.reset() }
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: granted) }
                    }
                }
                if entity == .event { self.store.requestFullAccessToEvents(completion: completed) }
                else { self.store.requestFullAccessToReminders(completion: completed) }
            }
        }
    }
    func fetch(_ access: AgendaAccess) async -> [AgendaItem] {
        await withCheckedContinuation { continuation in
            queue.async {
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: Date())
                let end = calendar.date(byAdding: .day, value: 1, to: start)!
                let events: [AgendaItem] = access.calendar ? self.store.events(matching: self.store.predicateForEvents(withStart: start, end: end, calendars: nil)).map {
                    AgendaItem(id: $0.calendarItemIdentifier, title: $0.title ?? "Untitled event", date: $0.startDate, isReminder: false, allDay: $0.isAllDay)
                } : []
                guard access.reminders else { continuation.resume(returning: Self.sorted(events)); return }
                self.store.fetchReminders(matching: self.store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)) { reminders in
                    let rows = (reminders ?? []).map { AgendaItem(id: $0.calendarItemIdentifier, title: $0.title ?? "Reminder", date: $0.dueDateComponents.flatMap(calendar.date(from:)), isReminder: true, allDay: false) }
                    continuation.resume(returning: Self.sorted(events + rows))
                }
            }
        }
    }
    private static func sorted(_ items: [AgendaItem]) -> [AgendaItem] {
        items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}

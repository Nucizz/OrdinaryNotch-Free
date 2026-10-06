import Combine
import Foundation

@MainActor
final class AgendaViewModel: ObservableObject {
    @Published var items: [AgendaItem] = []
    @Published var calendarGranted = false
    @Published var remindersGranted = false
    @Published private(set) var connecting = false
    @Published var message: String?
    private let service: any AgendaServing
    private var subscriptions = Set<AnyCancellable>()
    private var loading = false
    private var reloadRequested = false
    private var nextRefresh = Date.distantPast
    init(service: any AgendaServing, observeChanges: Bool = true) {
        self.service = service
        guard observeChanges else { return }
        service.access.removeDuplicates().sink { [weak self] access in
            guard let self else { return }
            if calendarGranted != access.calendar { calendarGranted = access.calendar }
            if remindersGranted != access.reminders { remindersGranted = access.reminders }
            items = items.filter { $0.isReminder ? access.reminders : access.calendar }
            if access.calendar && access.reminders { message = nil }
            refresh(force: true, checkAuthorization: false)
        }.store(in: &subscriptions)
        service.changes.sink { [weak self] in self?.refresh(force: true, checkAuthorization: false) }.store(in: &subscriptions)
    }
    func connect() {
        guard !connecting else { return }
        connecting = true
        Task {
            defer { connecting = false }
            for kind in [AgendaKind.calendar, .reminders] {
                do { try await service.request(kind) }
                catch { message = error.localizedDescription }
            }
            if !calendarGranted || !remindersGranted { message = "Access is off. Enable it in System Settings → Privacy & Security." }
            refresh(force: true)
        }
    }
    func refresh(force: Bool = false, checkAuthorization: Bool = true) {
        if checkAuthorization { service.refreshAuthorization() }
        guard force || Date() >= nextRefresh else { return }
        guard !loading else { reloadRequested = true; return }
        loading = true
        nextRefresh = Date().addingTimeInterval(30)
        let access = service.access.value
        Task {
            let result = await service.fetchItems()
            // Permission revocation or a newer grant must supersede an in-flight fetch.
            if service.access.value == access && !reloadRequested, items != result { items = result }
            loading = false
            if reloadRequested { reloadRequested = false; refresh(force: true, checkAuthorization: false) }
        }
    }
}

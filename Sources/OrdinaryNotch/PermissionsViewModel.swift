import AppKit
import Combine

@MainActor
final class PermissionsViewModel: ObservableObject {
    @Published private(set) var cameraGranted = false
    @Published private(set) var calendarGranted = false
    @Published private(set) var remindersGranted = false
    @Published private(set) var accessibility = false
    @Published private(set) var claudeHooks = false
    @Published private(set) var hookError: String?
    @Published private(set) var error: String?
    @Published private(set) var requesting = false
    @Published private(set) var requestingAll = false
    private let agenda: any AgendaServing
    private let privacy: any PrivacyServing
    private var subscriptions = Set<AnyCancellable>()
    private var polling: AnyCancellable?
    init(agenda: any AgendaServing, privacy: (any PrivacyServing)? = nil) {
        self.agenda = agenda; self.privacy = privacy ?? PrivacyService()
        agenda.access.removeDuplicates().sink { [weak self] state in
            guard let self else { return }
            if calendarGranted != state.calendar { calendarGranted = state.calendar }
            if remindersGranted != state.reminders { remindersGranted = state.reminders }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        refresh()
    }
    func refresh() {
        let camera = privacy.cameraGranted, trusted = privacy.accessibilityGranted, hooks = privacy.hooksInstalled()
        if cameraGranted != camera { cameraGranted = camera }
        if accessibility != trusted { accessibility = trusted }
        if claudeHooks != hooks { claudeHooks = hooks }
        agenda.refreshAuthorization()
    }
    func appear() {
        refresh()
        guard polling == nil else { return }
        polling = Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refresh() }
    }
    func disappear() { polling = nil }
    func open(_ pane: String) { privacy.open(pane) }
    func requestCamera() { Task { await privacy.requestCamera(); refresh() } }
    func requestAgenda(_ kind: AgendaKind) {
        let granted = kind == .calendar ? calendarGranted : remindersGranted
        if granted { return }
        requesting = true
        Task {
            defer { requesting = false }
            do { try await agenda.request(kind); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
    func requestAccessibility() { privacy.requestAccessibility(); refresh() }
    var requestInProgress: Bool { requesting || requestingAll }
    var hasMissingPermissions: Bool {
        !cameraGranted || !calendarGranted || !remindersGranted || !accessibility
    }
    func requestAll() {
        guard !requestInProgress else { return }
        requestingAll = true
        Task {
            defer { requestingAll = false; refresh() }
            if !cameraGranted { await privacy.requestCamera() }
            var failures: [String] = []
            for kind in [AgendaKind.calendar, .reminders] {
                let granted = kind == .calendar ? calendarGranted : remindersGranted
                if !granted {
                    do { try await agenda.request(kind) }
                    catch { failures.append(error.localizedDescription) }
                }
            }
            if !accessibility { privacy.requestAccessibility() }
            error = failures.isEmpty ? nil : failures.joined(separator: "\n")
        }
    }
    func toggleHooks() {
        do { try privacy.setHooksEnabled(!claudeHooks); claudeHooks = privacy.hooksInstalled(); hookError = nil }
        catch { hookError = error.localizedDescription }
    }
}

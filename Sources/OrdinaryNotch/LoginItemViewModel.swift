import Combine
import ServiceManagement

@MainActor
final class LoginItemViewModel: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var error: String?
    private let client: LoginItemClient

    init(client: LoginItemClient = LoginItemClient()) {
        self.client = client
        status = client.status()
    }
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    func refresh() { let next = client.status(); if status != next { status = next } }
    func setEnabled(_ enabled: Bool) {
        refresh()
        error = nil
        guard enabled != isEnabled else { return }
        do {
            if enabled { try client.register() }
            else { try client.unregister() }
        } catch {
            self.error = "Couldn’t change launch at login. \(error.localizedDescription)"
        }
        // macOS is the source of truth, including denied approval and failed registration.
        refresh()
    }
    func openLoginItems() { client.openSettings() }
}

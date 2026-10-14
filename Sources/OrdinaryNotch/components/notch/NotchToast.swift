import Combine
import Foundation

struct NotchToast: Hashable {
    let symbol: String
    let title: String
    let detail: String
    var postponesFullScreenHide = false
}

@MainActor final class NotchToastViewModel: ObservableObject {
    @Published private(set) var notice: NotchToast?
    private var expiration: Task<Void, Never>?
    private var generation = 0
    private let wait: (Duration) async throws -> Void
    init(wait: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) { self.wait = wait }
    func show(_ notice: NotchToast) {
        dismiss()
        self.notice = notice
        let generation = generation
        expiration = Task { [weak self, wait] in
            do { try await wait(.seconds(3)) } catch { return }
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            self.dismiss()
        }
    }
    func dismiss() {
        generation += 1; expiration?.cancel(); expiration = nil
        if notice != nil { notice = nil }
    }
}

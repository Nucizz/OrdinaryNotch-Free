import Foundation

/// Tokens keep a late permission/start callback from reviving a closed preview.
struct CameraRequestState {
    private(set) var generation = 0
    private(set) var requested = false
    mutating func start() -> Int? {
        guard !requested else { return nil }
        generation += 1; requested = true
        return generation
    }
    mutating func stop() { generation += 1; requested = false }
    func accepts(_ token: Int) -> Bool { requested && token == generation }
}

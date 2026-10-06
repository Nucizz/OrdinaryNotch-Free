import AppKit
import AVFoundation
import EventKit
import SwiftUI
/// One owner controls the requested state; capture work is serialized off the UI thread.
@MainActor
final class CameraViewModel: ObservableObject {
    @Published private(set) var session: AVCaptureSession?
    @Published private(set) var running = false
    @Published private(set) var message = ""
    @Published private(set) var isStarting = false
    private var request = CameraRequestState()
    private let engine: any CameraServing
    init(engine: any CameraServing = CameraEngine()) { self.engine = engine }

    func start() {
        guard let token = request.start() else { return }
        isStarting = true; message = ""
        Task {
            let granted = await engine.authorize()
            guard request.accepts(token) else { return }
            guard granted else {
                request.stop(); isStarting = false
                message = "Allow Camera access in System Settings → Privacy & Security."
                return
            }
            engine.start { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.request.accepts(token) else {
                        if case .success(let staleSession) = result { self.engine.stop(expected: staleSession) }
                        return
                    }
                    self.isStarting = false
                    switch result {
                    case .success(let session): self.session = session; self.running = true
                    case .failure(let error): self.request.stop(); self.message = error.localizedDescription
                    }
                }
            }
        }
    }
    func stop() {
        request.stop()
        running = false; isStarting = false; session = nil; message = ""
        engine.stop(expected: nil)
    }
}

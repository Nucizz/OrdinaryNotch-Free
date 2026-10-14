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
    @Published private(set) var isCapturing = false
    @Published private(set) var captureMessage: String?
    @Published private(set) var captureFailed = false
    private var captureID: UUID?
    private var latestPhotoID: UUID?
    private var captureTimeoutTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private let messageDuration: Duration
    private let waitForMessageExpiry: (Duration) async throws -> Void
    private let captureTimeout: Duration
    private let savePhoto: (Data) async throws -> Void
    private var request = CameraRequestState()
    private let engine: any CameraServing
    init(engine: any CameraServing = CameraEngine(),
         captureTimeout: Duration = .seconds(10),
         messageDuration: Duration = .seconds(3),
         waitForMessageExpiry: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         savePhoto: @escaping (Data) async throws -> Void = CameraPhotoService.save) {
        self.engine = engine
        self.savePhoto = savePhoto
        self.captureTimeout = captureTimeout
        self.messageDuration = messageDuration
        self.waitForMessageExpiry = waitForMessageExpiry
    }

    func capture() {
        guard running, !isCapturing else { return }
        let token = UUID()
        captureID = token
        latestPhotoID = token
        messageTask?.cancel()
        isCapturing = true; captureMessage = nil; captureFailed = false
        captureTimeoutTask = Task { [weak self, captureTimeout] in
            do { try await Task.sleep(for: captureTimeout) } catch { return }
            guard let self, self.captureID == token else { return }
            self.stop()
            self.start()
            self.captureMessage = "The camera timed out. Try taking another photo."
            self.captureFailed = true
        }
        engine.capture { [weak self] result in
            Task { @MainActor in
                guard let self, self.captureID == token else { return }
                self.captureTimeoutTask?.cancel()
                self.captureID = nil
                self.isCapturing = false
                do {
                    let data = try result.get()
                    self.captureMessage = "Saving to Photos..."
                    try await self.savePhoto(data)
                    guard self.latestPhotoID == token else { return }
                    self.captureMessage = "Saved to Photos"
                    self.messageTask = Task { [weak self, messageDuration = self.messageDuration,
                                              waitForMessageExpiry = self.waitForMessageExpiry] in
                        do { try await waitForMessageExpiry(messageDuration) } catch { return }
                        guard let self, self.latestPhotoID == token else { return }
                        self.captureMessage = nil
                    }
                } catch {
                    guard self.latestPhotoID == token else { return }
                    self.captureMessage = error.localizedDescription
                    self.captureFailed = true
                }
            }
        }
    }

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
        captureTimeoutTask?.cancel(); captureTimeoutTask = nil
        messageTask?.cancel(); messageTask = nil
        latestPhotoID = nil
        captureID = nil; isCapturing = false; captureMessage = nil; captureFailed = false
        running = false; isStarting = false; session = nil; message = ""
        engine.stop(expected: nil)
    }
    func finishStopping() async { await engine.finishStopping() }
}

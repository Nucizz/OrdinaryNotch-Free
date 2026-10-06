import AppKit
import AVFoundation
import EventKit
import SwiftUI
protocol CameraServing: AnyObject {
    func authorize() async -> Bool
    func start(completion: @escaping (Result<AVCaptureSession, Error>) -> Void)
    func stop(expected: AVCaptureSession?)
}
final class CameraEngine: CameraServing {
    func authorize() async -> Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized ? true : await AVCaptureDevice.requestAccess(for: .video)
    }
    private let queue = DispatchQueue(label: "ordinary.camera")
    // Accessed only on queue. A fresh session prevents stale preview connections on reopen.
    private var active: AVCaptureSession?
    func start(completion: @escaping (Result<AVCaptureSession, Error>) -> Void) {
        queue.async {
            self.releaseSession()
            guard let device = AVCaptureDevice.default(for: .video) else {
                completion(.failure(CameraError.unavailable)); return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                let session = AVCaptureSession()
                session.beginConfiguration()
                session.sessionPreset = .high
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    completion(.failure(CameraError.unavailable)); return
                }
                session.addInput(input)
                session.commitConfiguration()
                self.active = session
                session.startRunning()
                guard session.isRunning else {
                    self.releaseSession(); completion(.failure(CameraError.unavailable)); return
                }
                completion(.success(session))
            } catch { completion(.failure(error)) }
        }
    }
    func stop(expected: AVCaptureSession? = nil) {
        queue.async {
            if let expected, self.active !== expected { return }
            self.releaseSession()
        }
    }
    private func releaseSession() {
        guard let session = active else { return }
        if session.isRunning { session.stopRunning() }
        // The session and its connections can now be released along with the old preview.
        active = nil
    }
    private enum CameraError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Camera is unavailable. Select Mirror to try again." }
    }
}

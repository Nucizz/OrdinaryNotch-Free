import AppKit
import AVFoundation
import EventKit
import SwiftUI
protocol CameraServing: AnyObject {
    func authorize() async -> Bool
    func start(completion: @escaping (Result<AVCaptureSession, Error>) -> Void)
    func stop(expected: AVCaptureSession?)
    func finishStopping() async
    func capture(completion: @escaping (Result<Data, Error>) -> Void)
}
extension CameraServing {
    func finishStopping() async {}
    func capture(completion: @escaping (Result<Data, Error>) -> Void) {
        completion(.failure(CameraCaptureError.unavailable))
    }
}

enum CameraCaptureError: LocalizedError {
    case unavailable, noImage
    var errorDescription: String? {
        switch self {
        case .unavailable: "The camera is not ready to take a photo."
        case .noImage: "The camera could not capture a photo. Try again."
        }
    }
}
final class CameraEngine: CameraServing {
    func authorize() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .notDetermined else { return status == .authorized }
        return await SystemPromptPresentationService.shared.withPrompt {
            await AVCaptureDevice.requestAccess(for: .video)
        }
    }
    private let queue = DispatchQueue(label: "ordinary.camera")
    // Accessed only on queue. A fresh session prevents stale preview connections on reopen.
    private var active: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var photoDelegate: CameraPhotoDelegate?
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
                let output = AVCapturePhotoOutput()
                guard session.canAddOutput(output) else {
                    session.commitConfiguration()
                    completion(.failure(CameraCaptureError.unavailable)); return
                }
                session.addOutput(output)
                self.photoOutput = output
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
    /// Wait behind the queued stop so another app cannot claim a still-running camera.
    func finishStopping() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
    func capture(completion: @escaping (Result<Data, Error>) -> Void) {
        queue.async {
            guard self.active?.isRunning == true, let output = self.photoOutput, self.photoDelegate == nil else {
                completion(.failure(CameraCaptureError.unavailable)); return
            }
            if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            let delegate = CameraPhotoDelegate { [weak self, weak output] result in
                self?.queue.async {
                    if self?.photoOutput === output { self?.photoDelegate = nil }
                    completion(result)
                }
            }
            self.photoDelegate = delegate
            output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: delegate)
        }
    }
    private func releaseSession() {
        guard let session = active else { return }
        if session.isRunning { session.stopRunning() }
        // The session and its connections can now be released along with the old preview.
        active = nil
        photoOutput = nil
        photoDelegate = nil
    }
    private enum CameraError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Camera is unavailable. Select Mirror to try again." }
    }
}

private final class CameraPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void
    private var result: Result<Data, Error> = .failure(CameraCaptureError.noImage)
    init(completion: @escaping (Result<Data, Error>) -> Void) { self.completion = completion }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { result = .failure(error) }
        else if let data = photo.fileDataRepresentation() { result = .success(data) }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        completion(error.map { .failure($0) } ?? result)
    }
}

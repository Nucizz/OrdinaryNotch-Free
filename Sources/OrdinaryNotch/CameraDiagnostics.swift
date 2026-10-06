import AppKit
import AVFoundation

@MainActor
enum CameraDiagnostics {
    /// Explicit developer smoke test: exercise real start/stop and preview detach without saving frames.
    static func run() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            print("Camera check skipped: permission is not granted.")
            NSApp.terminate(nil)
            return
        }
        Task {
            let camera = CameraViewModel()
            for cycle in 1...3 {
                camera.start()
                let deadline = Date().addingTimeInterval(8)
                while camera.isStarting && Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
                guard camera.running, let session = camera.session else {
                    print("Camera cycle \(cycle) failed: \(camera.message)")
                    camera.stop(); NSApp.terminate(nil); return
                }
                let preview = CameraPreview.PreviewView()
                preview.attach(session)
                try? await Task.sleep(for: .milliseconds(300))
                preview.detach()
                camera.stop()
                guard !camera.running, camera.session == nil else {
                    print("Camera cycle \(cycle) failed to close")
                    NSApp.terminate(nil); return
                }
                print("Camera cycle \(cycle): opened, preview attached, detached, stopped")
                try? await Task.sleep(for: .milliseconds(150))
            }
            print("Camera reopen check passed (3 cycles)")
            NSApp.terminate(nil)
        }
    }
}

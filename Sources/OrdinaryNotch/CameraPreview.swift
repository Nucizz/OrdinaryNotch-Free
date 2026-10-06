import AppKit
import AVFoundation
import EventKit
import SwiftUI
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var circular = false
    func makeNSView(context: Context) -> PreviewView { PreviewView() }
    func updateNSView(_ view: PreviewView, context: Context) { view.attach(session, circular: circular) }
    static func dismantleNSView(_ view: PreviewView, coordinator: ()) { view.detach() }
    final class PreviewView: NSView {
        private let preview = AVCaptureVideoPreviewLayer()
        private let circleMask = CAShapeLayer()
        private var circular = false
        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            layer?.addSublayer(preview)
            preview.videoGravity = .resizeAspectFill
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func attach(_ session: AVCaptureSession, circular: Bool = false) {
            if preview.session !== session { preview.session = session }
            if self.circular != circular {
                self.circular = circular
                needsLayout = true
            }
            mirror()
        }
        func detach() { preview.session = nil }
        private func mirror() {
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            preview.frame = bounds
            // Clip the live camera layer itself, not just its SwiftUI host.
            // This also keeps the mask centered when the notch changes size.
            let side = min(bounds.width, bounds.height)
            circleMask.frame = preview.bounds
            circleMask.path = CGPath(ellipseIn: CGRect(x: (bounds.width - side) / 2,
                y: (bounds.height - side) / 2, width: side, height: side), transform: nil)
            preview.mask = circular ? circleMask : nil
            CATransaction.commit()
            mirror()
        }
    }
}

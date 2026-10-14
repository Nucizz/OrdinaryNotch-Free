import Foundation
import Photos

enum CameraPhotoService {
    static func save(_ data: Data) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await SystemPromptPresentationService.shared.withPrompt {
                await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            }
        }
        guard status == .authorized || status == .limited else { throw PhotoError.permission }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "Ordinary Notch \(UUID().uuidString).jpg"
            request.addResource(with: .photo, data: data, options: options)
        }
    }
    private enum PhotoError: LocalizedError {
        case permission
        var errorDescription: String? { "Allow Photos access in System Settings > Privacy & Security to save pictures." }
    }
}

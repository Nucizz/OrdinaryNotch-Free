import CryptoKit
import Foundation

enum WelcomeService {
    // Include the executable digest so local updates are detected even when the
    // marketing version and build number have not changed. Copies keep this ID.
    static let currentBuildID: String = {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        guard let url = bundle.executableURL, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return "\(version):\(build)"
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(version):\(build):\(digest)"
    }()
}

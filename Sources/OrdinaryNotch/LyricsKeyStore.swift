import Foundation
import Security

protocol LyricsKeyStoring {
    func load() throws -> String?
    func save(_ key: String) throws
    func remove() throws
}

struct LyricsKeyStore: LyricsKeyStoring {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "dev.ordinary.notch.free.lyrics",
         kSecAttrAccount as String: "musixmatch-api-key"]
    }
    func load() throws -> String? {
        var lookup = query
        lookup[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = perform { SecItemCopyMatching(lookup as CFDictionary, &result) }
        if status == errSecItemNotFound { return nil }
        try check(status)
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }
    func save(_ key: String) throws {
        let value = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query.merging(value) { _, new in new }
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            try check(SecItemAdd(insert as CFDictionary, nil))
        } else { try check(status) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    private func perform(_ operation: () -> OSStatus) -> OSStatus {
        var previous = DarwinBoolean(false)
        let readStatus = SecKeychainGetUserInteractionAllowed(&previous)
        guard readStatus == errSecSuccess else { return readStatus }
        let status = SecKeychainSetUserInteractionAllowed(false)
        guard status == errSecSuccess else { return status }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return operation()
    }
}

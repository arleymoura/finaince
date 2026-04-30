import Foundation
import Security

struct KeychainHelper {
    private static let service = "finaince"

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue

        delete(forKey: key)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(forKey key: String) -> Bool {
        var query = baseQuery(forKey: key)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Deletes ALL Keychain items that belong to the given service.
    /// Used on first launch after a fresh install, since iOS Keychain survives
    /// app deletion while UserDefaults does not.
    @discardableResult
    static func deleteAll(forService service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

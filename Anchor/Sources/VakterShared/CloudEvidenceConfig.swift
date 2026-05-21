import Foundation
import Security

/// Persists the user's cloud-evidence-upload configuration.
///
/// Non-secret pieces (provider type, keyID, bucket name) live in
/// UserDefaults so they survive launches and are trivially diffable
/// across a `defaults read` for debugging.
///
/// The secret (B2 application key, or the presigned-URL template) lives
/// in the user's Keychain under the `app.vakter.cloud.secret` service
/// — never written to disk. The Keychain ACL allows only Vakter
/// binaries (signed under our Team ID) to read it.
public enum CloudEvidenceConfig {

    private static let providerKey = "vakter.cloud.provider"
    private static let keyIDKey    = "vakter.cloud.keyID"
    private static let bucketKey   = "vakter.cloud.bucket"

    private static let keychainService = "app.vakter.cloud.secret"
    private static let keychainAccount = "default"

    public static func load() -> CloudEvidenceUpload.Configuration? {
        let defaults = UserDefaults.standard
        guard let providerRaw = defaults.string(forKey: providerKey),
              let provider = CloudEvidenceUpload.Provider(rawValue: providerRaw) else {
            return nil
        }
        let secret = readKeychainSecret()
        let keyID  = defaults.string(forKey: keyIDKey)
        let bucket = defaults.string(forKey: bucketKey) ?? ""
        guard !bucket.isEmpty || provider == .presignedURL else {
            return nil
        }
        return CloudEvidenceUpload.Configuration(
            provider: provider,
            keyID: keyID,
            secret: secret,
            bucket: bucket
        )
    }

    public static func save(_ config: CloudEvidenceUpload.Configuration) -> Bool {
        let defaults = UserDefaults.standard
        defaults.set(config.provider.rawValue, forKey: providerKey)
        defaults.set(config.keyID, forKey: keyIDKey)
        defaults.set(config.bucket, forKey: bucketKey)
        if let secret = config.secret {
            return writeKeychainSecret(secret)
        }
        deleteKeychainSecret()
        return true
    }

    /// Wipes all configuration. Equivalent to "disable cloud upload."
    public static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: providerKey)
        defaults.removeObject(forKey: keyIDKey)
        defaults.removeObject(forKey: bucketKey)
        deleteKeychainSecret()
    }

    // MARK: - Keychain

    private static func readKeychainSecret() -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  keychainService,
            kSecAttrAccount as String:  keychainAccount,
            kSecMatchLimit as String:   kSecMatchLimitOne,
            kSecReturnData as String:   true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func writeKeychainSecret(_ value: String) -> Bool {
        let data = value.data(using: .utf8) ?? Data()
        // Delete first; SecItemUpdate fails if no item exists.
        deleteKeychainSecret()
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  keychainService,
            kSecAttrAccount as String:  keychainAccount,
            kSecValueData as String:    data,
            // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly = available
            // after first login, never syncs to iCloud Keychain. Right
            // posture for cloud credentials on a single Mac.
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func deleteKeychainSecret() {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  keychainService,
            kSecAttrAccount as String:  keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

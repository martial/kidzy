import Foundation
import Security

/// The device token, kept in the Keychain (this device only).
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.screenclub.kidzy", kSecAttrAccount as String: key]
    }

    static func get(_ key: String) -> String? {
        #if targetEnvironment(simulator)
        // Unsigned simulator builds have no Keychain access; fall back to defaults.
        if let v = UserDefaults.standard.string(forKey: "sim-keychain." + key) { return v }
        #endif
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String) {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        #if targetEnvironment(simulator)
        if status != errSecSuccess { UserDefaults.standard.set(value, forKey: "sim-keychain." + key) }
        #else
        _ = status
        #endif
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
        #if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: "sim-keychain." + key)
        #endif
    }
}

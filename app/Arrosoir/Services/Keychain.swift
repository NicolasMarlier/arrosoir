import Foundation
import Security

nonisolated enum Keychain {
    private static let service = "com.nicolasmarlier.arrosoir"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Réglages de l'app.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var apiKey: String {
        didSet { Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "anthropic-api-key") }
    }
    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
    }
    var city: String {
        didSet { UserDefaults.standard.set(city, forKey: "city") }
    }
    var safetyNet: Bool {
        didSet { UserDefaults.standard.set(safetyNet, forKey: "safetyNet") }
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    private init() {
        apiKey = Keychain.get("anthropic-api-key") ?? ""
        model = UserDefaults.standard.string(forKey: "model") ?? ""
        city = UserDefaults.standard.string(forKey: "city") ?? "Paris"
        safetyNet = UserDefaults.standard.bool(forKey: "safetyNet")
    }
}

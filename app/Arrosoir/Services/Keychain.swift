import Foundation
import Security

nonisolated enum Keychain {
    private static let service = "com.nicolasmarlier.arrosoir"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        var base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        // Synchronisée via le trousseau iCloud : pas besoin de recoller la clé sur chaque appareil.
        base[kSecAttrSynchronizable as String] = kCFBooleanTrue
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
        didSet { Self.store("model", model) }
    }
    var city: String {
        didSet { Self.store("city", city) }
    }
    var safetyNet: Bool {
        didSet { UserDefaults.standard.set(safetyNet, forKey: "safetyNet") }
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    private init() {
        let key = Keychain.get("anthropic-api-key") ?? ""
        apiKey = key
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.synchronize()
        model = cloud.string(forKey: "model") ?? UserDefaults.standard.string(forKey: "model") ?? ""
        city = cloud.string(forKey: "city") ?? UserDefaults.standard.string(forKey: "city") ?? "Paris"
        safetyNet = UserDefaults.standard.bool(forKey: "safetyNet")
        // Ré-enregistre une éventuelle ancienne clé locale pour qu'elle passe dans le trousseau iCloud.
        if !key.isEmpty { Keychain.set(key, for: "anthropic-api-key") }
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { _ in
            Task { @MainActor in AppSettings.shared.reloadFromCloud() }
        }
    }

    /// Réglages partagés entre appareils (iCloud clé-valeur), avec copie locale.
    private static func store(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.set(value, forKey: key)
    }

    func reloadFromCloud() {
        let cloud = NSUbiquitousKeyValueStore.default
        if let m = cloud.string(forKey: "model"), m != model { model = m }
        if let c = cloud.string(forKey: "city"), c != city { city = c }
        if apiKey.isEmpty, let k = Keychain.get("anthropic-api-key") { apiKey = k }
    }
}

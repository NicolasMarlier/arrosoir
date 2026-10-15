import CloudKit
import Foundation

/// État de la synchronisation iCloud.
enum CloudSync {
    static let containerID = "iCloud.com.nicolasmarlier.arrosoir"
    /// Vrai si la base a été ouverte avec CloudKit.
    nonisolated(unsafe) static var enabled = false

    enum Status: Equatable {
        case ok, noAccount, restricted, unavailable, localOnly

        var label: String {
            switch self {
            case .ok: "✅ Activée : tes plantes se synchronisent entre tes appareils."
            case .noAccount: "Connecte-toi à iCloud dans les Réglages de l'iPhone pour synchroniser."
            case .restricted: "iCloud est restreint sur cet appareil."
            case .unavailable: "iCloud est momentanément indisponible."
            case .localOnly: "Désactivée : les données restent sur cet appareil."
            }
        }
    }

    static func status() async -> Status {
        guard enabled else { return .localOnly }
        let s = try? await CKContainer(identifier: containerID).accountStatus()
        switch s {
        case .available: return .ok
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        default: return .unavailable
        }
    }
}

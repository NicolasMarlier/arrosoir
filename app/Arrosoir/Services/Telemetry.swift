import Foundation
import Sentry

/// Remontée des erreurs vers Sentry.
/// Le DSN vient de `SENTRY_DSN` (app/Config/Secrets.xcconfig, non versionné) : sans DSN, tout est inerte.
/// Jamais de photo ni de clé API envoyée ; seulement les réponses textuelles de Claude quand elles posent problème.
nonisolated enum Telemetry {
    static var dsn: String? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return raw.hasPrefix("https://") ? raw : nil
    }

    static var isEnabled: Bool { dsn != nil }

    static func start() {
        guard let dsn else { return }
        let args = ProcessInfo.processInfo.arguments
        SentrySDK.start { o in
            o.dsn = dsn
            #if DEBUG
            o.environment = "debug"
            #else
            o.environment = "production"
            #endif
            o.sendDefaultPii = false
            o.attachScreenshot = false
            o.attachViewHierarchy = true
            o.enableAppHangTracking = true
            o.tracesSampleRate = 0.2
            o.maxBreadcrumbs = 150
            o.beforeSend = { event in
                // Pas d'envoi depuis les tests / les lancements de démo éphémères.
                if args.contains("-inMemory") || NSClassFromString("XCTestCase") != nil { return nil }
                return event
            }
        }
    }

    // MARK: Fil d'Ariane

    static func breadcrumb(_ message: String, category: String = "app", data: [String: Any]? = nil, level: SentryLevel = .info) {
        guard isEnabled else { return }
        let b = Breadcrumb(level: level, category: category)
        b.message = message
        b.data = data
        SentrySDK.addBreadcrumb(b)
    }

    // MARK: Erreurs

    /// Une pièce jointe texte (réponse brute de Claude, schéma…).
    struct Attachment {
        var name: String
        var text: String
    }

    /// Erreur visible par l'utilisateur ou anomalie notable.
    /// - feature : « identify », « care_profile », « diagnose »… (sert à regrouper / filtrer).
    static func capture(_ error: Error, feature: String, extra: [String: Any] = [:], attachments: [Attachment] = []) {
        guard isEnabled else { return }
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        SentrySDK.capture(error: error) { scope in
            configure(scope, feature: feature, extra: extra, attachments: attachments)
            scope.setTag(value: String(describing: type(of: error)), key: "error.type")
            if let ai = error as? AIError { scope.setTag(value: ai.kind, key: "ai.error") }
            if let msg = (error as? LocalizedError)?.errorDescription { scope.setExtra(value: msg, key: "user_message") }
        }
    }

    /// Anomalie non bloquante (ex. réponse tronquée, décodage de secours utilisé).
    static func warn(_ message: String, feature: String, extra: [String: Any] = [:], attachments: [Attachment] = []) {
        guard isEnabled else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(.warning)
            configure(scope, feature: feature, extra: extra, attachments: attachments)
        }
    }

    private static func configure(_ scope: Scope, feature: String, extra: [String: Any], attachments: [Attachment]) {
        scope.setTag(value: feature, key: "feature")
        if let model = extra["model"] as? String { scope.setTag(value: model, key: "ai.model") }
        for (k, v) in extra { scope.setExtra(value: v, key: k) }
        for a in attachments where !a.text.isEmpty {
            scope.addAttachment(Sentry.Attachment(data: Data(a.text.utf8), filename: a.name, contentType: "text/plain"))
        }
    }

    // MARK: Retour utilisateur

    /// « Signaler un problème » depuis l'app : rattaché au dernier événement capturé s'il y en a un.
    static func feedback(_ message: String) {
        guard isEnabled else { return }
        let id = SentrySDK.capture(message: "Retour utilisateur") { scope in
            scope.setLevel(.info)
            scope.setTag(value: "user_feedback", key: "feature")
            scope.setExtra(value: message, key: "message")
        }
        SentrySDK.capture(feedback: SentryFeedback(message: message, name: nil, email: nil, source: .custom, associatedEventId: id))
    }
}

extension AIError {
    nonisolated var kind: String {
        switch self {
        case .missingKey: "missing_key"
        case .http(let code, _): "http_\(code)"
        case .noToolOutput: "no_tool_output"
        case .decoding: "decoding"
        }
    }
}

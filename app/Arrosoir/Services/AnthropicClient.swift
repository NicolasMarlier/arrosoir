import Foundation

enum AIError: LocalizedError {
    case missingKey
    case http(Int, String)
    case noToolOutput
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Ajoute ta clé API Anthropic dans les réglages."
        case .http(let code, let msg): code == 401 ? "Clé API refusée. Vérifie-la dans les réglages." : "Erreur \(code) : \(msg)"
        case .noToolOutput: "Réponse inattendue de Claude."
        case .decoding(let m): "Réponse illisible (\(m))."
        }
    }
}

/// Client minimal de l'API Messages d'Anthropic.
struct AnthropicClient {
    var apiKey: String
    var model: String

    static let base = URL(string: "https://api.anthropic.com/v1")!
    /// Utilisé si la liste des modèles n'est pas disponible.
    static let fallbackModel = "claude-sonnet-4-5"

    struct ModelInfo: Decodable, Identifiable, Hashable {
        let id: String
        let display_name: String?
    }

    private func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) -> URLRequest {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var r = URLRequest(url: comps.url!)
        r.httpMethod = method
        r.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = body
        r.timeoutInterval = 90
        return r
    }

    /// Envoie la requête ; les erreurs réseau / HTTP sont remontées à Sentry ici (une seule fois).
    private func send(_ r: URLRequest, feature: String) async throws -> Data {
        let started = Date()
        let extra: [String: Any] = ["model": model, "endpoint": r.url?.path ?? ""]
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: r)
        } catch {
            Telemetry.capture(error, feature: feature, extra: extra)
            throw error
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let requestId = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "request-id") ?? ""
        Telemetry.breadcrumb("Claude \(feature) → \(code)", category: "anthropic",
                             data: ["model": model, "status": code, "seconds": Date().timeIntervalSince(started).rounded(), "bytes": data.count, "request_id": requestId])
        guard (200..<300).contains(code) else {
            var msg = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any], let m = err["message"] as? String { msg = m }
            let error = AIError.http(code, msg)
            // Le refus de tool_choice imposé est géré par un repli automatique : pas une erreur.
            if !(code == 400 && msg.contains("tool_choice")) {
                Telemetry.capture(error, feature: feature, extra: extra.merging(["status": code, "api_message": msg, "request_id": requestId]) { a, _ in a })
            }
            throw error
        }
        return data
    }

    func listModels() async throws -> [ModelInfo] {
        struct Resp: Decodable { let data: [ModelInfo] }
        let data = try await send(request("models", query: [URLQueryItem(name: "limit", value: "100")]), feature: "list_models")
        return try JSONDecoder().decode(Resp.self, from: data).data
    }

    /// Choisit un modèle par défaut : le plus récent « sonnet », sinon le premier de la liste.
    static func preferredModel(in models: [ModelInfo]) -> String? {
        models.first { $0.id.contains("sonnet") }?.id ?? models.first?.id
    }

    enum Content {
        case text(String)
        case jpeg(Data)

        var json: [String: Any] {
            switch self {
            case .text(let t): ["type": "text", "text": t]
            case .jpeg(let d): ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": d.base64EncodedString()]]
            }
        }
    }

    /// Appel avec un outil imposé : renvoie l'objet JSON de `tool_use.input`.
    /// Certains modèles refusent un outil imposé : on bascule alors en mode « auto ».
    nonisolated(unsafe) private static var forcedToolUnsupported: Set<String> = []

    /// Sortie d'un appel d'outil : l'objet JSON + la réponse brute (pour les rapports d'erreur).
    struct ToolOutput {
        var data: Data
        var raw: String
        var stopReason: String?
    }

    func callTool(system: String, content: [Content], toolName: String, toolDescription: String, schema: [String: Any], maxTokens: Int = 2048) async throws -> ToolOutput {
        let forced = !Self.forcedToolUnsupported.contains(model)
        var body: [String: Any] = [
            "model": model,
            "max_tokens": forced ? maxTokens : maxTokens + 4000,
            "system": system + (forced ? "" : "\n\nTu DOIS répondre en appelant l'outil « \(toolName) », sans autre texte."),
            "messages": [["role": "user", "content": content.map(\.json)]],
            "tools": [["name": toolName, "description": toolDescription, "input_schema": schema]],
            "tool_choice": forced ? ["type": "tool", "name": toolName] : ["type": "auto"],
        ]
        let data: Data
        do {
            data = try await send(request("messages", method: "POST", body: try JSONSerialization.data(withJSONObject: body)), feature: toolName)
        } catch AIError.http(400, let msg) where forced && msg.contains("tool_choice") {
            Telemetry.breadcrumb("tool_choice imposé refusé, repli en auto", category: "anthropic", data: ["model": model], level: .warning)
            Self.forcedToolUnsupported.insert(model)
            return try await callTool(system: system, content: content, toolName: toolName, toolDescription: toolDescription, schema: schema, maxTokens: maxTokens)
        }
        body = [:]
        let raw = String(data: data, encoding: .utf8) ?? "<\(data.count) octets non UTF-8>"
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let stopReason = obj?["stop_reason"] as? String
        let report: [String: Any] = ["model": model, "tool": toolName, "forced_tool": forced, "max_tokens": forced ? maxTokens : maxTokens + 4000,
                                     "stop_reason": stopReason ?? "?", "usage": obj?["usage"] ?? [:]]
        guard let blocks = obj?["content"] as? [[String: Any]] else {
            Telemetry.capture(AIError.noToolOutput, feature: toolName, extra: report, attachments: [.init(name: "claude-response.json", text: raw)])
            throw AIError.noToolOutput
        }
        if stopReason == "max_tokens" {
            Telemetry.warn("Réponse de Claude tronquée (max_tokens)", feature: toolName, extra: report, attachments: [.init(name: "claude-response.json", text: raw)])
        }
        if let tool = blocks.first(where: { $0["type"] as? String == "tool_use" }), let input = tool["input"] {
            return ToolOutput(data: try JSONSerialization.data(withJSONObject: input), raw: raw, stopReason: stopReason)
        }
        // Dernier recours : un objet JSON dans le texte.
        let text = blocks.compactMap { $0["text"] as? String }.joined()
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            let json = Data(text[start...end].utf8)
            if (try? JSONSerialization.jsonObject(with: json)) != nil {
                Telemetry.breadcrumb("Pas de tool_use, JSON repêché dans le texte", category: "anthropic", data: ["tool": toolName], level: .warning)
                return ToolOutput(data: json, raw: raw, stopReason: stopReason)
            }
        }
        Telemetry.capture(AIError.noToolOutput, feature: toolName, extra: report, attachments: [.init(name: "claude-response.json", text: raw)])
        throw AIError.noToolOutput
    }

    func callText(system: String, prompt: String, maxTokens: Int = 200) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
        ]
        let data = try await send(request("messages", method: "POST", body: try JSONSerialization.data(withJSONObject: body)), feature: "text")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = obj["content"] as? [[String: Any]] else { throw AIError.noToolOutput }
        return blocks.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

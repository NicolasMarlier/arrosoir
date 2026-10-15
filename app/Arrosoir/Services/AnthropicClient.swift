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

    private func send(_ r: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            var msg = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any], let m = err["message"] as? String { msg = m }
            throw AIError.http(code, msg)
        }
        return data
    }

    func listModels() async throws -> [ModelInfo] {
        struct Resp: Decodable { let data: [ModelInfo] }
        let data = try await send(request("models", query: [URLQueryItem(name: "limit", value: "100")]))
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
    func callTool(system: String, content: [Content], toolName: String, toolDescription: String, schema: [String: Any], maxTokens: Int = 2048) async throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": content.map(\.json)]],
            "tools": [["name": toolName, "description": toolDescription, "input_schema": schema]],
            "tool_choice": ["type": "tool", "name": toolName],
        ]
        let data = try await send(request("messages", method: "POST", body: try JSONSerialization.data(withJSONObject: body)))
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = obj["content"] as? [[String: Any]],
              let tool = blocks.first(where: { $0["type"] as? String == "tool_use" }),
              let input = tool["input"] else { throw AIError.noToolOutput }
        return try JSONSerialization.data(withJSONObject: input)
    }

    func callText(system: String, prompt: String, maxTokens: Int = 200) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
        ]
        let data = try await send(request("messages", method: "POST", body: try JSONSerialization.data(withJSONObject: body)))
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = obj["content"] as? [[String: Any]] else { throw AIError.noToolOutput }
        return blocks.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

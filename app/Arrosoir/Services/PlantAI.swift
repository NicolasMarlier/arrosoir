import Foundation

struct SpeciesCandidate: Codable, Hashable, Identifiable {
    var commonName: String
    var scientificName: String
    var confidence: Double
    var id: String { scientificName + commonName }

    var confidenceLabel: String {
        switch confidence {
        case 0.75...: "très probable"
        case 0.35..<0.75: "possible"
        default: "peu probable"
        }
    }
}

struct Identification: Codable {
    var isPlant: Bool
    var candidates: [SpeciesCandidate]
}

/// Tout ce qui passe par Claude : identification, fiche d'entretien, épitaphe.
struct PlantAI {
    let settings: AppSettings

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func client() async throws -> AnthropicClient {
        guard settings.hasAPIKey else { throw AIError.missingKey }
        var c = AnthropicClient(apiKey: settings.apiKey, model: settings.model)
        if settings.model.isEmpty {
            let models = (try? await c.listModels()) ?? []
            let chosen = AnthropicClient.preferredModel(in: models) ?? AnthropicClient.fallbackModel
            settings.model = chosen
            c.model = chosen
        }
        return c
    }

    private var context: String {
        "L'utilisateur vit en appartement à \(settings.city) (chauffage l'hiver). Ses plantes sont d'intérieur."
    }

    // MARK: Identification

    func identify(jpeg: Data) async throws -> Identification {
        let schema: [String: Any] = [
            "type": "object",
            "required": ["is_plant", "candidates"],
            "properties": [
                "is_plant": ["type": "boolean", "description": "La photo montre-t-elle une plante ?"],
                "candidates": [
                    "type": "array", "maxItems": 3,
                    "description": "1 à 3 espèces possibles, de la plus probable à la moins probable.",
                    "items": [
                        "type": "object",
                        "required": ["common_name", "scientific_name", "confidence"],
                        "properties": [
                            "common_name": ["type": "string", "description": "Nom courant en français, court (ex. « Monstera », « Rose du désert »)."],
                            "scientific_name": ["type": "string"],
                            "confidence": ["type": "number", "minimum": 0, "maximum": 1],
                        ],
                    ],
                ],
            ],
        ]
        let data = try await client().callTool(
            system: "Tu es un botaniste expert en plantes d'intérieur. \(context) Identifie l'espèce de la plante en photo.",
            content: [.jpeg(jpeg), .text("Quelle est cette plante ?")],
            toolName: "report_identification",
            toolDescription: "Renvoie l'identification de la plante.",
            schema: schema, maxTokens: 800
        )
        do { return try Self.decoder.decode(Identification.self, from: data) } catch { throw AIError.decoding(error.localizedDescription) }
    }

    // MARK: Fiche d'entretien

    func careProfile(commonName: String, scientificName: String, room: String? = nil, light: LightLevel? = nil) async throws -> CareProfile {
        let seasonal: (String) -> [String: Any] = { desc in
            [
                "type": "object", "description": desc,
                "required": ["spring", "summer", "autumn", "winter"],
                "properties": ["spring": ["type": "number"], "summer": ["type": "number"], "autumn": ["type": "number"], "winter": ["type": "number"]],
            ]
        }
        let months: [String: Any] = ["type": "array", "items": ["type": "integer", "minimum": 1, "maximum": 12]]
        let schema: [String: Any] = [
            "type": "object",
            "required": ["common_name", "scientific_name", "archetype", "intro", "light", "watering", "repotting", "misting_days", "rotation_days", "fertilizing", "dormancy", "pruning"],
            "properties": [
                "common_name": ["type": "string", "description": "Nom courant français court."],
                "scientific_name": ["type": "string"],
                "archetype": [
                    "type": "string", "enum": PlantArchetype.allCases.map(\.rawValue),
                    "description": "Famille visuelle la plus proche pour l'illustration : " + PlantArchetype.allCases.map { "\($0.rawValue) = \($0.promptDescription)" }.joined(separator: " ; "),
                ],
                "intro": ["type": "string", "description": "La plante se présente à la 1re personne, tutoie l'utilisateur, 1 à 2 phrases, ton chaleureux et drôle mais adulte, avec le conseil clé pour la garder en forme. Un emoji maximum."],
                "light": ["type": "string", "description": "Besoin de lumière en quelques mots (ex. « Vive, sans soleil direct »)."],
                "watering": [
                    "type": "object",
                    "required": ["interval_days", "quantity", "method", "check_hint"],
                    "properties": [
                        "interval_days": seasonal("Intervalle typique entre deux arrosages, en jours, pour chaque saison, en intérieur chauffé. En dormance, mettre un grand intervalle (ex. 30)."),
                        "quantity": ["type": "string", "description": "Quantité indicative, qualitative et courte (ex. « Généreuse, jusqu'à ce que ça coule », « Un verre, pas plus »)."],
                        "method": ["type": "string", "description": "Comment arroser, une phrase courte (ex. « Par la soucoupe, garder 1 cm d'eau »)."],
                        "water_type": ["type": "string", "description": "Type d'eau si important (ex. « déminéralisée ou de pluie »), sinon chaîne vide."],
                        "check_hint": ["type": "string", "description": "Comment savoir s'il faut arroser (ex. « Les 2 premiers cm de terre sont secs »)."],
                    ],
                ],
                "dormancy": [
                    "type": "object", "required": ["months", "advice"],
                    "description": "Repos végétatif. Liste vide si la plante n'a pas de vraie dormance.",
                    "properties": ["months": months, "advice": ["type": "string", "description": "Conseil court pendant le repos."]],
                ],
                "misting_days": seasonal("Intervalle de brumisation en jours par saison. 0 si inutile (la plupart des plantes)."),
                "rotation_days": ["type": "number", "description": "Tourner le pot d'un quart tous les N jours (0 si inutile)."],
                "fertilizing": [
                    "type": "object", "required": ["months", "interval_days", "advice"],
                    "properties": ["months": months, "interval_days": ["type": "number"], "advice": ["type": "string"]],
                ],
                "repotting": [
                    "type": "object", "required": ["every_years", "best_months", "advice"],
                    "properties": ["every_years": ["type": "number"], "best_months": months, "advice": ["type": "string", "description": "Une phrase courte."]],
                ],
                "pruning": ["type": "string", "description": "Conseil de taille court, ou chaîne vide si inutile."],
            ],
        ]
        var where_ = ""
        if let room { where_ += " Elle est dans la pièce « \(room) »." }
        if let light { where_ += " Elle est \(light.prompt)." }
        let data = try await client().callTool(
            system: "Tu es un jardinier expert et bienveillant. \(context) Tu rédiges en français des fiches d'entretien fiables, concrètes et concises.",
            content: [.text("Fiche d'entretien pour : \(commonName) (\(scientificName)).\(where_)")],
            toolName: "save_care_profile",
            toolDescription: "Enregistre la fiche d'entretien de la plante.",
            schema: schema, maxTokens: 2000
        )
        do {
            var profile = try Self.decoder.decode(CareProfile.self, from: data)
            if profile.watering.waterType?.isEmpty == true { profile.watering.waterType = nil }
            if profile.dormancy?.months.isEmpty == true { profile.dormancy = nil }
            if profile.fertilizing?.months.isEmpty == true { profile.fertilizing = nil }
            if profile.pruning?.isEmpty == true { profile.pruning = nil }
            return profile
        } catch {
            throw AIError.decoding(error.localizedDescription)
        }
    }

    // MARK: Épitaphe

    func epitaph(name: String, reason: ArchiveReason, since: Date) async -> String {
        let fallback = Voice.epitaph(reason: reason, name: name)
        guard settings.hasAPIKey, let c = try? await client() else { return fallback }
        let what = reason == .died ? "est morte" : "a été donnée à quelqu'un"
        let prompt = "Ma plante « \(name) », adoptée \(Fmt.ago(since)), \(what). Écris une épitaphe en français, tendre et drôle, 12 mots maximum, sans guillemets."
        let text = try? await c.callText(system: "Tu écris des épitaphes de plantes d'intérieur, avec humour léger.", prompt: prompt, maxTokens: 80)
        guard let text, !text.isEmpty else { return fallback }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "«»\"“” "))
    }
}

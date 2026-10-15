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
        if let id = try? Self.decoder.decode(Identification.self, from: data) { return id }
        let j = LenientJSON(data: data)
        let candidates = j["candidates"].array.compactMap { c -> SpeciesCandidate? in
            guard let name = c["common_name", "name"].string else { return nil }
            return SpeciesCandidate(commonName: name, scientificName: c["scientific_name"].string ?? name, confidence: c["confidence"].double ?? 0.5)
        }
        guard !candidates.isEmpty || j["is_plant"].bool == false else { throw AIError.decoding(Self.snippet(data)) }
        return Identification(isPlant: j["is_plant"].bool ?? !candidates.isEmpty, candidates: candidates)
    }

    // MARK: Fiche d'entretien

    func careProfile(commonName: String, scientificName: String, room: String? = nil, light: LightLevel? = nil) async throws -> CareProfile {
        // Schéma volontairement « à plat » : plus robuste quel que soit le modèle.
        let num: (String) -> [String: Any] = { ["type": "number", "description": $0] }
        let str: (String) -> [String: Any] = { ["type": "string", "description": $0] }
        let months: (String) -> [String: Any] = { ["type": "array", "items": ["type": "integer", "minimum": 1, "maximum": 12], "description": $0] }
        let props: [String: Any] = [
            "common_name": str("Nom courant français court."),
            "scientific_name": str("Nom scientifique."),
            "archetype": [
                "type": "string", "enum": PlantArchetype.allCases.map(\.rawValue),
                "description": "Famille visuelle la plus proche pour l'illustration : " + PlantArchetype.allCases.map { "\($0.rawValue) = \($0.promptDescription)" }.joined(separator: " ; "),
            ],
            "intro": str("La plante se présente à la 1re personne, tutoie l'utilisateur, 1 à 2 phrases, ton chaleureux et drôle mais adulte, avec le conseil clé pour la garder en forme. Un emoji maximum."),
            "light": str("Besoin de lumière en quelques mots (ex. « Vive, sans soleil direct »)."),
            "water_spring_days": num("Jours entre deux arrosages au printemps (intérieur chauffé)."),
            "water_summer_days": num("Jours entre deux arrosages en été."),
            "water_autumn_days": num("Jours entre deux arrosages en automne."),
            "water_winter_days": num("Jours entre deux arrosages en hiver (grand intervalle si dormance, ex. 30)."),
            "water_quantity": str("Quantité indicative, qualitative et courte (ex. « Généreuse, jusqu'à ce que ça coule », « Un verre, pas plus »)."),
            "water_method": str("Comment arroser, une phrase courte (ex. « Par la soucoupe, garder 1 cm d'eau »)."),
            "water_type": str("Type d'eau si important (ex. « déminéralisée ou de pluie »), sinon chaîne vide."),
            "water_check_hint": str("Comment savoir qu'il faut arroser (ex. « Les 2 premiers cm de terre sont secs »)."),
            "dormancy_months": months("Mois de repos végétatif (1-12). Liste vide si pas de vraie dormance."),
            "dormancy_advice": str("Conseil court pendant le repos, ou chaîne vide."),
            "mist_spring_days": num("Brumiser tous les N jours au printemps, 0 si inutile (la plupart des plantes)."),
            "mist_summer_days": num("Idem en été, 0 si inutile."),
            "mist_autumn_days": num("Idem en automne, 0 si inutile."),
            "mist_winter_days": num("Idem en hiver, 0 si inutile."),
            "rotation_days": num("Tourner le pot d'un quart tous les N jours, 0 si inutile."),
            "fertilizing_months": months("Mois où donner de l'engrais, liste vide si jamais."),
            "fertilizing_interval_days": num("Engrais tous les N jours pendant ces mois."),
            "fertilizing_advice": str("Type d'engrais / dose, très court."),
            "repotting_every_years": num("Rempoter tous les N ans."),
            "repotting_best_months": months("Meilleurs mois pour rempoter."),
            "repotting_advice": str("Une phrase courte."),
            "pruning": str("Conseil de taille court, ou chaîne vide si inutile."),
        ]
        let schema: [String: Any] = ["type": "object", "required": Array(props.keys), "properties": props]
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
        var profile: CareProfile
        if let loose = CareProfile.lenient(LenientJSON(data: data), fallbackName: commonName, fallbackScientific: scientificName) {
            profile = loose
        } else {
            throw AIError.decoding(Self.snippet(data))
        }
        if profile.watering.waterType?.isEmpty == true { profile.watering.waterType = nil }
        if profile.dormancy?.months.isEmpty == true { profile.dormancy = nil }
        if profile.fertilizing?.months.isEmpty == true { profile.fertilizing = nil }
        if profile.pruning?.isEmpty == true { profile.pruning = nil }
        return profile
    }

    private static func snippet(_ data: Data) -> String {
        String((String(data: data, encoding: .utf8) ?? "").prefix(160))
    }

    // MARK: Diagnostic

    func diagnose(context plantContext: String, note: String, photos: [Data]) async throws -> DiagnosisResult {
        let str: (String) -> [String: Any] = { ["type": "string", "description": $0] }
        let list: (String) -> [String: Any] = { ["type": "array", "items": ["type": "string"], "description": $0] }
        let props: [String: Any] = [
            "title": str("Le diagnostic en 3 à 6 mots (ex. « Excès d'eau probable », « En pleine forme »)."),
            "severity": ["type": "string", "enum": ["ok", "watch", "urgent"], "description": "ok = rien d'inquiétant, watch = à surveiller / corriger, urgent = agir vite."],
            "plant_says": str("Une phrase courte, drôle et tendre, dite par la plante à la 1re personne (tutoiement)."),
            "summary": str("Explication claire en 2 à 4 phrases : ce que tu observes et ce que tu en conclus. Dis-le si tu as un doute."),
            "causes": list("Causes probables, de la plus à la moins probable (1 à 4)."),
            "actions": list("Actions concrètes à faire, dans l'ordre (1 à 5), courtes et précises."),
            "watering_adjustment": ["type": "string", "enum": ["none", "more", "less"], "description": "Faut-il arroser plus souvent (more), moins souvent (less), ou ne rien changer (none) ?"],
            "follow_up_days": ["type": "integer", "description": "Dans combien de jours refaire un point (0 si inutile)."],
        ]
        let schema: [String: Any] = ["type": "object", "required": Array(props.keys), "properties": props]
        var content: [AnthropicClient.Content] = photos.prefix(4).map { .jpeg($0) }
        content.append(.text("""
        \(plantContext)

        Ce que l'utilisateur observe / raconte :
        \(note.isEmpty ? "(rien de plus, regarde les photos)" : note)

        Fais un diagnostic.
        """))
        let data = try await client().callTool(
            system: "Tu es un phytopathologiste et jardinier expert des plantes d'intérieur, bienveillant et précis. \(context) Tu poses un diagnostic à partir des photos, de la description et de l'historique de soins. Tu réponds en français, sans jargon inutile.",
            content: content,
            toolName: "report_diagnosis",
            toolDescription: "Renvoie le diagnostic de la plante.",
            schema: schema, maxTokens: 1800
        )
        let j = LenientJSON(data: data)
        guard let summary = j.find("summary").string else { throw AIError.decoding(Self.snippet(data)) }
        return DiagnosisResult(
            title: j.find("title").string ?? "Diagnostic",
            severity: DiagnosisResult.Severity(rawValue: j.find("severity").string?.lowercased() ?? "") ?? .watch,
            plantSays: j.find("plant_says").string ?? "Merci de t'occuper de moi 🌿",
            summary: summary,
            causes: j.find("causes").array.compactMap(\.string),
            actions: j.find("actions").array.compactMap(\.string),
            wateringAdjustment: DiagnosisResult.WateringAdjustment(rawValue: j.find("watering_adjustment").string?.lowercased() ?? "") ?? .none,
            followUpDays: j.find("follow_up_days").double.map { Int($0) }
        )
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

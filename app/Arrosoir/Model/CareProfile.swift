import Foundation

nonisolated enum Season: String, Codable, CaseIterable, Sendable {
    case spring, summer, autumn, winter

    /// Saison météorologique (hémisphère nord par défaut).
    static func of(_ date: Date, southernHemisphere: Bool = false, calendar: Calendar = .current) -> Season {
        var month = calendar.component(.month, from: date)
        if southernHemisphere { month = (month + 5) % 12 + 1 }
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    var label: String {
        switch self {
        case .spring: "Printemps"
        case .summer: "Été"
        case .autumn: "Automne"
        case .winter: "Hiver"
        }
    }
}

/// Une valeur (en jours) par saison. `nil` = pas nécessaire pendant cette saison.
nonisolated struct SeasonalDays: Codable, Sendable, Equatable {
    var spring: Double?
    var summer: Double?
    var autumn: Double?
    var winter: Double?

    func value(for season: Season) -> Double? {
        let v: Double? = switch season {
        case .spring: spring
        case .summer: summer
        case .autumn: autumn
        case .winter: winter
        }
        guard let v, v > 0 else { return nil }
        return v
    }

    static func all(_ d: Double) -> SeasonalDays { SeasonalDays(spring: d, summer: d, autumn: d, winter: d) }
}

/// Fiche d'entretien générée (une fois) par Claude, stockée localement.
nonisolated struct CareProfile: Codable, Sendable, Equatable {
    struct Watering: Codable, Sendable, Equatable {
        var intervalDays: SeasonalDays
        var quantity: String
        var method: String
        var waterType: String?
        var checkHint: String
    }

    struct Dormancy: Codable, Sendable, Equatable {
        var months: [Int]
        var advice: String
    }

    struct Fertilizing: Codable, Sendable, Equatable {
        var months: [Int]
        var intervalDays: Double
        var advice: String
    }

    struct Repotting: Codable, Sendable, Equatable {
        var everyYears: Double
        var bestMonths: [Int]
        var advice: String
    }

    var commonName: String
    var scientificName: String
    var archetype: String
    var intro: String
    var light: String
    var watering: Watering
    var dormancy: Dormancy?
    var mistingDays: SeasonalDays?
    var rotationDays: Double?
    var fertilizing: Fertilizing?
    var repotting: Repotting
    var pruning: String?

    var archetypeValue: PlantArchetype { PlantArchetype(rawValue: archetype) ?? .upright }
}

nonisolated enum CareKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case watering, stillWet, misting, rotation, fertilizing, repotting, pruning, cleaning

    var id: String { rawValue }

    var label: String {
        switch self {
        case .watering: "Arrosage"
        case .stillWet: "Encore humide"
        case .misting: "Brumisation"
        case .rotation: "Rotation du pot"
        case .fertilizing: "Engrais"
        case .repotting: "Rempotage"
        case .pruning: "Taille"
        case .cleaning: "Nettoyage des feuilles"
        }
    }

    var actionLabel: String {
        switch self {
        case .watering: "Arroser"
        case .stillWet: "Vérifier"
        case .misting: "Brumiser"
        case .rotation: "Tourner le pot d'¼"
        case .fertilizing: "Donner de l'engrais"
        case .repotting: "Rempoter"
        case .pruning: "Tailler"
        case .cleaning: "Dépoussiérer les feuilles"
        }
    }

    var emoji: String {
        switch self {
        case .watering: "💧"
        case .stillWet: "⏳"
        case .misting: "💨"
        case .rotation: "🔄"
        case .fertilizing: "🧪"
        case .repotting: "🪴"
        case .pruning: "✂️"
        case .cleaning: "🧽"
        }
    }

    /// Soins qu'on peut noter manuellement depuis la fiche.
    static let loggable: [CareKind] = [.watering, .misting, .rotation, .fertilizing, .repotting, .pruning, .cleaning]
}

nonisolated enum LightLevel: String, Codable, CaseIterable, Sendable {
    case full, bright, low

    var label: String {
        switch self {
        case .full: "☀️ Plein soleil"
        case .bright: "🌤️ Lumineux"
        case .low: "☁️ Peu"
        }
    }

    var prompt: String {
        switch self {
        case .full: "en plein soleil (soleil direct plusieurs heures)"
        case .bright: "dans une pièce lumineuse, sans soleil direct"
        case .low: "dans un endroit peu lumineux"
        }
    }
}

nonisolated enum ArchiveReason: String, Codable, Sendable {
    case died, given
}

/// Famille d'illustration. Claude choisit la plus proche pour chaque espèce.
nonisolated enum PlantArchetype: String, Codable, CaseIterable, Sendable {
    case monstera, trailing, cactus, carnivorous, upright, caudex, succulent, sword, tree, fern, orchid

    var promptDescription: String {
        switch self {
        case .monstera: "grandes feuilles découpées ou en cœur (monstera, philodendron, alocasia)"
        case .trailing: "plante retombante à petites feuilles en cœur (pothos, lierre, philodendron scandens, tradescantia)"
        case .cactus: "cactus colonnaire ou à bras"
        case .carnivorous: "plante carnivore (dionée, sarracénie, drosera, népenthès)"
        case .upright: "feuilles ovales dressées (calathea, maranta, aglaonema, spathiphyllum)"
        case .caudex: "plante à tronc renflé (rose du désert, pied d'éléphant, bonsaï succulent)"
        case .succulent: "succulente en rosette (echeveria, aloe, haworthia, crassula)"
        case .sword: "feuilles en épée dressées (sansevieria, dracaena, yucca, zamioculcas)"
        case .tree: "petit arbre à feuilles rondes (ficus, pilea, citronnier, olivier)"
        case .fern: "fougère ou plante à frondes (néphrolépis, asplénium, palmier d'intérieur)"
        case .orchid: "orchidée ou plante à hampe florale (phalaenopsis, broméliacée)"
        }
    }
}

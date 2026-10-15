import Foundation

/// Lecture tolérante des réponses de Claude : nombres en texte, objets sérialisés en chaîne,
/// clés en camelCase ou snake_case, champs manquants…
nonisolated struct LenientJSON {
    let raw: Any?

    init(_ raw: Any?) {
        // Un objet ou tableau sérialisé dans une chaîne → on le désérialise.
        if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if (t.hasPrefix("{") || t.hasPrefix("[")), let d = t.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) {
                self.raw = o
                return
            }
        }
        self.raw = raw
    }

    init(data: Data) { self.init(try? JSONSerialization.jsonObject(with: data)) }

    subscript(_ keys: String...) -> LenientJSON {
        guard let dict = raw as? [String: Any] else { return LenientJSON(nil) }
        for k in keys {
            for variant in [k, Self.camel(k), k.lowercased()] {
                if let v = dict[variant], !(v is NSNull) { return LenientJSON(v) }
            }
        }
        return LenientJSON(nil)
    }

    var string: String? {
        switch raw {
        case let s as String: let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    var double: Double? {
        switch raw {
        case let n as NSNumber: return n.doubleValue
        case let s as String:
            let cleaned = s.replacingOccurrences(of: ",", with: ".")
            let digits = cleaned.prefix { "0123456789.".contains($0) }
            return Double(digits) ?? Double(cleaned.filter { "0123456789.".contains($0) })
        default: return nil
        }
    }

    var bool: Bool? {
        switch raw {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["true", "oui", "yes", "1"].contains(s.lowercased())
        default: return nil
        }
    }

    var array: [LenientJSON] {
        if let a = raw as? [Any] { return a.map(LenientJSON.init) }
        return []
    }

    /// Liste de mois : [11, 12, 1], ["11", "12"], "11,12,1"…
    var months: [Int] {
        if let a = raw as? [Any] { return a.compactMap { LenientJSON($0).double.map { Int($0) } }.filter { (1...12).contains($0) } }
        if let s = raw as? String {
            return s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { (1...12).contains($0) }
        }
        return []
    }

    var isNull: Bool { raw == nil }

    private static func camel(_ s: String) -> String {
        let parts = s.split(separator: "_")
        guard let first = parts.first else { return s }
        return String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }
}

extension SeasonalDays {
    nonisolated init?(lenient j: LenientJSON) {
        if let single = j.double { self = .all(single); return }
        let s = j["spring", "printemps"].double, su = j["summer", "ete", "été"].double
        let a = j["autumn", "fall", "automne"].double, w = j["winter", "hiver"].double
        guard s != nil || su != nil || a != nil || w != nil else { return nil }
        self.init(spring: s, summer: su, autumn: a, winter: w)
    }
}

extension CareProfile {
    /// Construit une fiche à partir d'une réponse imparfaite, avec des valeurs par défaut prudentes.
    nonisolated static func lenient(_ input: LenientJSON, fallbackName: String, fallbackScientific: String) -> CareProfile? {
        var j = input
        // Réponse enveloppée ({"care_profile": {...}}) → on déballe.
        if j["watering"].isNull, let dict = j.raw as? [String: Any], dict.count == 1, let inner = dict.values.first {
            j = LenientJSON(inner)
        }
        let w = j["watering"]
        var intervals = SeasonalDays(lenient: w["interval_days", "intervals", "interval"]) ?? SeasonalDays(lenient: j["interval_days"])
        // Saisons manquantes : on comble avec les valeurs présentes.
        if var iv = intervals {
            let known = Season.allCases.compactMap { iv.value(for: $0) }
            guard let avg = known.isEmpty ? nil : known.reduce(0, +) / Double(known.count) else { return nil }
            iv.spring = iv.spring ?? avg; iv.summer = iv.summer ?? (iv.spring ?? avg)
            iv.autumn = iv.autumn ?? avg; iv.winter = iv.winter ?? max(avg, iv.autumn ?? avg) * 1.4
            intervals = iv
        }
        guard let intervals else { return nil }

        let archetypeRaw = j["archetype"].string?.lowercased() ?? ""
        let archetype = PlantArchetype(rawValue: archetypeRaw)?.rawValue ?? PlantArchetype.upright.rawValue

        let dormancyMonths = j["dormancy"]["months"].months
        let fert = j["fertilizing", "fertilization"]
        let fertMonths = fert["months"].months
        let rep = j["repotting"]
        let rotation = j["rotation_days", "rotation"].double

        return CareProfile(
            commonName: j["common_name", "name"].string ?? fallbackName,
            scientificName: j["scientific_name"].string ?? fallbackScientific,
            archetype: archetype,
            intro: j["intro"].string ?? "Salut ! Je suis ravie d'emménager ici 🌿",
            light: j["light"].string ?? "Lumineux, sans soleil brûlant",
            watering: .init(
                intervalDays: intervals,
                quantity: w["quantity"].string ?? "Modérée",
                method: w["method"].string ?? "Par le dessus, quand la terre est sèche.",
                waterType: w["water_type"].string,
                checkHint: w["check_hint"].string ?? "Les premiers centimètres de terre sont secs"
            ),
            dormancy: dormancyMonths.isEmpty ? nil : .init(months: dormancyMonths, advice: j["dormancy"]["advice"].string ?? "Arrose beaucoup moins."),
            mistingDays: SeasonalDays(lenient: j["misting_days", "misting"]).flatMap { m in
                Season.allCases.contains { m.value(for: $0) != nil } ? m : nil
            },
            rotationDays: (rotation ?? 0) > 0 ? rotation : nil,
            fertilizing: fertMonths.isEmpty ? nil : .init(months: fertMonths, intervalDays: fert["interval_days", "interval"].double ?? 30, advice: fert["advice"].string ?? ""),
            repotting: .init(everyYears: rep["every_years", "years"].double ?? 2, bestMonths: rep["best_months", "months"].months.isEmpty ? [3, 4] : rep["best_months", "months"].months, advice: rep["advice"].string ?? ""),
            pruning: j["pruning"].string
        )
    }
}

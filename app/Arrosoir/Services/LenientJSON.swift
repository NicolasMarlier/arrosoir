import Foundation

/// Lecture tolérante des réponses de Claude : nombres en texte, objets sérialisés en chaîne,
/// clés en camelCase ou snake_case, champs rangés au mauvais niveau, champs manquants…
nonisolated struct LenientJSON {
    let raw: Any?

    init(_ raw: Any?) {
        // Un objet ou tableau sérialisé dans une chaîne → on le désérialise.
        if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("{") || t.hasPrefix("["), let d = t.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) {
                self.raw = o
                return
            }
        }
        self.raw = raw
    }

    init(data: Data) { self.init(try? JSONSerialization.jsonObject(with: data)) }

    private static func variants(_ k: String) -> [String] { [k, camel(k), k.lowercased()] }

    /// Clé directe (premier nom trouvé).
    subscript(_ keys: String...) -> LenientJSON { child(keys) }

    func child(_ keys: [String]) -> LenientJSON {
        guard let dict = raw as? [String: Any] else { return LenientJSON(nil) }
        for k in keys {
            for v in Self.variants(k) {
                if let val = dict[v], !(val is NSNull) { return LenientJSON(val) }
            }
        }
        return LenientJSON(nil)
    }

    /// Recherche en profondeur (la clé peut être rangée n'importe où).
    func find(_ keys: String...) -> LenientJSON {
        var queue: [Any] = [raw as Any]
        while !queue.isEmpty {
            let node = LenientJSON(queue.removeFirst())
            let hit = node.child(keys)
            if !hit.isNull { return hit }
            if let dict = node.raw as? [String: Any] {
                queue.append(contentsOf: dict.values.map { LenientJSON($0).raw as Any })
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
            let digits = cleaned.drop { !"0123456789".contains($0) }.prefix { "0123456789.".contains($0) }
            return Double(digits)
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

    /// Comble les saisons manquantes avec les valeurs connues.
    nonisolated func filled() -> SeasonalDays? {
        let known = [spring, summer, autumn, winter].compactMap { $0 }.filter { $0 > 0 }
        guard !known.isEmpty else { return nil }
        let avg = known.reduce(0, +) / Double(known.count)
        let sp = spring ?? avg
        let au = autumn ?? avg
        return SeasonalDays(spring: sp, summer: summer ?? sp, autumn: au, winter: winter ?? max(avg, au) * 1.4)
    }
}

extension CareProfile {
    /// Construit une fiche à partir d'une réponse (plate ou imbriquée, même imparfaite).
    nonisolated static func lenient(_ j: LenientJSON, fallbackName: String, fallbackScientific: String) -> CareProfile? {
        // --- Arrosage : format plat, sinon imbriqué, sinon n'importe où.
        var flat = SeasonalDays(spring: j.find("water_spring_days").double, summer: j.find("water_summer_days").double,
                                autumn: j.find("water_autumn_days").double, winter: j.find("water_winter_days").double)
        if [flat.spring, flat.summer, flat.autumn, flat.winter].allSatisfy({ $0 == nil }) {
            flat = SeasonalDays(lenient: j.find("interval_days", "watering_interval_days", "intervals", "watering_days")) ?? flat
        }
        guard let intervals = flat.filled() else { return nil }

        let mist = SeasonalDays(spring: j.find("mist_spring_days").double, summer: j.find("mist_summer_days").double,
                                autumn: j.find("mist_autumn_days").double, winter: j.find("mist_winter_days").double)
        let mistNested = SeasonalDays(lenient: j.find("misting_days", "misting"))
        let misting = [mist, mistNested].compactMap { $0 }.first { m in Season.allCases.contains { m.value(for: $0) != nil } }

        let archetypeRaw = j.find("archetype").string?.lowercased() ?? ""
        let dormancyMonths = !j.find("dormancy_months").months.isEmpty ? j.find("dormancy_months").months : j.find("dormancy")["months"].months
        let fertMonths = !j.find("fertilizing_months").months.isEmpty ? j.find("fertilizing_months").months : j.find("fertilizing", "fertilization")["months"].months
        let repotMonths = !j.find("repotting_best_months").months.isEmpty ? j.find("repotting_best_months").months : j.find("repotting")["best_months", "months"].months
        let rotation = j.find("rotation_days").double

        return CareProfile(
            commonName: j.find("common_name").string ?? fallbackName,
            scientificName: j.find("scientific_name").string ?? fallbackScientific,
            archetype: PlantArchetype(rawValue: archetypeRaw)?.rawValue ?? PlantArchetype.upright.rawValue,
            intro: j.find("intro").string ?? "Salut ! Ravie d'emménager ici 🌿",
            light: j.find("light").string ?? "Lumineux, sans soleil brûlant",
            watering: .init(
                intervalDays: intervals,
                quantity: j.find("water_quantity", "quantity").string ?? "Modérée",
                method: j.find("water_method", "method").string ?? "Par le dessus, quand la terre est sèche.",
                waterType: j.find("water_type").string,
                checkHint: j.find("water_check_hint", "check_hint").string ?? "Les premiers centimètres de terre sont secs"
            ),
            dormancy: dormancyMonths.isEmpty ? nil : .init(months: dormancyMonths, advice: (j.find("dormancy_advice").string ?? j.find("dormancy")["advice"].string) ?? "Arrose beaucoup moins."),
            mistingDays: misting,
            rotationDays: (rotation ?? 0) > 0 ? rotation : nil,
            fertilizing: fertMonths.isEmpty ? nil : .init(
                months: fertMonths,
                intervalDays: j.find("fertilizing_interval_days").double ?? j.find("fertilizing")["interval_days", "interval"].double ?? 30,
                advice: j.find("fertilizing_advice").string ?? j.find("fertilizing")["advice"].string ?? ""),
            repotting: .init(
                everyYears: j.find("repotting_every_years", "every_years").double ?? 2,
                bestMonths: repotMonths.isEmpty ? [3, 4] : repotMonths,
                advice: j.find("repotting_advice").string ?? j.find("repotting")["advice"].string ?? ""),
            pruning: j.find("pruning").string
        )
    }
}

import Foundation

/// Formatage en français.
nonisolated enum Fmt {
    static let locale = Locale(identifier: "fr_FR")

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    static func monthName(_ month: Int) -> String {
        let names = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
        return names[(max(1, min(12, month))) - 1]
    }

    /// « au printemps », « en mars-avril »…
    static func monthsPhrase(_ months: [Int]) -> String {
        let s = Set(months)
        if s.isEmpty { return "au printemps" }
        if s.isSubset(of: [3, 4, 5]) { return "au printemps" }
        if s.isSubset(of: [6, 7, 8]) { return "en été" }
        if s.isSubset(of: [9, 10, 11]) { return "en automne" }
        let sorted = months.sorted()
        if sorted.count == 1 { return "en \(monthName(sorted[0]))" }
        return "entre \(monthName(sorted.first!)) et \(monthName(sorted.last!))"
    }

    /// « mer. 15 octobre »
    static func dayHeader(_ d: Date) -> String {
        formatter("EEE d MMMM").string(from: d).capitalizedFirst
    }

    /// « ven. 24 »
    static func shortDay(_ d: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let n = CareEngine.days(from: now, to: d, calendar)
        if n == 0 { return "aujourd'hui" }
        if n == 1 { return "demain" }
        if n < 7 { return formatter("EEE d").string(from: d) }
        return formatter("EEE d MMM").string(from: d)
    }

    static func ago(_ d: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let n = CareEngine.days(from: d, to: now, calendar)
        switch n {
        case ..<1: return "aujourd'hui"
        case 1: return "hier"
        case 2..<45: return "il y a \(n) j"
        case 45..<365: return "il y a \(Int((Double(n) / 30.4).rounded())) mois"
        default:
            let y = Double(n) / 365
            let rounded = (y * 2).rounded() / 2
            return "il y a \(years(rounded))"
        }
    }

    static func years(_ y: Double) -> String {
        if y < 1 { return "\(Int((y * 12).rounded())) mois" }
        let r = (y * 2).rounded() / 2
        let s = r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
        return r < 2 ? "\(s) an" : "\(s) ans"
    }

    static func inDays(_ n: Int) -> String {
        switch n {
        case ..<1: return "aujourd'hui"
        case 1: return "demain"
        default: return "dans \(n) j"
        }
    }

    static func everyDays(_ d: Double) -> String {
        let n = Int(d.rounded())
        if n >= 28 { return "~ \(max(1, Int((d / 30.4).rounded()))) mois" }
        return "~ \(n) j"
    }
}

extension String {
    nonisolated var capitalizedFirst: String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }
}

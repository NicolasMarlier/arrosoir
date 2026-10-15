import Foundation

/// Humeur affichée sur le pot.
nonisolated enum Mood: String, Sendable, CaseIterable {
    case ok, thirsty, sleeping, happy, ghost
}

/// Données nécessaires au calcul, indépendantes de SwiftData (testables).
nonisolated struct PlantSnapshot: Sendable {
    var profile: CareProfile
    var createdAt: Date
    var lastWateredAt: Date?
    var snoozedUntil: Date?
    var learnedFactor: Double = 1
    var manualFactor: Double = 1
    var lastDone: [CareKind: Date] = [:]
}

nonisolated enum WateringState: Equatable, Sendable {
    /// En retard : il faut arroser.
    case water
    /// C'est le moment de vérifier la terre.
    case check
    /// Bientôt (≤ 2 jours).
    case soon(days: Int)
    case later(days: Int)

    var isDue: Bool { self == .water || self == .check }
}

nonisolated struct TaskItem: Equatable, Sendable, Identifiable {
    var kind: CareKind
    var urgent: Bool = false
    var id: String { kind.rawValue }
}

nonisolated struct CareStatus: Sendable {
    var season: Season
    var interval: Double
    var watering: WateringState
    var wateringDue: Date
    var tasks: [TaskItem]
    var dormantUntil: Date?
    var mood: Mood

    var hasTasks: Bool { !tasks.isEmpty }
    var wateringTask: TaskItem? { tasks.first { $0.kind == .watering } }
    var otherTasks: [TaskItem] { tasks.filter { $0.kind != .watering } }

    /// Plus c'est grand, plus c'est urgent (pour trier).
    var urgencyScore: Double {
        switch watering {
        case .water: 3
        case .check: 2
        case .soon(let d): 1 - Double(d) * 0.1
        case .later(let d): -Double(d) * 0.01
        }
    }
}

nonisolated struct HorizonHint: Sendable, Identifiable {
    var kind: CareKind
    var title: String
    var detail: String
    var soon: Bool
    var id: String { kind.rawValue }
}

nonisolated struct UpcomingItem: Sendable, Identifiable {
    var kind: CareKind
    var date: Date
    var id: String { kind.rawValue }
}

nonisolated enum CareEngine {
    static let minFactor = 0.5
    static let maxFactor = 2.5
    /// Ratio de retard à partir duquel on passe de « vérifier » à « arroser ».
    static let urgentRatio = 1.3

    // MARK: Intervalle

    static func baseInterval(_ profile: CareProfile, season: Season) -> Double {
        if let v = profile.watering.intervalDays.value(for: season) { return v }
        let all = Season.allCases.compactMap { profile.watering.intervalDays.value(for: $0) }
        return all.max() ?? 7
    }

    static func interval(_ s: PlantSnapshot, season: Season, dormant: Bool = false) -> Double {
        var base = baseInterval(s.profile, season: season)
        // En dormance, on garde au moins le rythme d'hiver (le plus espacé en général).
        if dormant { base = max(base, baseInterval(s.profile, season: .winter)) }
        return max(1, base * s.learnedFactor * s.manualFactor)
    }

    // MARK: Statut

    static func status(_ s: PlantSnapshot, now: Date = Date(), calendar: Calendar = .current, southernHemisphere: Bool = false) -> CareStatus {
        let season = Season.of(now, southernHemisphere: southernHemisphere, calendar: calendar)
        let dormantUntil = dormancyEnd(s.profile.dormancy?.months ?? [], now: now, calendar: calendar)
        let interval = interval(s, season: season, dormant: dormantUntil != nil)
        let today = calendar.startOfDay(for: now)

        var due: Date
        var state: WateringState
        if let last = s.lastWateredAt {
            due = calendar.date(byAdding: .day, value: Int(interval.rounded()), to: calendar.startOfDay(for: last)) ?? today
            if let snooze = s.snoozedUntil, calendar.startOfDay(for: snooze) > due {
                due = calendar.startOfDay(for: snooze)
            }
            let until = days(from: today, to: due, calendar)
            if until <= 0 {
                let since = Double(days(from: last, to: now, calendar))
                let snoozed = s.snoozedUntil.map { calendar.startOfDay(for: $0) >= calendar.startOfDay(for: last) } ?? false
                state = (since >= interval * urgentRatio && !snoozed) ? .water : .check
            } else {
                state = until <= 2 ? .soon(days: until) : .later(days: until)
            }
        } else if let snooze = s.snoozedUntil, calendar.startOfDay(for: snooze) > today {
            due = calendar.startOfDay(for: snooze)
            let until = days(from: today, to: due, calendar)
            state = until <= 2 ? .soon(days: until) : .later(days: until)
        } else {
            due = today
            state = .check
        }

        var tasks: [TaskItem] = []
        if state.isDue { tasks.append(TaskItem(kind: .watering, urgent: state == .water)) }
        for (kind, period) in periodicCare(s.profile, season: season, month: calendar.component(.month, from: now)) {
            let last = s.lastDone[kind] ?? s.createdAt
            if days(from: last, to: now, calendar) >= Int(period.rounded()) {
                tasks.append(TaskItem(kind: kind))
            }
        }

        let mood: Mood
        if state.isDue {
            mood = .thirsty
        } else if let last = s.lastWateredAt, calendar.isDate(last, inSameDayAs: now) {
            mood = .happy
        } else if dormantUntil != nil {
            mood = .sleeping
        } else {
            mood = .ok
        }

        return CareStatus(season: season, interval: interval, watering: state, wateringDue: due, tasks: tasks, dormantUntil: dormantUntil, mood: mood)
    }

    /// Soins courants (hors arrosage) applicables aujourd'hui, avec leur période en jours.
    static func periodicCare(_ p: CareProfile, season: Season, month: Int) -> [(CareKind, Double)] {
        var out: [(CareKind, Double)] = []
        if let d = p.mistingDays?.value(for: season) { out.append((.misting, d)) }
        if let d = p.rotationDays, d > 0 { out.append((.rotation, d)) }
        if let f = p.fertilizing, f.months.contains(month), f.intervalDays > 0 { out.append((.fertilizing, f.intervalDays)) }
        return out
    }

    // MARK: Prochaines échéances

    static func upcoming(_ s: PlantSnapshot, now: Date = Date(), calendar: Calendar = .current) -> [UpcomingItem] {
        let st = status(s, now: now, calendar: calendar)
        var items: [UpcomingItem] = []
        if !st.watering.isDue { items.append(UpcomingItem(kind: .watering, date: st.wateringDue)) }
        for (kind, period) in periodicCare(s.profile, season: st.season, month: calendar.component(.month, from: now)) {
            let last = s.lastDone[kind] ?? s.createdAt
            if let next = calendar.date(byAdding: .day, value: Int(period.rounded()), to: calendar.startOfDay(for: last)),
               next > calendar.startOfDay(for: now) {
                items.append(UpcomingItem(kind: kind, date: next))
            }
        }
        return items.sorted { $0.date < $1.date }
    }

    // MARK: Apprentissage

    /// Après « Arrosé » : si on n'a pas eu besoin de repousser, on resserre très légèrement
    /// l'intervalle (l'app explore doucement un rythme plus soutenu jusqu'au prochain « encore humide »).
    static func factorAfterWatering(_ factor: Double, snoozedThisCycle: Bool) -> Double {
        snoozedThisCycle ? factor : clamp(factor * 0.97)
    }

    /// Après « Encore humide » : on allonge l'intervalle et on repasse dans quelques jours.
    static func afterStillWet(factor: Double, interval: Double) -> (factor: Double, snoozeDays: Int) {
        let days = min(10, max(1, Int((interval * 0.25).rounded())))
        return (clamp(factor * 1.12), days)
    }

    static func clamp(_ f: Double) -> Double { min(maxFactor, max(minFactor, f)) }

    // MARK: Dormance

    /// Si on est dans un mois de dormance, renvoie le 1er jour du premier mois « réveillé ».
    static func dormancyEnd(_ months: [Int], now: Date, calendar: Calendar = .current) -> Date? {
        let set = Set(months.filter { (1...12).contains($0) })
        guard !set.isEmpty, set.count < 12 else { return nil }
        let month = calendar.component(.month, from: now)
        guard set.contains(month) else { return nil }
        var m = month
        var year = calendar.component(.year, from: now)
        repeat {
            m += 1
            if m > 12 { m = 1; year += 1 }
        } while set.contains(m)
        return calendar.date(from: DateComponents(year: year, month: m, day: 1))
    }

    // MARK: À l'horizon (long terme, jamais de notification)

    static func horizon(_ s: PlantSnapshot, now: Date = Date(), calendar: Calendar = .current) -> [HorizonHint] {
        var hints: [HorizonHint] = []
        let rep = s.profile.repotting
        let when = Fmt.monthsPhrase(rep.bestMonths)
        if let last = s.lastDone[.repotting] {
            let years = Double(days(from: last, to: now, calendar)) / 365
            let soon = years >= rep.everyYears * 0.8
            let detail = soon
                ? "À prévoir \(when)."
                : "Prochain dans ~\(Fmt.years(max(0.5, rep.everyYears - years)))."
            hints.append(HorizonHint(kind: .repotting, title: "Rempotée \(Fmt.ago(last, now: now))", detail: detail + " " + rep.advice, soon: soon))
        } else {
            hints.append(HorizonHint(kind: .repotting, title: "Rempotage : jamais noté", detail: "Tous les ~\(Fmt.years(rep.everyYears)), idéalement \(when).", soon: false))
        }
        if let pruning = s.profile.pruning, !pruning.isEmpty {
            let title = s.lastDone[.pruning].map { "Taillée \(Fmt.ago($0, now: now))" } ?? "Taille"
            hints.append(HorizonHint(kind: .pruning, title: title, detail: pruning, soon: false))
        }
        return hints
    }

    // MARK: Utilitaires

    static func days(from a: Date, to b: Date, _ calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }
}

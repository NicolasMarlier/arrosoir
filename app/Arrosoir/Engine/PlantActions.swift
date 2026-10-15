import Foundation
import SwiftData

/// De quoi annuler la dernière action sur une plante.
nonisolated struct UndoSnapshot {
    let lastWateredAt: Date?
    let snoozedUntil: Date?
    let learnedFactor: Double
    let snoozedThisCycle: Bool
    let event: CareEvent?
}

extension Plant {
    private func snapshotForUndo(_ event: CareEvent?) -> UndoSnapshot {
        UndoSnapshot(lastWateredAt: lastWateredAt, snoozedUntil: snoozedUntil, learnedFactor: learnedFactor, snoozedThisCycle: snoozedThisCycle, event: event)
    }

    private func addEvent(_ kind: CareKind, _ date: Date, _ ctx: ModelContext) -> CareEvent {
        let e = CareEvent(kind: kind, date: date)
        ctx.insert(e)
        e.plant = self
        return e
    }

    @discardableResult
    func water(in ctx: ModelContext, now: Date = Date()) -> UndoSnapshot {
        let e = addEvent(.watering, now, ctx)
        let undo = snapshotForUndo(e)
        learnedFactor = CareEngine.factorAfterWatering(learnedFactor, snoozedThisCycle: snoozedThisCycle)
        lastWateredAt = now
        snoozedUntil = nil
        snoozedThisCycle = false
        try? ctx.save()
        return undo
    }

    @discardableResult
    func markStillWet(in ctx: ModelContext, now: Date = Date()) -> UndoSnapshot {
        let e = addEvent(.stillWet, now, ctx)
        let undo = snapshotForUndo(e)
        let interval = snapshot().map { CareEngine.status($0, now: now).interval } ?? 7
        let r = CareEngine.afterStillWet(factor: learnedFactor, interval: interval)
        learnedFactor = r.factor
        snoozedUntil = Calendar.current.date(byAdding: .day, value: r.snoozeDays, to: Calendar.current.startOfDay(for: now))
        snoozedThisCycle = true
        try? ctx.save()
        return undo
    }

    @discardableResult
    func markDone(_ kind: CareKind, in ctx: ModelContext, now: Date = Date()) -> UndoSnapshot {
        if kind == .watering { return water(in: ctx, now: now) }
        let e = addEvent(kind, now, ctx)
        try? ctx.save()
        return snapshotForUndo(e)
    }

    /// Soin noté a posteriori depuis la fiche (n'influence pas l'apprentissage).
    func log(_ kind: CareKind, date: Date, in ctx: ModelContext) {
        _ = addEvent(kind, date, ctx)
        if kind == .watering, date > (lastWateredAt ?? .distantPast) {
            lastWateredAt = date
            snoozedUntil = nil
            snoozedThisCycle = false
        }
        try? ctx.save()
    }

    func restore(_ s: UndoSnapshot, in ctx: ModelContext) {
        lastWateredAt = s.lastWateredAt
        snoozedUntil = s.snoozedUntil
        learnedFactor = s.learnedFactor
        snoozedThisCycle = s.snoozedThisCycle
        if let e = s.event { ctx.delete(e) }
        try? ctx.save()
    }

    func archive(_ reason: ArchiveReason, epitaph: String, in ctx: ModelContext, now: Date = Date()) {
        archivedAt = now
        archiveReasonRaw = reason.rawValue
        self.epitaph = epitaph
        try? ctx.save()
    }

    /// Prochain index de pot : le moins utilisé parmi les plantes actives.
    static func nextPotIndex(existing: [Plant]) -> Int {
        var counts = Array(repeating: 0, count: PotStyle.all.count)
        for p in existing where !p.isArchived { counts[((p.potStyleIndex % counts.count) + counts.count) % counts.count] += 1 }
        let minCount = counts.min() ?? 0
        return counts.firstIndex(of: minCount) ?? 0
    }
}

extension Plant {
    /// Résumé de la plante et de son historique, envoyé à Claude pour un diagnostic.
    func diagnosisContext(now: Date = Date()) -> String {
        var lines: [String] = ["Plante : \(commonName) (\(scientificName))."]
        if let room { lines.append("Pièce : \(room).") }
        if let light { lines.append("Exposition : \(light.prompt).") }
        lines.append("Saison actuelle : \(Season.of(now).label.lowercased()). Adoptée dans l'app \(Fmt.ago(createdAt, now: now)).")
        if let p = profile, let s = snapshot() {
            let st = CareEngine.status(s, now: now)
            lines.append("Rythme d'arrosage actuel : environ tous les \(Int(st.interval.rounded())) jours. Méthode conseillée : \(p.watering.method)")
            if st.dormantUntil != nil { lines.append("Elle est censée être en repos végétatif en ce moment.") }
        }
        lines.append("Dernier arrosage : \(lastWateredAt.map { Fmt.ago($0, now: now) } ?? "inconnu").")
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
        let recent = careEvents.filter { $0.date >= cutoff }
        let waterings = recent.filter { $0.kind == .watering }.count
        let wet = recent.filter { $0.kind == .stillWet }.count
        lines.append("Sur les 60 derniers jours : \(waterings) arrosage(s), \(wet) fois « terre encore humide » au moment de vérifier.")
        if let r = lastDone(.repotting) { lines.append("Dernier rempotage : \(Fmt.ago(r, now: now)).") }
        if let f = lastDone(.fertilizing) { lines.append("Dernier engrais : \(Fmt.ago(f, now: now)).") }
        if let last = diagnosisList.max(by: { $0.date < $1.date }), let r = last.result {
            lines.append("Diagnostic précédent (\(Fmt.ago(last.date, now: now))) : \(r.title). \(r.summary)")
        }
        return lines.joined(separator: "\n")
    }
}

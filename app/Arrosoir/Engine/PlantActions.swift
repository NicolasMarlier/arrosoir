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

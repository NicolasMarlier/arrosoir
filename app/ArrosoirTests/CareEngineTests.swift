import Foundation
import Testing
@testable import Arrosoir

@MainActor
struct CareEngineTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func snap(_ p: CareProfile, lastDaysAgo: Int?, now: Date, factor: Double = 1, snooze: Date? = nil) -> PlantSnapshot {
        PlantSnapshot(profile: p, createdAt: cal.date(byAdding: .day, value: -60, to: now)!,
                      lastWateredAt: lastDaysAgo.map { cal.date(byAdding: .day, value: -$0, to: now)! },
                      snoozedUntil: snooze, learnedFactor: factor, manualFactor: 1,
                      lastDone: [.misting: now, .rotation: now, .fertilizing: now])
    }

    @Test func seasons() {
        #expect(Season.of(date(2026, 1, 10), calendar: cal) == .winter)
        #expect(Season.of(date(2026, 4, 10), calendar: cal) == .spring)
        #expect(Season.of(date(2026, 7, 10), calendar: cal) == .summer)
        #expect(Season.of(date(2026, 10, 15), calendar: cal) == .autumn)
        #expect(Season.of(date(2026, 1, 10), southernHemisphere: true, calendar: cal) == .summer)
    }

    @Test func wateringStates() {
        let now = date(2026, 10, 15) // automne : monstera tous les 10 j
        let p = DemoData.monstera
        #expect(CareEngine.status(snap(p, lastDaysAgo: 2, now: now), now: now, calendar: cal).watering == .later(days: 8))
        #expect(CareEngine.status(snap(p, lastDaysAgo: 9, now: now), now: now, calendar: cal).watering == .soon(days: 1))
        #expect(CareEngine.status(snap(p, lastDaysAgo: 10, now: now), now: now, calendar: cal).watering == .check)
        #expect(CareEngine.status(snap(p, lastDaysAgo: 13, now: now), now: now, calendar: cal).watering == .water)
        #expect(CareEngine.status(snap(p, lastDaysAgo: nil, now: now), now: now, calendar: cal).watering == .check)
    }

    @Test func learnedFactorStretchesInterval() {
        let now = date(2026, 10, 15)
        let st = CareEngine.status(snap(DemoData.monstera, lastDaysAgo: 10, now: now, factor: 1.5), now: now, calendar: cal)
        #expect(st.interval == 15)
        #expect(st.watering == .later(days: 5))
    }

    @Test func snoozePostponesAndNeverUrgent() {
        let now = date(2026, 10, 15)
        let snooze = cal.date(byAdding: .day, value: -1, to: now)!
        let st = CareEngine.status(snap(DemoData.monstera, lastDaysAgo: 20, now: now, snooze: snooze), now: now, calendar: cal)
        #expect(st.watering == .check)
        let later = CareEngine.status(snap(DemoData.monstera, lastDaysAgo: 20, now: now, snooze: cal.date(byAdding: .day, value: 3, to: now)!), now: now, calendar: cal)
        #expect(later.watering == .later(days: 3))
    }

    @Test func stillWetLearning() {
        let r = CareEngine.afterStillWet(factor: 1, interval: 10)
        #expect(r.factor > 1)
        #expect(r.snoozeDays == 3)
        #expect(CareEngine.afterStillWet(factor: 2.4, interval: 60).factor == CareEngine.maxFactor)
        #expect(CareEngine.afterStillWet(factor: 1, interval: 60).snoozeDays == 10)
        #expect(CareEngine.factorAfterWatering(1, snoozedThisCycle: true) == 1)
        #expect(CareEngine.factorAfterWatering(1, snoozedThisCycle: false) < 1)
        #expect(CareEngine.factorAfterWatering(0.5, snoozedThisCycle: false) == CareEngine.minFactor)
    }

    @Test func dormancy() {
        let oct = date(2026, 10, 15)
        let end = CareEngine.dormancyEnd([10, 11, 12, 1, 2, 3], now: oct, calendar: cal)
        #expect(end == cal.date(from: DateComponents(year: 2027, month: 4, day: 1)))
        #expect(CareEngine.dormancyEnd([12, 1, 2], now: oct, calendar: cal) == nil)
        let st = CareEngine.status(snap(DemoData.rose, lastDaysAgo: 5, now: oct), now: oct, calendar: cal)
        #expect(st.mood == .sleeping)
    }

    @Test func periodicTasks() {
        let now = date(2026, 10, 15)
        var s = snap(DemoData.calathea, lastDaysAgo: 1, now: now)
        s.lastDone[.misting] = cal.date(byAdding: .day, value: -3, to: now)
        let st = CareEngine.status(s, now: now, calendar: cal)
        #expect(st.tasks.map(\.kind) == [.misting])
        // Engrais hors saison : jamais proposé.
        s.lastDone[.fertilizing] = cal.date(byAdding: .day, value: -100, to: now)
        #expect(!CareEngine.status(s, now: now, calendar: cal).tasks.contains { $0.kind == .fertilizing })
    }

    @Test func happyMoodRightAfterWatering() {
        let now = date(2026, 10, 15, 18)
        let st = CareEngine.status(snap(DemoData.monstera, lastDaysAgo: 0, now: now), now: now, calendar: cal)
        #expect(st.mood == .happy)
    }

    @Test func horizonRepotting() {
        let now = date(2026, 10, 15)
        var s = snap(DemoData.rose, lastDaysAgo: 5, now: now)
        s.lastDone[.repotting] = cal.date(byAdding: .month, value: -27, to: now)
        let h = CareEngine.horizon(s, now: now, calendar: cal)
        #expect(h.first?.kind == .repotting)
        #expect(h.first?.soon == true)
    }

    @Test func profileJSONDecodesFromSnakeCase() throws {
        let json = """
        {"common_name":"Pilea","scientific_name":"Pilea peperomioides","archetype":"tree","intro":"Salut !","light":"Vive",
         "watering":{"interval_days":{"spring":7,"summer":5,"autumn":8,"winter":12},"quantity":"Moyenne","method":"Par le dessus","water_type":"","check_hint":"Terre sèche"},
         "dormancy":{"months":[],"advice":""},"misting_days":{"spring":0,"summer":0,"autumn":0,"winter":0},"rotation_days":7,
         "fertilizing":{"months":[4,5,6],"interval_days":30,"advice":"x"},"repotting":{"every_years":2,"best_months":[3,4],"advice":"x"},"pruning":""}
        """
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let p = try d.decode(CareProfile.self, from: Data(json.utf8))
        #expect(p.archetypeValue == .tree)
        #expect(p.watering.intervalDays.value(for: .winter) == 12)
        #expect(p.mistingDays?.value(for: .summer) == nil)
    }
}

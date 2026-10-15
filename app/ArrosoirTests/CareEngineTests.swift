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

@MainActor
struct LenientJSONTests {
    @Test func messyProfileStillDecodes() throws {
        let json = """
        {"care_profile": {"commonName":"Rose du désert","scientific_name":"Adenium obesum","archetype":"Caudex",
         "watering":"{\\"interval_days\\":{\\"spring\\":\\"10\\",\\"summer\\":7,\\"winter\\":\\"30 jours\\"},\\"quantity\\":\\"Un verre\\"}",
         "dormancy":{"months":"10, 11, 12, 1, 2","advice":"Laisse-la dormir"},
         "fertilizing":{"months":["5","6"],"interval_days":"21"},"rotation_days":"0","pruning":""}}
        """
        let p = try #require(CareProfile.lenient(LenientJSON(data: Data(json.utf8)), fallbackName: "X", fallbackScientific: "Y"))
        #expect(p.commonName == "Rose du désert")
        #expect(p.archetypeValue == .caudex)
        #expect(p.watering.intervalDays.value(for: .winter) == 30)
        #expect(p.watering.intervalDays.value(for: .autumn) != nil)
        #expect(p.dormancy?.months == [10, 11, 12, 1, 2])
        #expect(p.fertilizing?.intervalDays == 21)
        #expect(p.rotationDays == nil)
        #expect(p.watering.quantity == "Un verre")
    }

    @Test func flatSchemaDecodes() throws {
        let json = """
        {"common_name":"Arbre ombrelle","scientific_name":"Schefflera arboricola","archetype":"tree","intro":"Salut !",
         "light":"Vive, sans soleil direct brûlant","water_spring_days":8,"water_summer_days":"6","water_autumn_days":10,"water_winter_days":14,
         "water_quantity":"Généreuse","water_method":"Par le dessus, puis vide la soucoupe après 15 min","water_type":"","water_check_hint":"2 cm secs",
         "dormancy_months":[],"dormancy_advice":"","mist_spring_days":0,"mist_summer_days":0,"mist_autumn_days":0,"mist_winter_days":0,
         "rotation_days":14,"fertilizing_months":[4,5,6,7,8,9],"fertilizing_interval_days":15,"fertilizing_advice":"Demi-dose",
         "repotting_every_years":2,"repotting_best_months":[3,4],"repotting_advice":"Pot un peu plus grand","pruning":""}
        """
        let p = try #require(CareProfile.lenient(LenientJSON(data: Data(json.utf8)), fallbackName: "X", fallbackScientific: "Y"))
        #expect(p.archetypeValue == .tree)
        #expect(p.watering.intervalDays.value(for: .summer) == 6)
        #expect(p.watering.method.hasPrefix("Par le dessus"))
        #expect(p.watering.waterType == nil)
        #expect(p.mistingDays == nil)
        #expect(p.dormancy == nil)
        #expect(p.rotationDays == 14)
        #expect(p.fertilizing?.intervalDays == 15)
        #expect(p.pruning == nil)
    }

    @Test func halfFlattenedDecodes() throws {
        // Ce qu'a renvoyé le modèle sur l'iPhone : champs d'arrosage remontés au 1er niveau.
        let json = """
        {"light":"Vive","quantity":"Généreuse, jusqu'à ce que l'eau s'écoule","method":"Arrose par le dessus",
         "interval_days":{"spring":7,"summer":5,"autumn":9,"winter":14},"common_name":"Arbre ombrelle","archetype":"tree"}
        """
        let p = try #require(CareProfile.lenient(LenientJSON(data: Data(json.utf8)), fallbackName: "X", fallbackScientific: "Y"))
        #expect(p.watering.quantity.hasPrefix("Généreuse"))
        #expect(p.watering.intervalDays.value(for: .winter) == 14)
    }

    @Test func missingWateringFails() {
        #expect(CareProfile.lenient(LenientJSON(data: Data(#"{"intro":"hey"}"#.utf8)), fallbackName: "X", fallbackScientific: "Y") == nil)
    }
}

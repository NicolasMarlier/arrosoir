import Foundation
import SwiftData

@Model
final class Plant {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var commonName: String = ""
    var scientificName: String = ""
    var archetypeRaw: String = PlantArchetype.upright.rawValue
    var room: String?
    var lightRaw: String?
    @Attribute(.externalStorage) var photo: Data?
    var potStyleIndex: Int = 0
    var profileData: Data = Data()

    var lastWateredAt: Date?
    var snoozedUntil: Date?
    /// Facteur appris (boutons « Arrosé » / « Encore humide »).
    var learnedFactor: Double = 1
    /// Facteur réglé à la main (réglette « Son rythme »).
    var manualFactor: Double = 1
    /// Vrai si l'utilisateur a déjà répondu « Encore humide » depuis le dernier arrosage.
    var snoozedThisCycle: Bool = false

    var archivedAt: Date?
    var archiveReasonRaw: String?
    var epitaph: String?

    @Relationship(deleteRule: .cascade, inverse: \CareEvent.plant)
    var events: [CareEvent] = []

    @Relationship(deleteRule: .cascade, inverse: \Diagnosis.plant)
    var diagnoses: [Diagnosis] = []

    init(profile: CareProfile, photo: Data?, room: String?, light: LightLevel?, potStyleIndex: Int, lastWateredAt: Date?, now: Date = Date()) {
        self.id = UUID()
        self.createdAt = now
        self.commonName = profile.commonName
        self.scientificName = profile.scientificName
        self.archetypeRaw = profile.archetype
        self.room = room
        self.lightRaw = light?.rawValue
        self.photo = photo
        self.potStyleIndex = potStyleIndex
        self.profileData = (try? JSONEncoder().encode(profile)) ?? Data()
        self.lastWateredAt = lastWateredAt
    }

    var profile: CareProfile? {
        get { try? JSONDecoder().decode(CareProfile.self, from: profileData) }
        set {
            guard let newValue else { return }
            profileData = (try? JSONEncoder().encode(newValue)) ?? profileData
            commonName = newValue.commonName
            scientificName = newValue.scientificName
            archetypeRaw = newValue.archetype
        }
    }

    var archetype: PlantArchetype { PlantArchetype(rawValue: archetypeRaw) ?? .upright }
    var potStyle: PotStyle { .at(potStyleIndex) }
    var light: LightLevel? {
        get { lightRaw.flatMap(LightLevel.init(rawValue:)) }
        set { lightRaw = newValue?.rawValue }
    }
    var archiveReason: ArchiveReason? { archiveReasonRaw.flatMap(ArchiveReason.init(rawValue:)) }
    var isArchived: Bool { archivedAt != nil }

    func lastDone(_ kind: CareKind) -> Date? {
        events.filter { $0.kind == kind }.map(\.date).max()
    }

    func snapshot() -> PlantSnapshot? {
        guard let profile else { return nil }
        var last: [CareKind: Date] = [:]
        for e in events {
            if let d = last[e.kind], d >= e.date { continue }
            last[e.kind] = e.date
        }
        return PlantSnapshot(
            profile: profile,
            createdAt: createdAt,
            lastWateredAt: lastWateredAt,
            snoozedUntil: snoozedUntil,
            learnedFactor: learnedFactor,
            manualFactor: manualFactor,
            lastDone: last
        )
    }
}

@Model
final class CareEvent {
    var id: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = CareKind.watering.rawValue
    var plant: Plant?

    init(kind: CareKind, date: Date = Date()) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.date = date
    }

    var kind: CareKind { CareKind(rawValue: kindRaw) ?? .watering }
}

/// Un diagnostic fait par Claude (photo + description).
@Model
final class Diagnosis {
    var id: UUID = UUID()
    var date: Date = Date()
    var note: String = ""
    @Attribute(.externalStorage) var photo: Data?
    var resultData: Data = Data()
    var plant: Plant?

    init(note: String, photo: Data?, result: DiagnosisResult, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.note = note
        self.photo = photo
        self.resultData = (try? JSONEncoder().encode(result)) ?? Data()
    }

    var result: DiagnosisResult? { try? JSONDecoder().decode(DiagnosisResult.self, from: resultData) }
}

nonisolated struct DiagnosisResult: Codable, Sendable, Equatable {
    enum Severity: String, Codable, Sendable { case ok, watch, urgent }
    enum WateringAdjustment: String, Codable, Sendable { case none, more, less }

    var title: String
    var severity: Severity
    var plantSays: String
    var summary: String
    var causes: [String]
    var actions: [String]
    var wateringAdjustment: WateringAdjustment
    var followUpDays: Int?
}

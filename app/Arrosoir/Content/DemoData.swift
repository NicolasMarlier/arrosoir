import Foundation
import SwiftData

/// Fiches d'exemple (pour tester sans clé API, et pour les tests).
enum DemoData {
    static let monstera = CareProfile(
        commonName: "Monstera", scientificName: "Monstera deliciosa", archetype: "monstera",
        intro: "Salut ! Moi c'est Monstera. Je suis plutôt facile à vivre : arrose-moi quand le dessus de la terre est sec, et on s'entendra bien 🤝",
        light: "Vive, sans soleil direct",
        watering: .init(intervalDays: .init(spring: 8, summer: 6, autumn: 10, winter: 14), quantity: "Généreuse, jusqu'à ce que ça coule", method: "Par le dessus, généreusement. Vide la soucoupe.", waterType: nil, checkHint: "Les 3 premiers cm de terre sont secs"),
        dormancy: nil, mistingDays: nil, rotationDays: 21,
        fertilizing: .init(months: [4, 5, 6, 7, 8, 9], intervalDays: 21, advice: "Engrais plantes vertes dilué"),
        repotting: .init(everyYears: 2, bestMonths: [3, 4, 5], advice: "Un pot à peine plus grand."),
        pruning: "Retire les feuilles jaunies à la base."
    )

    static let dionee = CareProfile(
        commonName: "Dionée", scientificName: "Dionaea muscipula", archetype: "carnivorous",
        intro: "Bonjour ! Je ne mords que les mouches, promis. Garde mes pieds humides avec de l'eau de pluie, jamais celle du robinet 🪰",
        light: "Plein soleil",
        watering: .init(intervalDays: .init(spring: 3, summer: 2, autumn: 4, winter: 7), quantity: "1 cm d'eau dans la soucoupe", method: "Par la soucoupe, garder 1 cm d'eau.", waterType: "déminéralisée ou de pluie", checkHint: "La soucoupe est vide"),
        dormancy: .init(months: [12, 1, 2], advice: "Au frais, terre juste humide. Ne pas nourrir."),
        mistingDays: nil, rotationDays: nil, fertilizing: nil,
        repotting: .init(everyYears: 2, bestMonths: [3], advice: "Dans de la tourbe blonde et du sable."),
        pruning: "Coupe les pièges noircis."
    )

    static let calathea = CareProfile(
        commonName: "Calathea", scientificName: "Calathea orbifolia", archetype: "upright",
        intro: "Coucou ! Je suis un peu diva : j'aime l'humidité, l'ombre douce et l'eau peu calcaire. En échange, je fais de belles feuilles 💅",
        light: "Lumière tamisée",
        watering: .init(intervalDays: .init(spring: 6, summer: 4, autumn: 7, winter: 9), quantity: "Modérée, terre toujours un peu fraîche", method: "Par le dessus, à l'eau tempérée.", waterType: "peu calcaire", checkHint: "Le premier cm de terre est sec"),
        dormancy: nil, mistingDays: .init(spring: 3, summer: 2, autumn: 3, winter: 3), rotationDays: 14,
        fertilizing: .init(months: [4, 5, 6, 7, 8], intervalDays: 30, advice: "Demi-dose"),
        repotting: .init(everyYears: 2, bestMonths: [4, 5], advice: "Terreau léger et drainant."),
        pruning: nil
    )

    static let pothos = CareProfile(
        commonName: "Pothos", scientificName: "Epipremnum aureum", archetype: "trailing",
        intro: "Yo ! Je suis increvable, ou presque. Laisse sécher la terre entre deux verres et je pousserai partout 🌿",
        light: "Lumineux à mi-ombre",
        watering: .init(intervalDays: .init(spring: 8, summer: 6, autumn: 10, winter: 14), quantity: "Moyenne", method: "Par le dessus. Vide la soucoupe.", waterType: nil, checkHint: "La moitié du pot est sèche"),
        dormancy: nil, mistingDays: nil, rotationDays: 30,
        fertilizing: .init(months: [4, 5, 6, 7, 8, 9], intervalDays: 30, advice: "Engrais plantes vertes"),
        repotting: .init(everyYears: 2, bestMonths: [3, 4], advice: "Quand les racines sortent du pot."),
        pruning: "Pince les tiges trop longues pour l'étoffer."
    )

    static let cactus = CareProfile(
        commonName: "Cactus", scientificName: "Cereus peruvianus", archetype: "cactus",
        intro: "Salut. Moins tu t'occupes de moi, mieux je me porte. Et l'hiver, je dors : pas d'eau, merci 🌵",
        light: "Plein soleil",
        watering: .init(intervalDays: .init(spring: 14, summer: 10, autumn: 21, winter: 45), quantity: "Un fond d'eau", method: "Par le dessus, sur terre totalement sèche.", waterType: nil, checkHint: "La terre est sèche jusqu'au fond"),
        dormancy: .init(months: [11, 12, 1, 2], advice: "Presque pas d'eau, au frais et au clair."),
        mistingDays: nil, rotationDays: 30,
        fertilizing: .init(months: [5, 6, 7, 8], intervalDays: 30, advice: "Engrais cactus"),
        repotting: .init(everyYears: 3, bestMonths: [3, 4], advice: "Avec des gants, terreau cactus."),
        pruning: nil
    )

    static let rose = CareProfile(
        commonName: "Rose du désert", scientificName: "Adenium obesum", archetype: "caudex",
        intro: "Bonjour ! Je stocke l'eau dans mon gros pied, alors pas de noyade s'il te plaît. Du soleil, et je fleuris 🌸",
        light: "Plein soleil",
        watering: .init(intervalDays: .init(spring: 10, summer: 7, autumn: 14, winter: 30), quantity: "Un verre, pas plus", method: "Par le dessus, sur une terre complètement sèche. Jamais d'eau dans la soucoupe.", waterType: nil, checkHint: "Les tiges se plissent légèrement"),
        dormancy: .init(months: [10, 11, 12, 1, 2, 3], advice: "Un petit verre par mois au maximum, et seulement si les tiges se plissent. Sinon, laisse-la dormir."),
        mistingDays: nil, rotationDays: 21,
        fertilizing: .init(months: [5, 6, 7, 8], intervalDays: 21, advice: "Engrais riche en potasse"),
        repotting: .init(everyYears: 2, bestMonths: [4, 5], advice: "Quand elle se réveille."),
        pruning: "En fin d'hiver si elle s'étale trop."
    )

    static let all: [(CareProfile, String, LightLevel, Int, Int?)] = [
        // profil, pièce, lumière, pot, arrosée il y a N jours
        (monstera, "Salon", .bright, 0, 13),
        (dionee, "Cuisine", .full, 1, 4),
        (calathea, "Chambre", .low, 2, 3),
        (pothos, "Salon", .bright, 3, 4),
        (cactus, "Salon", .full, 4, 20),
        (rose, "Bureau", .full, 5, 18),
    ]

    static func load(into context: ModelContext, now: Date = Date()) {
        let cal = Calendar.current
        for (profile, room, light, pot, days) in all {
            let last = days.flatMap { cal.date(byAdding: .day, value: -$0, to: now) }
            let plant = Plant(profile: profile, photo: nil, room: room, light: light, potStyleIndex: pot, lastWateredAt: last,
                              now: cal.date(byAdding: .day, value: -40, to: now) ?? now)
            context.insert(plant)
            let rep = CareEvent(kind: .repotting, date: cal.date(byAdding: .month, value: -27, to: now) ?? now)
            rep.plant = plant
            context.insert(rep)
            let rot = CareEvent(kind: .rotation, date: cal.date(byAdding: .day, value: -Int.random(in: 2...10), to: now) ?? now)
            rot.plant = plant
            context.insert(rot)
            if profile.archetype == "upright" {
                let mist = CareEvent(kind: .misting, date: cal.date(byAdding: .day, value: -4, to: now) ?? now)
                mist.plant = plant
                context.insert(mist)
            }
        }
        try? context.save()
    }
}

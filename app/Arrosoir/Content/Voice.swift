import Foundation

/// Les petites phrases des plantes. Choix déterministe (stable dans la journée).
enum Voice {
    static let thirsty = ["J'ai soif ! 🥵", "Un verre, vite !", "Je sèche sur place…", "Psst… de l'eau ?", "C'est le désert ici 🏜️"]
    static let check = ["Tu me touches la terre ?", "On vérifie ?", "Ça va, mais vérifie quand même 👀"]
    static let happy = ["Ahhh, merci ! 😌", "Ça fait du bien !", "Rafraîchie ✨", "Merci, coloc !"]
    static let stillWet = ["Ok, je repasse plus tard 👌", "Noté, je bois moins que prévu.", "Pas soif, merci !"]
    static let allGood = ["Va vivre ta vie ☀️", "Rien à signaler, chef.", "Tout le monde est content.", "Repos pour toi aussi."]

    static func pick(_ list: [String], seed: UUID, date: Date = Date()) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        var h = 0
        for b in seed.uuidString.utf8 { h = (h &* 31 &+ Int(b)) & 0x7FFFFFFF }
        return list[(h &+ day) % list.count]
    }

    static func epitaph(reason: ArchiveReason, name: String) -> String {
        switch reason {
        case .died: ["Elle a fait de son mieux.", "Partie trop tôt, trop au soleil (ou pas assez).", "Repose en terreau.", "On ne l'oubliera pas (enfin, on va essayer)."].randomElement()!
        case .given: ["Partie vivre sa meilleure vie ailleurs.", "Adoptée. Elle est heureuse là-bas.", "Nouvelle coloc, même sourire."].randomElement()!
        }
    }
}

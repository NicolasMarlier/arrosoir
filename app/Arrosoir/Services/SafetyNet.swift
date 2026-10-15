import Foundation
import UserNotifications

/// Filet de sécurité optionnel : une seule notification si une plante a plus de 3 jours de retard.
enum SafetyNet {
    static let overdueDays = 3
    static let hour = 9
    private static let id = "safety-net"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func reschedule(plants: [Plant], enabled: Bool, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard enabled else { return }
        let cal = Calendar.current

        var best: (Date, Plant)?
        for plant in plants where !plant.isArchived {
            guard let snap = plant.snapshot() else { continue }
            let st = CareEngine.status(snap, now: now)
            guard let alert = cal.date(byAdding: .day, value: overdueDays, to: st.wateringDue) else { continue }
            if best == nil || alert < best!.0 { best = (alert, plant) }
        }
        guard let (date, plant) = best else { return }

        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        if let fire = cal.date(from: comps), fire <= now {
            // Déjà en retard : on prévient demain matin.
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
            comps.hour = hour
        }
        let content = UNMutableNotificationContent()
        content.title = "\(plant.commonName) t'attend 🥺"
        content.body = "Ça fait un moment… Un petit tour dans Arrosoir ?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        center.add(request)
    }
}

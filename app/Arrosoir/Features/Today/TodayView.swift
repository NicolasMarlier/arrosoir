import SwiftUI
import SwiftData

struct DoneEntry {
    var undo: UndoSnapshot
    var message: String
    var stillWet: Bool
}

struct TodayView: View {
    var onAdd: () -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<Plant> { $0.archivedAt == nil }, sort: \Plant.createdAt) private var plants: [Plant]
    @State private var now = Date()
    @State private var done: [UUID: DoneEntry] = [:]

    private struct Row: Identifiable {
        let plant: Plant
        let status: CareStatus
        var id: UUID { plant.id }
    }

    private var rows: [Row] {
        plants.compactMap { p -> Row? in
            guard let s = p.snapshot() else { return nil }
            let st = CareEngine.status(s, now: now)
            guard st.hasTasks || done[p.id] != nil else { return nil }
            return Row(plant: p, status: st)
        }
        .sorted { a, b in
            let da = done[a.plant.id] != nil, db = done[b.plant.id] != nil
            if da != db { return !da }
            return a.status.urgencyScore > b.status.urgencyScore
        }
    }

    var body: some View {
        let rows = rows
        let pending = rows.filter { done[$0.plant.id] == nil }
        let careCount = pending.reduce(0) { $0 + $1.status.tasks.count }
        let wateringCount = pending.filter { $0.status.wateringTask != nil }.count
        let stickerPlant = pending.first { $0.status.wateringTask != nil }?.plant.id

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(plantCount: pending.count, careCount: careCount, showAll: wateringCount >= 2)

                if plants.isEmpty {
                    EmptyCoLocView(onAdd: onAdd)
                } else if rows.isEmpty {
                    AllGoodView(plants: plants, now: now)
                } else {
                    VStack(spacing: 12) {
                        ForEach(rows) { row in
                            TaskCard(
                                plant: row.plant, status: row.status, done: done[row.plant.id],
                                sticker: row.plant.id == stickerPlant ? stickerText(row) : nil,
                                now: now,
                                onWater: { water(row.plant) },
                                onStillWet: { stillWet(row.plant) },
                                onDone: { kind in markDone(row.plant, kind) },
                                onUndo: { undo(row.plant) }
                            )
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.95))))
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.spring(duration: 0.35), value: done.count)
        }
        .scrollIndicators(.hidden)
        .background(Color.cream)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: UUID.self) { id in
            if let p = plants.first(where: { $0.id == id }) { PlantDetailView(plant: p) }
        }
        .onAppear { now = Date() }
        .onChange(of: scenePhase) { _, p in if p == .active { now = Date(); done = [:] } }
    }

    private func header(plantCount: Int, careCount: Int, showAll: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Fmt.dayHeader(now)) · \(Season.of(now).label)")
                .font(.brico(13)).foregroundStyle(Color.muted)
            Text("À faire")
                .font(.brico(40, .heavy, relativeTo: .largeTitle))
                .tracking(-1)
                .foregroundStyle(Color.ink)
            if plantCount > 0 {
                HStack {
                    Text("\(plantCount) plante\(plantCount > 1 ? "s" : "") · \(careCount) soin\(careCount > 1 ? "s" : "")")
                        .font(.brico(14)).foregroundStyle(Color.muted)
                    Spacer()
                    if showAll {
                        Button("💧 Tout arroser", action: waterAll)
                            .buttonStyle(PillButtonStyle(kind: .dark, compact: true))
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private func stickerText(_ row: Row) -> String {
        Voice.pick(row.status.wateringTask?.urgent == true ? Voice.thirsty : Voice.check, seed: row.plant.id, date: now)
    }

    // MARK: Actions

    private func water(_ p: Plant) {
        let undo = p.water(in: ctx, now: Date())
        withAnimation { done[p.id] = DoneEntry(undo: undo, message: Voice.pick(Voice.happy, seed: p.id), stillWet: false) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func stillWet(_ p: Plant) {
        let undo = p.markStillWet(in: ctx, now: Date())
        withAnimation { done[p.id] = DoneEntry(undo: undo, message: Voice.pick(Voice.stillWet, seed: p.id), stillWet: true) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func markDone(_ p: Plant, _ kind: CareKind) {
        withAnimation { _ = p.markDone(kind, in: ctx, now: Date()) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func undo(_ p: Plant) {
        guard let entry = done[p.id] else { return }
        withAnimation {
            p.restore(entry.undo, in: ctx)
            done[p.id] = nil
        }
    }

    private func waterAll() {
        for row in rows where done[row.plant.id] == nil && row.status.wateringTask != nil {
            water(row.plant)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Carte d'une plante

struct TaskCard: View {
    let plant: Plant
    let status: CareStatus
    let done: DoneEntry?
    let sticker: String?
    let now: Date
    var onWater: () -> Void
    var onStillWet: () -> Void
    var onDone: (CareKind) -> Void
    var onUndo: () -> Void

    var body: some View {
        let profile = plant.profile
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                NavigationLink(value: plant.id) {
                    PlantIllustration(plant: plant, mood: done != nil ? (done!.stillWet ? .ok : .happy) : status.mood)
                        .frame(width: 68, height: 68)
                        .background(done != nil ? Color.white : plant.potStyle.tintColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plant.commonName + (done != nil ? " ✓" : ""))
                        .font(.brico(19, .heavy)).tracking(-0.3)
                    Text(subtitle).font(.brico(12.5)).foregroundStyle(done != nil ? Color.ink : Color.muted)
                }
                Spacer(minLength: 4)
                if let done {
                    Button("Annuler", action: onUndo)
                        .font(.brico(12, .semibold)).underline().foregroundStyle(Color.ink)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .accessibilityLabel(done.stillWet ? "Annuler encore humide" : "Annuler l'arrosage")
                } else if let w = status.wateringTask {
                    Group {
                        if w.urgent { Tag(text: "Arroser") } else { Tag(text: "Vérifier", background: .mustard, foreground: .ink) }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if let done {
                Sticker(text: done.message, color: .white).padding(.top, 10)
            } else if let sticker {
                Sticker(text: sticker).padding(.top, 10)
            }

            if done == nil, status.wateringTask != nil, let profile {
                Text(methodLine(profile))
                    .font(.brico(13)).foregroundStyle(Color(hex: 0x4A4760))
                    .padding(.top, 9)
                HStack(spacing: 8) {
                    Button("💧 Arrosé", action: onWater).buttonStyle(PillButtonStyle(kind: .fill))
                    Button("Encore humide", action: onStillWet).buttonStyle(PillButtonStyle(kind: .outline))
                }
                .padding(.top, 10)
            }

            ForEach(status.otherTasks) { task in
                HStack {
                    Text("\(task.kind.emoji) \(task.kind.actionLabel)").font(.brico(14, .semibold))
                    Spacer()
                    Button("Fait") { onDone(task.kind) }.buttonStyle(PillButtonStyle(kind: .outline, compact: true))
                }
                .padding(.top, 10)
            }
        }
        .card(done.map { $0.stillWet ? Color.sky : Color.sage } ?? .white)
    }

    private var subtitle: String {
        if done != nil {
            return "Prochaine vérif. \(Fmt.shortDay(status.wateringDue, now: now))"
        }
        var parts: [String] = []
        if let room = plant.room { parts.append(room) }
        if status.wateringTask != nil {
            parts.append(plant.lastWateredAt.map { Fmt.ago($0, now: now) } ?? "jamais arrosée ici")
        }
        return parts.joined(separator: " · ")
    }

    private func methodLine(_ p: CareProfile) -> String {
        var s = "🚿 " + p.watering.method
        if let w = p.watering.waterType { s += " Eau \(w)." }
        if status.wateringTask?.urgent == false { s += "\n👆 À vérifier : \(p.watering.checkHint.lowercased().trimmingCharacters(in: .punctuationCharacters))." }
        return s
    }
}

// MARK: - États vides

struct AllGoodView: View {
    let plants: [Plant]
    let now: Date

    var body: some View {
        let cast = Array(plants.shuffledStable(seed: Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0).prefix(3))
        VStack(spacing: 0) {
            ZStack {
                Blob(seed: 2).fill(Color.sage).frame(width: 270, height: 220)
                HStack(alignment: .bottom, spacing: -14) {
                    ForEach(Array(cast.enumerated()), id: \.element.id) { i, p in
                        let mood: Mood = p.snapshot().map { CareEngine.status($0, now: now).dormantUntil != nil ? .sleeping : .ok } ?? .ok
                        PlantIllustration(plant: p, mood: mood)
                            .frame(width: i == 1 ? 130 : 100)
                            .offset(y: i == 1 ? -30 : 0)
                    }
                }
            }
            .frame(height: 250)
            .padding(.top, 70)

            Text("Tout le monde va bien").font(.brico(26, .heavy)).padding(.top, 4)
            Text(Voice.pick(Voice.allGood, seed: plants.first?.id ?? UUID(), date: now)).font(.brico(15)).foregroundStyle(Color.muted)

        }
    }
}

struct EmptyCoLocView: View {
    var onAdd: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Blob(seed: 1).fill(Color.sand).frame(width: 240, height: 220)
                PlantIllustration(archetype: .monstera, mood: .happy, pot: .at(0)).frame(width: 170)
            }
            .padding(.top, 30)
            Text("La coloc est vide").font(.brico(26, .heavy))
            Text("Prends ta première plante en photo : je la reconnais et je te dis comment t'en occuper.")
                .font(.brico(15)).foregroundStyle(Color.muted).multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button("📷 Ajouter une plante", action: onAdd).buttonStyle(PillButtonStyle(kind: .fill)).padding(.top, 10).padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
    }
}

extension Array {
    /// Mélange déterministe (stable dans la journée).
    func shuffledStable(seed: Int) -> [Element] {
        var rng = SeededRNG(seed: UInt64(truncatingIfNeeded: seed &* 2654435761))
        return shuffled(using: &rng)
    }
}

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}

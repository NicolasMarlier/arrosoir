import SwiftUI
import SwiftData

struct PlantsView: View {
    var onAdd: () -> Void

    @Query(filter: #Predicate<Plant> { $0.archivedAt == nil }, sort: \Plant.commonName) private var plants: [Plant]
    @Query(filter: #Predicate<Plant> { $0.archivedAt != nil }) private var archived: [Plant]
    @State private var now = Date()

    private var groups: [(String, [Plant])] {
        let dict = Dictionary(grouping: plants) { $0.room?.isEmpty == false ? $0.room! : "Autres" }
        return dict.keys.sorted { a, b in
            if a == "Autres" { return false }
            if b == "Autres" { return true }
            return a.localizedCompare(b) == .orderedAscending
        }.map { ($0, dict[$0]!) }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(plants.count) plante\(plants.count > 1 ? "s" : "") · \(AppSettings.shared.city)")
                            .font(.brico(13)).foregroundStyle(Color.muted)
                        Text("Mes plantes").font(.brico(40, .heavy, relativeTo: .largeTitle)).tracking(-1)
                    }
                    Spacer()
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape.fill").font(.system(size: 20)).foregroundStyle(Color.ink)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Réglages")
                }
                .padding(.top, 12)

                if plants.isEmpty {
                    EmptyCoLocView(onAdd: onAdd)
                }

                ForEach(groups, id: \.0) { room, list in
                    SectionTitle(text: room)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(list) { p in
                            NavigationLink(value: p.id) { PlantTile(plant: p, now: now) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if !archived.isEmpty {
                    NavigationLink { GraveyardView() } label: {
                        HStack {
                            Text("🪦 Le jardin du souvenir").font(.brico(15, .bold))
                            Spacer()
                            Text("\(archived.count)").font(.brico(15)).foregroundStyle(Color.muted)
                            Image(systemName: "chevron.right").foregroundStyle(Color.muted)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 28)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .scrollIndicators(.hidden)
        .background(Color.cream.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: UUID.self) { id in
            if let p = plants.first(where: { $0.id == id }) { PlantDetailView(plant: p) }
        }
        .onAppear { now = Date() }
    }
}

struct PlantTile: View {
    let plant: Plant
    let now: Date

    var body: some View {
        let st = plant.snapshot().map { CareEngine.status($0, now: now) }
        let due = st?.watering.isDue == true
        VStack(spacing: 3) {
            PlantIllustration(plant: plant, mood: st?.mood == .happy ? .ok : (st?.mood ?? .ok))
                .frame(height: 78)
            Text(plant.commonName)
                .font(.brico(14, .heavy))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
            Text(nextLabel(st))
                .font(.brico(12, due ? .heavy : .semibold))
                .foregroundStyle(due ? Color.vermillon : Color.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
            if let st {
                Text("💧 \(Fmt.frequency(st.interval))")
                    .font(.brico(11))
                    .foregroundStyle(Color.ink.opacity(0.65))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(plant.potStyle.tintColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func nextLabel(_ st: CareStatus?) -> String {
        guard let st else { return "" }
        switch st.watering {
        case .water: return "J'ai soif !"
        case .check: return "À vérifier"
        case .soon(let d), .later(let d):
            let when = Fmt.coarseIn(d)
            return st.dormantUntil != nil ? "💤 \(when)" : when
        }
    }
}

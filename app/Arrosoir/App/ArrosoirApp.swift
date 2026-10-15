import SwiftUI
import SwiftData

@main
struct ArrosoirApp: App {
    let container: ModelContainer

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-inMemory")
        do {
            container = try ModelContainer(for: Plant.self, CareEvent.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
        } catch {
            fatalError("Impossible d'ouvrir la base : \(error)")
        }
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            let ctx = container.mainContext
            if ((try? ctx.fetchCount(FetchDescriptor<Plant>())) ?? 0) == 0 { DemoData.load(into: ctx) }
        }
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-gallery") {
                IllustrationGallery()
            } else if ProcessInfo.processInfo.arguments.contains("-candidatesDemo") {
                CandidatesDemo()
            } else {
                RootView()
                .environment(AppSettings.shared)
            }
        }
        .modelContainer(container)
    }
}

enum AppTab { case today, plants }

struct RootView: View {
    @State private var tab: AppTab = ProcessInfo.processInfo.arguments.contains("-plantsTab") ? .plants : .today
    @State private var showAdd = false
    @State private var plantsPath: [UUID] = []
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<Plant> { $0.archivedAt == nil }) private var plants: [Plant]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch tab {
                case .today: NavigationStack { TodayView(onAdd: { showAdd = true }) }
                case .plants: NavigationStack(path: $plantsPath) { PlantsView(onAdd: { showAdd = true }) }
                }
            }
            .frame(maxHeight: .infinity)
            TabBar(tab: $tab, onAdd: { showAdd = true })
        }
        .background(Color.cream.ignoresSafeArea())
        .tint(.ink)
        .fullScreenCover(isPresented: $showAdd) {
            AddPlantFlow()
        }
        .onAppear {
            // Raccourci de debug : -open <NomDeLaPlante>
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-open"), i + 1 < args.count,
               let p = plants.first(where: { $0.commonName == args[i + 1] }) {
                tab = .plants
                plantsPath = [p.id]
            }
            if args.contains("-add") { showAdd = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { SafetyNet.reschedule(plants: plants, enabled: settings.safetyNet) }
        }
    }
}

struct TabBar: View {
    @Binding var tab: AppTab
    var onAdd: () -> Void

    var body: some View {
        HStack {
            tabButton("À faire", .today)
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.vermillon, in: Circle())
                    .shadow(color: .vermillon.opacity(0.35), radius: 8, y: 4)
            }
            .accessibilityLabel("Ajouter une plante")
            tabButton("Mes plantes", .plants)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(Color.cream)
    }

    private func tabButton(_ title: String, _ t: AppTab) -> some View {
        Button {
            withAnimation(.snappy) { tab = t }
        } label: {
            Text(title)
                .font(.brico(14, tab == t ? .heavy : .semibold))
                .foregroundStyle(tab == t ? Color.ink : Color.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }
}

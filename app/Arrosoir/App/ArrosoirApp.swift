import SwiftUI
import SwiftData

@main
struct ArrosoirApp: App {
    let container: ModelContainer

    init() {
        Telemetry.start()
        let inMemory = ProcessInfo.processInfo.arguments.contains("-inMemory")
        let schema = Schema([Plant.self, CareEvent.self, Diagnosis.self])
        if inMemory {
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        } else {
            do {
                // Synchronisation iCloud (base privée de l'utilisateur) entre ses appareils.
                container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .private(CloudSync.containerID)))
                CloudSync.enabled = true
            } catch {
                // Repli : stockage local seul (iCloud indisponible ou mal configuré).
                Telemetry.capture(error, feature: "icloud-sync")
                do {
                    container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
                } catch {
                    fatalError("Impossible d'ouvrir la base : \(error)")
                }
            }
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

/// Les écrans de détail masquent la barre d'onglets (ils ont déjà un bouton retour).
@Observable
final class TabBarVisibility {
    var hiders = 0
    var isHidden: Bool { hiders > 0 }
}

extension View {
    func hidesTabBar() -> some View { modifier(HidesTabBar()) }
}

struct HidesTabBar: ViewModifier {
    @Environment(TabBarVisibility.self) private var visibility
    func body(content: Content) -> some View {
        content
            .onAppear { withAnimation(.snappy) { visibility.hiders += 1 } }
            .onDisappear { withAnimation(.snappy) { visibility.hiders = max(0, visibility.hiders - 1) } }
    }
}

struct RootView: View {
    @State private var tab: AppTab = ProcessInfo.processInfo.arguments.contains("-plantsTab") ? .plants : .today
    @State private var showAdd = false
    @State private var tabBar = TabBarVisibility()
    @State private var plantsPath: [UUID] = []
    @State private var debugDiagnosis: Plant?
    @State private var debugResult: Diagnosis?
    @State private var debugLoader: Plant?
    @Environment(\.modelContext) private var ctx
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.cream.ignoresSafeArea())
            if !tabBar.isHidden {
                TabBar(tab: $tab, onAdd: { showAdd = true })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(tabBar)
        .background(Color.cream.ignoresSafeArea())
        .tint(.ink)
        .fullScreenCover(isPresented: $showAdd) {
            AddPlantFlow()
        }
        .sheet(item: $debugDiagnosis) { p in DoctorSheet(plant: p, preview: ProcessInfo.processInfo.arguments.contains("-preview")).presentationBackground(Color.cream).presentationCornerRadius(32) }
        .sheet(item: $debugLoader) { p in DoctorLoader(plant: p).presentationBackground(Color.cream) }
        .sheet(item: $debugResult) { d in if let p = d.plant { DiagnosisResultView(plant: p, diagnosis: d) } }
        .onAppear {
            // Raccourci de debug : -open <NomDeLaPlante>
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-open"), i + 1 < args.count,
               let p = plants.first(where: { $0.commonName == args[i + 1] }) {
                tab = .plants
                plantsPath = [p.id]
            }
            if args.contains("-add") { showAdd = true }
            if args.contains("-demoPhoto") {
                let img = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).image { c in
                    UIColor(red: 0.25, green: 0.4, blue: 0.28, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
                    UIColor(red: 0.8, green: 0.7, blue: 0.55, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 800, width: 900, height: 400))
                }
                for p in plants { p.photo = img.jpegData(compressionQuality: 0.8) }
            }
            if args.contains("-allGood") {
                for p in plants {
                    p.lastWateredAt = Calendar.current.date(byAdding: .day, value: -1, to: Date())
                    for k in [CareKind.misting, .rotation, .fertilizing] { p.log(k, date: Date(), in: ctx) }
                }
            }
            if args.contains("-diagnose") { debugDiagnosis = plants.first }
            if args.contains("-doctorLoader") { debugLoader = plants.first }
            if args.contains("-diagnosisResult"), let p = plants.first {
                let d = Diagnosis(note: "Les feuilles du bas jaunissent depuis 2 semaines, et la terre reste humide longtemps.", photo: nil, result: DiagnosisResult(
                    title: "Excès d'eau probable", severity: .watch, plantSays: "J'ai les pieds dans l'eau, au secours 🫠",
                    summary: "Le jaunissement des feuilles basses avec une terre qui reste humide évoque un arrosage trop fréquent pour la saison. Rien d'irréversible.",
                    causes: ["Arrosage trop fréquent en automne", "Soucoupe qui garde l'eau", "Lumière en baisse"],
                    actions: ["Laisse sécher les 3 premiers cm avant d'arroser", "Vide la soucoupe 15 min après l'arrosage", "Retire les feuilles jaunes"],
                    wateringAdjustment: .less, followUpDays: 14))
                ctx.insert(d); d.plant = p
                debugResult = d
            }
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
        .readable(520)
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

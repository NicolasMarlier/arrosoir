import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Plant> { $0.archivedAt == nil }) private var plants: [Plant]
    @Query(filter: #Predicate<Plant> { $0.archivedAt != nil }) private var archived: [Plant]

    @State private var keyDraft = ""
    @State private var models: [AnthropicClient.ModelInfo] = []
    @State private var keyStatus: String?
    @State private var checking = false
    @State private var demoLoaded = false
    @State private var cloudStatus: CloudSync.Status?
    @State private var bugReport = ""
    @State private var bugSent = false

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Réglages").font(.brico(36, .heavy)).tracking(-1)

                SectionTitle(text: "Lieu")
                TextField("Ville", text: $settings.city)
                    .font(.brico(16)).padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                Text("Sert à caler les saisons et à contextualiser les fiches.").font(.brico(12)).foregroundStyle(Color.muted).padding(.top, 4)

                SectionTitle(text: "iCloud")
                HStack(spacing: 10) {
                    Image(systemName: "icloud.fill").font(.system(size: 20)).foregroundStyle(Color.cobalt)
                    Text(cloudStatus?.label ?? "Vérification…").font(.brico(14))
                }
                .card()

                SectionTitle(text: "Notifications")
                Toggle(isOn: Binding(get: { settings.safetyNet }, set: { toggleSafetyNet($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Filet de sécurité").font(.brico(16, .bold))
                        Text("Me prévenir si une plante a plus de \(SafetyNet.overdueDays) jours de retard.").font(.brico(12.5)).foregroundStyle(Color.muted)
                    }
                }
                .tint(.vermillon)
                .card()

                SectionTitle(text: "Claude (IA)")
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("Clé API Anthropic (sk-ant-…)", text: $keyDraft)
                        .font(.brico(15)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(12).background(Color.cream, in: RoundedRectangle(cornerRadius: 12))
                    HStack {
                        Button(checking ? "Vérification…" : "Enregistrer et tester") { saveKey() }
                            .buttonStyle(PillButtonStyle(kind: .dark, compact: true))
                            .disabled(checking)
                        if let keyStatus { Text(keyStatus).font(.brico(13, .semibold)) }
                    }
                    if !models.isEmpty {
                        Picker("Modèle", selection: $settings.model) {
                            ForEach(models) { m in Text(m.display_name ?? m.id).tag(m.id) }
                        }
                        .pickerStyle(.menu)
                        .tint(.ink)
                    } else if !settings.model.isEmpty {
                        Text("Modèle : \(settings.model)").font(.brico(13)).foregroundStyle(Color.muted)
                    }
                    Text("La clé reste sur ton iPhone (trousseau). Elle sert à reconnaître les plantes et à rédiger leurs fiches.")
                        .font(.brico(12)).foregroundStyle(Color.muted)
                }
                .card()

                SectionTitle(text: "Plantes")
                NavigationLink { GraveyardView() } label: {
                    HStack {
                        Text("🪦 Le jardin du souvenir").font(.brico(15, .bold))
                        Spacer()
                        Text("\(archived.count)").foregroundStyle(Color.muted)
                        Image(systemName: "chevron.right").foregroundStyle(Color.muted)
                    }
                    .card()
                }
                .buttonStyle(.plain)

                Button(demoLoaded ? "Plantes de démo ajoutées ✓" : "Ajouter des plantes de démo") {
                    DemoData.load(into: ctx)
                    demoLoaded = true
                }
                .buttonStyle(PillButtonStyle(kind: .outline))
                .disabled(demoLoaded)
                .padding(.top, 12)

                if Telemetry.isEnabled {
                    SectionTitle(text: "Un souci ?")
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Ce qui s'est passé (réponse illisible, écran bizarre…)", text: $bugReport, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.brico(15)).padding(12).background(Color.cream, in: RoundedRectangle(cornerRadius: 12))
                        Button(bugSent ? "Envoyé, merci ✓" : "Signaler un problème") {
                            Telemetry.feedback(bugReport.trimmingCharacters(in: .whitespacesAndNewlines))
                            bugReport = ""
                            bugSent = true
                        }
                        .buttonStyle(PillButtonStyle(kind: .dark, compact: true))
                        .disabled(bugReport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("Part avec les dernières actions et erreurs de l'app (jamais tes photos ni ta clé).")
                            .font(.brico(12)).foregroundStyle(Color.muted)
                    }
                    .card()
                }

                Text("Arrosoir \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · fait maison 🪴")
                    .font(.brico(12)).foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            }
            .padding(.horizontal, 16)
            .readable(720)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity)
        .scrollIndicators(.hidden)
        .background(Color.cream.ignoresSafeArea())
        .task { cloudStatus = await CloudSync.status() }
        .onAppear {
            keyDraft = settings.apiKey
            if settings.hasAPIKey && models.isEmpty { Task { await loadModels() } }
        }
    }

    private func saveKey() {
        settings.apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await loadModels() }
    }

    private func loadModels() async {
        guard settings.hasAPIKey else { keyStatus = nil; return }
        checking = true
        defer { checking = false }
        do {
            let list = try await AnthropicClient(apiKey: settings.apiKey, model: "").listModels()
            models = list
            if settings.model.isEmpty || !list.contains(where: { $0.id == settings.model }) {
                settings.model = AnthropicClient.preferredModel(in: list) ?? AnthropicClient.fallbackModel
            }
            keyStatus = "✅ Clé valide"
        } catch {
            keyStatus = "❌ " + (error.localizedDescription)
        }
    }

    private func toggleSafetyNet(_ on: Bool) {
        if on {
            Task {
                let ok = await SafetyNet.requestAuthorization()
                settings.safetyNet = ok
                SafetyNet.reschedule(plants: plants, enabled: ok)
            }
        } else {
            settings.safetyNet = false
            SafetyNet.reschedule(plants: plants, enabled: false)
        }
    }
}

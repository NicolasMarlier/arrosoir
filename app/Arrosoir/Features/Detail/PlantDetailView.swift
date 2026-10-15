import SwiftUI
import SwiftData

struct PlantDetailView: View {
    @Bindable var plant: Plant

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<Plant> { $0.archivedAt == nil }) private var allPlants: [Plant]

    @State private var now = Date()
    @State private var showLog = false
    @State private var showDiagnosis = false
    @State private var openedDiagnosis: Diagnosis?
    @State private var showEdit = false
    @State private var showPhoto = false
    @State private var askArchive = false
    @State private var askDelete = false
    @State private var working: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let snap = plant.snapshot(), let profile = plant.profile {
                let st = CareEngine.status(snap, now: now)
                VStack(alignment: .leading, spacing: 0) {
                    hero(st)
                    Text(plant.commonName)
                        .font(.brico(32, .heavy, relativeTo: .largeTitle)).tracking(-0.8)
                        .padding(.top, 14)
                    Text(plant.scientificName).font(.brico(14)).italic().foregroundStyle(Color.muted)
                    FlowLayout(spacing: 6) {
                        if let room = plant.room { chip("🏠 \(room)") }
                        if let light = plant.light { chip(light.label) }
                    }
                    .padding(.top, 8)

                    stateCard(st, profile).padding(.top, 14)

                    KeyValueRow(key: "Dernier arrosage", value: plant.lastWateredAt.map { Fmt.ago($0, now: now) } ?? "pas encore noté")
                        .padding(.top, 6)
                    KeyValueRow(key: "Prochaine vérif.", value: st.watering.isDue ? "maintenant" : Fmt.shortDay(st.wateringDue, now: now))
                    KeyValueRow(key: "Rythme en ce moment", value: "\(Fmt.frequency(st.interval)) (\(st.season.label.lowercased()))")
                    KeyValueRow(key: "Quantité", value: profile.watering.quantity)

                    Text(methodText(profile))
                        .font(.brico(13.5)).foregroundStyle(Color(hex: 0x4A4760))
                        .card().padding(.top, 10)

                    SectionTitle(text: "Soins")
                    KeyValueRow(key: "☀️ Lumière", value: profile.light)
                    if let d = profile.rotationDays, d > 0 {
                        KeyValueRow(key: "🔄 Rotation", value: plant.lastDone(.rotation).map { "fait \(Fmt.ago($0, now: now))" } ?? "tous les \(Int(d)) j")
                    }
                    KeyValueRow(key: "🧪 Engrais", value: fertilizingText(profile), mutedValue: profile.fertilizing == nil)
                    KeyValueRow(key: "💨 Brumisation", value: profile.mistingDays?.value(for: st.season).map { "\(Fmt.everyDays($0)) (\(st.season.label.lowercased()))" } ?? "pas besoin",
                                mutedValue: profile.mistingDays?.value(for: st.season) == nil)

                    SectionTitle(text: "À l'horizon")
                    ForEach(Array(CareEngine.horizon(snap, now: now).enumerated()), id: \.element.id) { i, h in
                        (Text("\(h.kind.emoji) ") + Text(h.title).bold() + Text(". \(h.detail)"))
                            .font(.brico(13.5))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(i == 0 ? Color.sand : Color.blush, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.top, 8)
                    }

                    rhythm(profile)

                    if !plant.diagnosisList.isEmpty {
                        SectionTitle(text: "Chez le docteur")
                        ForEach(plant.diagnosisList.sorted { $0.date > $1.date }) { d in
                            Button { openedDiagnosis = d } label: { diagnosisRow(d) }
                                .buttonStyle(.plain)
                        }
                    }

                    Button("✍️ Noter un soin") { showLog = true }
                        .buttonStyle(PillButtonStyle(kind: .outline))
                        .padding(.top, 20)
                }
                .padding(.horizontal, 16)
                .readable(720)
                .padding(.bottom, 100)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            DoctorBubble { showDiagnosis = true }
                .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color.cream.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Modifier", systemImage: "pencil") { showEdit = true }
                    Button("Régénérer la fiche", systemImage: "sparkles") { regenerate() }
                    Divider()
                    Button("Elle n'est plus là…", systemImage: "leaf") { askArchive = true }
                    Button("Supprimer", systemImage: "trash", role: .destructive) { askDelete = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.ink)
                }
            }
        }
        .overlay { if let working { WorkingOverlay(text: working) } }
        .sheet(isPresented: $showDiagnosis) {
            DoctorSheet(plant: plant)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
                .presentationBackground(Color.cream)
        }
        .sheet(item: $openedDiagnosis) { d in DiagnosisResultView(plant: plant, diagnosis: d).presentationDragIndicator(.visible) }
        .sheet(isPresented: $showLog) { LogCareSheet(plant: plant).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showEdit) { EditPlantSheet(plant: plant, rooms: Array(Set(allPlants.compactMap(\.room)))).presentationDetents([.large]) }
        .fullScreenCover(isPresented: $showPhoto) { PhotoViewer(data: plant.photo) }
        .confirmationDialog("Que s'est-il passé ?", isPresented: $askArchive, titleVisibility: .visible) {
            Button("🥀 Elle est morte") { archive(.died) }
            Button("🎁 Je l'ai donnée") { archive(.given) }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("Supprimer définitivement \(plant.commonName) ?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                dismiss()
                ctx.delete(plant)
                try? ctx.save()
            }
        }
        .alert("Oups", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .onAppear { now = Date() }
    }

    // MARK: Sous-vues

    @ViewBuilder
    private func hero(_ st: CareStatus) -> some View {
        if let data = plant.photo, let img = UIImage(data: data) {
            // La vraie photo en grand, le personnage en vignette.
            Button { showPhoto = true } label: {
                Color.clear
                    .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 440 : 300)
                    .overlay { Image(uiImage: img).resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voir la photo en grand")
            .overlay(alignment: .bottomTrailing) {
                PlantIllustration(plant: plant, mood: st.mood)
                    .padding(4)
                    .frame(width: 84, height: 84)
                    .background(plant.potStyle.tintColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white, lineWidth: 3))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        } else {
            PlantIllustration(plant: plant, mood: st.mood)
                .frame(width: 210, height: 210)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .background(plant.potStyle.tintColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private func chip(_ t: String) -> some View {
        Text(t).font(.brico(12.5, .bold)).padding(.horizontal, 10).padding(.vertical, 5).background(Color.white, in: Capsule())
    }

    @ViewBuilder
    private func stateCard(_ st: CareStatus, _ p: CareProfile) -> some View {
        if st.watering.isDue {
            VStack(alignment: .leading, spacing: 4) {
                Text(st.watering == .water ? "💧 J'ai soif !" : "👆 C'est le moment de vérifier").font(.brico(17, .heavy))
                Text("\(p.watering.checkHint) ? Alors arrose.").font(.brico(13.5))
            }
            .foregroundStyle(st.watering == .water ? Color.white : Color.ink)
            .card(st.watering == .water ? .vermillon : .mustard)
        } else if let end = st.dormantUntil {
            VStack(alignment: .leading, spacing: 4) {
                Text("💤 Au repos jusqu'à fin \(lastDormantMonth(end))").font(.brico(17, .heavy))
                if let advice = p.dormancy?.advice { Text(advice).font(.brico(13.5)).opacity(0.92) }
            }
            .foregroundStyle(.white)
            .card(.cobalt)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("😊 En forme").font(.brico(17, .heavy))
                Text("Prochaine vérification \(Fmt.shortDay(st.wateringDue, now: now)).").font(.brico(13.5))
            }
            .card(.sage)
        }
    }

    private func rhythm(_ p: CareProfile) -> some View {
        let f = plant.learnedFactor * plant.manualFactor
        let winter = CareEngine.baseInterval(p, season: .winter) * f
        let summer = CareEngine.baseInterval(p, season: .summer) * f
        return VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "Son rythme")
            Text("Arrosage \(Fmt.everyDays(winter)) en hiver · \(Fmt.everyDays(summer)) en été")
                .font(.brico(13.5)).foregroundStyle(Color.muted)
            if abs(plant.learnedFactor - 1) > 0.04 {
                let pct = Int(((plant.learnedFactor - 1) * 100).rounded())
                Text("Ajusté grâce à tes retours : \(pct > 0 ? "+" : "")\(pct) %").font(.brico(12.5)).foregroundStyle(Color.muted)
            }
            Slider(value: $plant.manualFactor, in: 0.5...2, step: 0.05)
                .tint(.cobalt)
                .padding(.top, 6)
            HStack {
                Text("Plus souvent"); Spacer(); Text("Moins souvent")
            }
            .font(.brico(12)).foregroundStyle(Color.muted)
        }
    }

    private func diagnosisRow(_ d: Diagnosis) -> some View {
        HStack(spacing: 12) {
            Group {
                if let data = d.photo, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.cream.overlay(Text("🩺"))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(d.result?.title ?? "Diagnostic").font(.brico(15, .heavy)).lineLimit(1)
                Text(Fmt.ago(d.date, now: now).capitalizedFirst).font(.brico(12)).foregroundStyle(Color.muted)
            }
            Spacer()
            Circle().fill(d.result.map { $0.severity == .ok ? Color.leafGreen : $0.severity == .watch ? Color.mustard : Color.vermillon } ?? .muted)
                .frame(width: 10, height: 10)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.muted)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.top, 6)
    }

    // MARK: Textes

    private func methodText(_ p: CareProfile) -> String {
        var s = "🚿 " + p.watering.method
        if let w = p.watering.waterType { s += "\n💧 Eau \(w)." }
        return s
    }

    private func fertilizingText(_ p: CareProfile) -> String {
        guard let f = p.fertilizing else { return "pas besoin" }
        let month = Calendar.current.component(.month, from: now)
        if f.months.contains(month) { return "tous les \(Int(f.intervalDays)) j" }
        let next = (1...12).map { (month + $0 - 1) % 12 + 1 }.first { f.months.contains($0) } ?? f.months.first ?? 4
        return "pas avant \(Fmt.monthName(next))"
    }

    private func lastDormantMonth(_ end: Date) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        return Fmt.monthName(Calendar.current.component(.month, from: d))
    }

    // MARK: Actions

    private func regenerate() {
        working = "Je relis mes notes de botanique…"
        Task {
            defer { working = nil }
            do {
                plant.profile = try await PlantAI(settings: settings).careProfile(commonName: plant.commonName, scientificName: plant.scientificName, room: plant.room, light: plant.light)
                try? ctx.save()
            } catch {
                Telemetry.breadcrumb("Erreur affichée : \(error.localizedDescription)", category: "ui", level: .error)
                self.error = error.localizedDescription
            }
        }
    }

    private func archive(_ reason: ArchiveReason) {
        working = reason == .died ? "Un instant de recueillement…" : "Je prépare ses valises…"
        Task {
            let text = await PlantAI(settings: settings).epitaph(name: plant.commonName, reason: reason, since: plant.createdAt)
            plant.archive(reason, epitaph: text, in: ctx)
            working = nil
            dismiss()
        }
    }
}

struct WorkingOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.cream.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(.ink)
                Text(text).font(.brico(16, .bold)).multilineTextAlignment(.center)
            }
            .padding(30)
        }
    }
}

struct PhotoViewer: View {
    let data: Data?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.white.opacity(0.2), in: Circle())
            }
            .padding()
        }
    }
}

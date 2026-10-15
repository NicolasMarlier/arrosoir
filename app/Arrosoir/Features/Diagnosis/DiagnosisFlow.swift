import SwiftUI
import SwiftData
import PhotosUI

/// Diagnostic : photos + description (dictée ou texte) → Claude.
struct DiagnosisFlow: View {
    let plant: Plant

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(AppSettings.self) private var settings

    @State private var photos: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var note = ""
    @State private var dictation = Dictation()
    @State private var analyzing = false
    @State private var error: String?
    @State private var result: Diagnosis?
    @FocusState private var noteFocused: Bool

    private let maxPhotos = 4
    private var canRun: Bool { !photos.isEmpty || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    DiagnosisResultView(plant: plant, diagnosis: result, onDone: { dismiss() })
                } else if analyzing {
                    analyzingView
                } else {
                    compose
                }
            }
            .background(Color.cream.ignoresSafeArea())
            .toolbar {
                if result == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dictation.stop(); dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                        }
                        .accessibilityLabel("Fermer")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                showCamera = false
                if let img, photos.count < maxPhotos { photos.append(img) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items where photos.count < maxPhotos {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { photos.append(img) }
                }
                pickerItems = []
            }
        }
    }

    // MARK: Saisie

    private var compose: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    PlantIllustration(plant: plant, mood: .ok)
                        .frame(width: 70, height: 70)
                        .background(plant.potStyle.tintColor, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostic").font(.brico(28, .heavy)).tracking(-0.5)
                        Text(plant.commonName).font(.brico(15)).foregroundStyle(Color.muted)
                    }
                }

                SectionTitle(text: "1 · Montre-moi")
                Text("Une vue d'ensemble, puis les zones qui t'inquiètent de près (feuilles, tiges, terre, dessous des feuilles).")
                    .font(.brico(13)).foregroundStyle(Color.muted)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { i, img in
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { photos.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.ink)
                                    }
                                    .padding(4)
                                    .accessibilityLabel("Retirer la photo")
                                }
                        }
                        if photos.count < maxPhotos {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                addTile("camera.fill", "Photo") { showCamera = true }
                            }
                            PhotosPicker(selection: $pickerItems, maxSelectionCount: maxPhotos - photos.count, matching: .images) {
                                AddTileLabel(icon: "photo.on.rectangle", title: "Galerie")
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)

                SectionTitle(text: "2 · Raconte-moi")
                Text("Ce que tu remarques, depuis quand, ce qui a changé (arrosage, place, chauffage…).")
                    .font(.brico(13)).foregroundStyle(Color.muted)

                VStack(spacing: 12) {
                    micButton
                    if dictation.isRecording {
                        Text(dictation.partial.isEmpty ? "Je t'écoute…" : dictation.partial)
                            .font(.brico(15)).foregroundStyle(Color.ink.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if dictation.state == .denied {
                        Text("Autorise le micro et la reconnaissance vocale dans Réglages > Arrosoir.").font(.brico(12.5)).foregroundStyle(Color.vermillon)
                    } else if dictation.state == .unavailable {
                        Text("Dictée indisponible pour le moment : écris plutôt ci-dessous.").font(.brico(12.5)).foregroundStyle(Color.vermillon)
                    }
                    TextField("…ou écris ici (ex. « les feuilles du bas jaunissent depuis 2 semaines »)", text: $note, axis: .vertical)
                        .font(.brico(15))
                        .lineLimit(3...10)
                        .focused($noteFocused)
                        .padding(12)
                        .background(Color.cream, in: RoundedRectangle(cornerRadius: 14))
                }
                .card()
                .padding(.top, 8)

                if let error {
                    Text(error).font(.brico(14, .semibold)).foregroundStyle(Color.vermillon).padding(.top, 12)
                }
                if !settings.hasAPIKey {
                    Text("🔑 Ajoute ta clé API Anthropic dans les réglages.").font(.brico(13, .semibold)).card(.sand).padding(.top, 12)
                }

                Button("🩺 Lancer le diagnostic") { run() }
                    .buttonStyle(PillButtonStyle(kind: .fill))
                    .disabled(!canRun || !settings.hasAPIKey || dictation.isRecording)
                    .opacity(canRun && settings.hasAPIKey && !dictation.isRecording ? 1 : 0.4)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var micButton: some View {
        Button {
            if dictation.isRecording {
                dictation.stop()
            } else {
                noteFocused = false
                Task {
                    await dictation.start { text in
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        note = note.isEmpty ? t : note + "\n" + t
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(dictation.isRecording ? Color.vermillon.opacity(0.25) : .clear)
                        .frame(width: 54, height: 54)
                        .scaleEffect(1 + CGFloat(dictation.level) * 0.6)
                        .animation(.easeOut(duration: 0.12), value: dictation.level)
                    Circle().fill(Color.vermillon).frame(width: 46, height: 46)
                    Image(systemName: dictation.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(dictation.isRecording ? "Touche pour arrêter" : "Parle-moi d'elle").font(.brico(16, .heavy))
                    Text(dictation.isRecording ? "Enregistrement en cours" : "Note vocale, transcrite sur ton iPhone").font(.brico(12)).foregroundStyle(Color.muted)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dictation.isRecording ? "Arrêter la dictée" : "Dicter une description")
    }

    private func addTile(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { AddTileLabel(icon: icon, title: title) }.buttonStyle(.plain)
    }

    // MARK: Analyse

    private var analyzingView: some View {
        VStack(spacing: 18) {
            Spacer()
            PlantIllustration(plant: plant, mood: .ok)
                .frame(width: 180, height: 180)
                .background(Blob(seed: 4).fill(plant.potStyle.tintColor).frame(width: 240, height: 220))
            Text("Le docteur des plantes l'examine… 🩺").font(.brico(19, .heavy)).multilineTextAlignment(.center)
            ProgressView().controlSize(.large).tint(.ink)
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }

    private func run() {
        dictation.stop()
        error = nil
        analyzing = true
        let jpegs = photos.compactMap { ImageUtils.jpeg($0, maxSide: 1280, quality: 0.75) }
        let context = plant.diagnosisContext()
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { analyzing = false }
            do {
                let r = try await PlantAI(settings: settings).diagnose(context: context, note: text, photos: jpegs)
                let thumb = photos.first.flatMap { ImageUtils.jpeg($0, maxSide: 1000, quality: 0.75) }
                let d = Diagnosis(note: text, photo: thumb, result: r)
                ctx.insert(d)
                d.plant = plant
                try? ctx.save()
                result = d
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

// MARK: - Résultat

struct DiagnosisResultView: View {
    @Bindable var plant: Plant
    let diagnosis: Diagnosis
    var onDone: (() -> Void)?

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var adjusted = false
    @State private var showPhoto = false

    var body: some View {
        ScrollView {
            if let r = diagnosis.result {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomTrailing) {
                        PlantIllustration(plant: plant, mood: mood(r))
                            .frame(width: 190, height: 190)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                        if let data = diagnosis.photo, let img = UIImage(data: data) {
                            Button { showPhoto = true } label: {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 66, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white, lineWidth: 3))
                            }
                            .padding(12)
                        }
                    }
                    .background(plant.potStyle.tintColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    Sticker(text: r.plantSays).padding(.top, 14)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(severityLabel(r.severity)).font(.brico(12, .heavy)).tracking(1).textCase(.uppercase).opacity(0.85)
                        Text(r.title).font(.brico(22, .heavy))
                        Text(r.summary).font(.brico(14.5))
                    }
                    .foregroundStyle(r.severity == .ok ? Color.ink : .white)
                    .card(severityColor(r.severity))
                    .padding(.top, 14)

                    if !r.causes.isEmpty {
                        SectionTitle(text: "Causes probables")
                        ForEach(Array(r.causes.enumerated()), id: \.offset) { i, c in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)").font(.brico(13, .heavy)).foregroundStyle(.white)
                                    .frame(width: 22, height: 22).background(Color.ink, in: Circle())
                                Text(c).font(.brico(14.5))
                            }
                            .padding(.vertical, 5)
                        }
                    }

                    if !r.actions.isEmpty {
                        SectionTitle(text: "À faire")
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(r.actions.enumerated()), id: \.offset) { _, a in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("✓").font(.brico(15, .heavy)).foregroundStyle(Color.leafGreen)
                                    Text(a).font(.brico(14.5))
                                }
                            }
                        }
                        .card()
                    }

                    if r.wateringAdjustment != .none {
                        let more = r.wateringAdjustment == .more
                        VStack(alignment: .leading, spacing: 8) {
                            Text(more ? "💧 Elle a besoin de plus d'eau" : "🌊 Elle reçoit trop d'eau").font(.brico(16, .heavy))
                            Text(more ? "Je peux resserrer son rythme d'arrosage d'environ 20 %." : "Je peux espacer son rythme d'arrosage d'environ 20 %.")
                                .font(.brico(13.5))
                            Button(adjusted ? "Rythme ajusté ✓" : (more ? "Arroser plus souvent" : "Arroser moins souvent")) {
                                plant.manualFactor = CareEngine.clamp(plant.manualFactor * (more ? 0.8 : 1.25))
                                try? ctx.save()
                                adjusted = true
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                            .buttonStyle(PillButtonStyle(kind: .dark, compact: true))
                            .disabled(adjusted)
                        }
                        .card(.sky)
                        .padding(.top, 14)
                    }

                    if let days = r.followUpDays, days > 0 {
                        Text("🔁 Refais un diagnostic dans ~\(days) jours pour voir si ça s'améliore.")
                            .font(.brico(13)).foregroundStyle(Color.muted).padding(.top, 14)
                    }

                    if !diagnosis.note.isEmpty {
                        SectionTitle(text: "Ce que tu as dit")
                        Text("« \(diagnosis.note) »").font(.brico(13.5)).italic().foregroundStyle(Color.muted)
                    }

                    Text(diagnosis.date.formatted(.dateTime.day().month(.wide).year().locale(Fmt.locale)))
                        .font(.brico(12)).foregroundStyle(Color.muted).padding(.top, 16)

                    if let onDone {
                        Button("Merci docteur !", action: onDone)
                            .buttonStyle(PillButtonStyle(kind: .fill))
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.cream.ignoresSafeArea())
        .fullScreenCover(isPresented: $showPhoto) { PhotoViewer(data: diagnosis.photo) }
    }

    private func mood(_ r: DiagnosisResult) -> Mood {
        switch r.severity {
        case .ok: .happy
        case .watch: .ok
        case .urgent: .thirsty
        }
    }

    private func severityLabel(_ s: DiagnosisResult.Severity) -> String {
        switch s {
        case .ok: "Tout va bien"
        case .watch: "À surveiller"
        case .urgent: "Urgent"
        }
    }

    private func severityColor(_ s: DiagnosisResult.Severity) -> Color {
        switch s {
        case .ok: .sage
        case .watch: .cobalt
        case .urgent: .vermillon
        }
    }
}

struct AddTileLabel: View {
    let icon: String
    let title: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold))
            Text(title).font(.brico(12, .bold))
        }
        .foregroundStyle(Color.ink)
        .frame(width: 96, height: 96)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }
}

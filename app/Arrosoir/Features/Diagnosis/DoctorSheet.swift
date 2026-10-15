import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Bulle flottante sur la fiche

struct DoctorBubble: View {
    var action: () -> Void
    @State private var breathe = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.vermillon, lineWidth: 3)
                        .frame(width: 50, height: 50)
                        .scaleEffect(breathe ? 1.3 : 0.92)
                        .opacity(breathe ? 0 : 0.55)
                    Circle().fill(Color.vermillon).frame(width: 46, height: 46)
                    Image(systemName: "mic.fill").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                }
                Text("Demande au docteur").font(.brico(16, .heavy)).foregroundStyle(Color.ink)
            }
            .padding(.leading, 7)
            .padding(.trailing, 20)
            .padding(.vertical, 7)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.ink.opacity(0.06), lineWidth: 1.5))
            .shadow(color: Color.ink.opacity(0.18), radius: 13, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Demande au docteur")
        .onAppear {
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { breathe = true }
        }
    }
}

// MARK: - Panneau « docteur »

/// S'ouvre déjà en écoute. Pas de bouton stop : « Envoyer au docteur » coupe l'écoute.
struct DoctorSheet: View {
    let plant: Plant
    /// Aperçu (debug) : pas de micro, texte factice.
    var preview = false

    enum Phase { case listening, loading, result }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(AppSettings.self) private var settings

    @State private var dictation = Dictation()
    @State private var phase: Phase = .listening
    @State private var photos: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var typed = ""
    @State private var error: String?
    @State private var diagnosis: Diagnosis?

    private let maxPhotos = 4
    private var text: String {
        let spoken = dictation.fullText
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return [spoken, t].filter { !$0.isEmpty }.joined(separator: "\n")
    }
    private var canSend: Bool { !text.isEmpty || !photos.isEmpty }
    private var micBlocked: Bool { dictation.state == .denied || dictation.state == .unavailable }

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()
            switch phase {
            case .listening: listening
            case .loading: DoctorLoader(plant: plant).transition(.opacity)
            case .result:
                if let diagnosis {
                    DiagnosisResultView(plant: plant, diagnosis: diagnosis, onDone: { dismiss() })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.snappy, value: phase)
        .task {
            if preview {
                dictation.committed = "Est-ce que c'est normal que les feuilles du haut jaunissent et tombent quand je les touche ?"
                dictation.partial = "Je l'arrose à peu près tous les dix"
                dictation.level = 0.7
            } else {
                await dictation.start()
            }
        }
        .onDisappear { dictation.stop() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                showCamera = false
                if let img, photos.count < maxPhotos { photos.append(img) }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $pickerItems, maxSelectionCount: max(1, maxPhotos - photos.count), matching: .images)
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

    // MARK: Écoute

    private var listening: some View {
        VStack(spacing: 0) {
            HStack {
                Text(plant.commonName).font(.brico(14, .bold))
                if dictation.isRecording {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let s = max(0, Int(ctx.date.timeIntervalSince(dictation.startedAt)))
                        HStack(spacing: 5) {
                            Circle().fill(Color.vermillon).frame(width: 7, height: 7)
                                .opacity(s % 2 == 0 ? 1 : 0.35)
                            Text(String(format: "%d:%02d", s / 60, s % 60)).font(.brico(12, .heavy)).foregroundStyle(Color.vermillon).monospacedDigit()
                        }
                    }
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.ink)
                        .frame(width: 32, height: 32).background(Color.white, in: Circle())
                }
                .accessibilityLabel("Fermer")
            }
            .padding(.top, 18)

            ListeningPlant(plant: plant, level: dictation.level)
                .frame(height: 140)
                .padding(.top, 4)

            Text("Je t'écoute 👂").font(.brico(22, .heavy))
            Text("Une question, un doute, un symptôme : dis-moi tout.")
                .font(.brico(13.5)).foregroundStyle(Color.muted).multilineTextAlignment(.center)
                .padding(.top, 2)

            SoundBars(level: micBlocked ? 0 : dictation.level)
                .frame(height: 80)
                .padding(.vertical, 8)

            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { i, img in
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { photos.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                                            .symbolRenderingMode(.palette).foregroundStyle(.white, Color.ink)
                                    }
                                    .offset(x: 6, y: -6)
                                    .accessibilityLabel("Retirer la photo")
                                }
                        }
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 8)
            }

            transcript
                .overlay(alignment: .bottomTrailing) { photoMenu.padding(10) }

            if let error {
                Text(error).font(.brico(13.5, .semibold)).foregroundStyle(Color.vermillon)
                    .multilineTextAlignment(.center).padding(.top, 8)
            }

            Button(action: send) {
                HStack(spacing: 10) {
                    Text("🩺").font(.system(size: 24))
                    Text("Envoyer au docteur").font(.brico(20, .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 66)
                .background(Color.vermillon, in: Capsule())
                .shadow(color: .vermillon.opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(!canSend || !settings.hasAPIKey)
            .opacity(canSend && settings.hasAPIKey ? 1 : 0.4)
            .padding(.top, 14)

            if !settings.hasAPIKey {
                Text("🔑 Ajoute ta clé API Anthropic dans les réglages.").font(.brico(12.5)).foregroundStyle(Color.muted).padding(.top, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var photoMenu: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Prendre une photo", systemImage: "camera") { showCamera = true }
            }
            Button("Choisir dans la galerie", systemImage: "photo.on.rectangle") { showLibrary = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "camera.fill").font(.system(size: 14, weight: .bold))
                Text("Photo").font(.brico(14, .heavy))
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.cream, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.ink.opacity(0.15), lineWidth: 1.5))
        }
        .disabled(photos.count >= maxPhotos)
        .opacity(photos.count >= maxPhotos ? 0.4 : 1)
        .accessibilityLabel("Ajouter une photo")
    }

    @ViewBuilder
    private var transcript: some View {
        if micBlocked {
            VStack(alignment: .leading, spacing: 6) {
                Text(dictation.state == .denied
                     ? "Autorise le micro et la reconnaissance vocale dans Réglages > Arrosoir. En attendant, écris ici :"
                     : "La dictée n'est pas disponible pour le moment. Écris ici :")
                    .font(.brico(12.5)).foregroundStyle(Color.muted)
                TextField("Ta question ou ce que tu remarques…", text: $typed, axis: .vertical)
                    .font(.brico(15)).lineLimit(3...8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if dictation.committed.isEmpty && dictation.partial.isEmpty {
                            Text("Parle normalement, je transcris en direct…").foregroundStyle(Color(hex: 0xB9B2C4))
                        } else {
                            Text(dictation.committed + (dictation.committed.isEmpty ? "" : " "))
                                .foregroundStyle(Color.ink)
                            + Text(dictation.partial).foregroundStyle(Color.muted)
                        }
                    }
                    .font(.brico(16))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 44)
                    .id("end")
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.top)
                .onChange(of: dictation.partial) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Envoi

    private func send() {
        let note = dictation.stop()
        let full = [note, typed.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }.joined(separator: "\n")
        error = nil
        phase = .loading
        let jpegs = photos.compactMap { ImageUtils.jpeg($0, maxSide: 1280, quality: 0.75) }
        let context = plant.diagnosisContext()
        let started = Date()
        Task {
            do {
                let r = try await PlantAI(settings: settings).diagnose(context: context, note: full, photos: jpegs)
                // Laisse le temps de profiter de la loupe 🔍
                let elapsed = Date().timeIntervalSince(started)
                if elapsed < 2.5 { try? await Task.sleep(for: .seconds(2.5 - elapsed)) }
                let thumb = photos.first.flatMap { ImageUtils.jpeg($0, maxSide: 1000, quality: 0.75) }
                let d = Diagnosis(note: full, photo: thumb, result: r)
                ctx.insert(d)
                d.plant = plant
                try? ctx.save()
                diagnosis = d
                phase = .result
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                typed = full
                phase = .listening
            }
        }
    }
}

// MARK: - La plante qui tend l'oreille

struct ListeningPlant: View {
    let plant: Plant
    let level: Float
    @State private var wobble = false

    var body: some View {
        let speaking = level > 0.08
        ZStack {
            Blob(seed: 3).fill(Color.sand)
                .frame(width: 160, height: 136)
                .rotationEffect(.degrees(wobble ? 8 : -4))
            PlantIllustration(plant: plant, mood: .ok, gaze: CGSize(width: 0.75, height: -0.35))
                .frame(width: 124, height: 124)
                .scaleEffect(1 + CGFloat(level) * 0.04, anchor: .bottom)
            EarWaves()
                .stroke(Color.cobalt, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 30, height: 50)
                .offset(x: 92, y: -22)
                .opacity(speaking ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: speaking)
        }
        .onAppear { withAnimation(.easeInOut(duration: 5).repeatForever()) { wobble = true } }
    }
}

nonisolated struct EarWaves: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.minX, y: r.midY)
        for k in [0.35, 0.68, 1.0] {
            let radius = r.height / 2 * k
            p.move(to: CGPoint(x: c.x + radius * cos(-.pi / 4), y: c.y + radius * sin(-.pi / 4)))
            p.addArc(center: c, radius: radius, startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false)
        }
        return p
    }
}

// MARK: - Barre de son en papier découpé (plate pendant les silences)

struct SoundBars: View {
    let level: Float
    private let count = 22
    private let colors: [Color] = [.vermillon, .mustard, .cobalt, .leafGreen, .pinkFlower]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { i in
                    let profile = 0.45 + 0.55 * sin(Double.pi * (Double(i) + 0.5) / Double(count))
                    let jitter = 0.55 + 0.45 * abs(sin(t * (6 + Double(i % 5)) + Double(i)))
                    let h = 8 + CGFloat(Double(level) * profile * jitter) * 70
                    Capsule().fill(colors[i % colors.count])
                        .frame(width: 7, height: h)
                }
            }
            .animation(.linear(duration: 0.08), value: level)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Chargement : la loupe

struct DoctorLoader: View {
    let plant: Plant
    @State private var start = Date()

    private let messages = [
        "J'ausculte les feuilles… 🔍", "Je réfléchis à ta question 🤔", "Je renifle la terre… 👃",
        "Je consulte mes collègues cactus 🌵", "Je relis son carnet de santé 📖", "Je rédige ma réponse ✍️",
    ]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            let phase = t * 2 * .pi / 3.2
            let lx = 52 * sin(phase)
            let ly = 34 * sin(2 * phase) - 6
            let msg = Int(t / 1.4) % messages.count
            let leaves = min(4, Int(t / 1.0))
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    Blob(seed: 5).fill(Color.sage)
                        .frame(width: 230, height: 220)
                        .rotationEffect(.degrees(6 * sin(t * 1.2)))
                    PlantIllustration(plant: plant, mood: .ok, gaze: CGSize(width: lx / 52, height: ly / 40))
                        .frame(width: 180, height: 180)
                        .scaleEffect(x: 1, y: 1 - 0.025 * abs(sin(t * 3.9)), anchor: .bottom)
                    Loupe()
                        .frame(width: 92, height: 92)
                        .rotationEffect(.degrees(12 * sin(phase)))
                        .offset(x: lx, y: ly - 20)
                }
                .frame(height: 260)

                Text(messages[msg])
                    .font(.brico(20, .heavy))
                    .multilineTextAlignment(.center)
                    .id(msg)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    .animation(.spring(duration: 0.4), value: msg)
                    .frame(minHeight: 56)
                    .padding(.top, 18)

                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        LeafShape()
                            .fill(i <= leaves ? Color.leafGreen : Color(hex: 0xE3D6BD))
                            .frame(width: 16, height: 16)
                    }
                }
                .animation(.easeOut(duration: 0.3), value: leaves)
                .padding(.top, 10)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Le docteur examine ta plante")
    }
}

nonisolated struct Loupe: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 100
            ctx.scaleBy(x: s, y: s)
            ctx.fill(Path(ellipseIn: CGRect(x: 12, y: 12, width: 52, height: 52)), with: .color(.white.opacity(0.35)))
            ctx.stroke(Path(ellipseIn: CGRect(x: 12, y: 12, width: 52, height: 52)), with: .color(.cobalt), lineWidth: 9)
            var handle = Path(); handle.move(to: CGPoint(x: 58, y: 58)); handle.addLine(to: CGPoint(x: 86, y: 86))
            ctx.stroke(handle, with: .color(.ink), style: StrokeStyle(lineWidth: 12, lineCap: .round))
            var shine = Path(); shine.move(to: CGPoint(x: 26, y: 30)); shine.addQuadCurve(to: CGPoint(x: 40, y: 22), control: CGPoint(x: 30, y: 22))
            ctx.stroke(shine, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }
}

nonisolated struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

import SwiftUI
import SwiftData
import PhotosUI

struct AddPlantFlow: View {
    enum Step { case source, identifying, candidates, details, welcome }
    enum LastWatered: String, CaseIterable { case today, fewDays, week, unknown
        var label: String {
            switch self {
            case .today: "Aujourd'hui"
            case .fewDays: "Qq jours"
            case .week: "+ 1 sem."
            case .unknown: "Aucune idée"
            }
        }
        var daysAgo: Int? {
            switch self {
            case .today: 0
            case .fewDays: 3
            case .week: 8
            case .unknown: nil
            }
        }
    }
    enum Repot: String, CaseIterable { case lessThanYear, oneTwo, moreThanTwo, unknown
        var label: String {
            switch self {
            case .lessThanYear: "< 1 an"
            case .oneTwo: "1-2 ans"
            case .moreThanTwo: "+ 2 ans"
            case .unknown: "?"
            }
        }
        var monthsAgo: Int? {
            switch self {
            case .lessThanYear: 6
            case .oneTwo: 18
            case .moreThanTwo: 30
            case .unknown: nil
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(AppSettings.self) private var settings
    @Query private var allPlants: [Plant]

    @State private var step: Step = .source
    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var identification: Identification?
    @State private var selected: SpeciesCandidate?
    @State private var manualName = ""
    @State private var showManual = false
    @State private var error: String?

    @State private var profileTask: Task<CareProfile, Error>?
    @State private var lastWatered: LastWatered = .fewDays
    @State private var room: String?
    @State private var light: LightLevel?
    @State private var repot: Repot = .unknown
    @State private var creating = false
    @State private var created: Plant?

    var body: some View {
        NavigationStack {
            ZStack {
                (step == .welcome ? (created?.potStyle.tintColor ?? .sage) : Color.cream).ignoresSafeArea()
                switch step {
                case .source: sourceStep
                case .identifying: identifyingStep
                case .candidates: candidatesStep
                case .details: detailsStep
                case .welcome: welcomeStep
                }
            }
            .animation(.snappy, value: step)
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { cancel() } label: {
                            Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                        }
                        .accessibilityLabel("Fermer")
                    }
                }
            }
            .overlay { if creating { WorkingOverlay(text: "Je prépare sa fiche…") } }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                showCamera = false
                if let img { start(with: img) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    start(with: img)
                }
                pickerItem = nil
            }
        }
    }

    // MARK: - Étapes

    private var sourceStep: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Blob(seed: 3).fill(Color.sage).frame(width: 250, height: 220)
                PlantIllustration(archetype: .trailing, mood: .ok, pot: .at(allPlants.count)).frame(width: 170)
            }
            Text("Une nouvelle coloc ?").font(.brico(30, .heavy)).tracking(-0.5)
            Text("Prends-la en photo, feuilles bien visibles. Je m'occupe de la reconnaître.")
                .font(.brico(15)).foregroundStyle(Color.muted).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            if !settings.hasAPIKey {
                NavigationLink { SettingsView() } label: {
                    Text("🔑 Ajoute d'abord ta clé API Anthropic dans les réglages pour que je puisse reconnaître la plante.")
                        .font(.brico(13.5, .semibold)).multilineTextAlignment(.leading)
                        .card(.sand)
                }
                .buttonStyle(.plain)
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("📷 Prendre une photo") { showCamera = true }
                    .buttonStyle(PillButtonStyle(kind: .fill))
                    .disabled(!settings.hasAPIKey)
                    .opacity(settings.hasAPIKey ? 1 : 0.4)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text("🖼️ Choisir dans la galerie")
            }
            .buttonStyle(PillButtonStyle(kind: UIImagePickerController.isSourceTypeAvailable(.camera) ? .outline : .fill))
            .disabled(!settings.hasAPIKey)
            .opacity(settings.hasAPIKey ? 1 : 0.4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var identifyingStep: some View {
        VStack(spacing: 18) {
            photoView(height: 300)
            if let error {
                Text(error).font(.brico(15, .semibold)).multilineTextAlignment(.center)
                Button("Réessayer") { if let image { start(with: image) } }.buttonStyle(PillButtonStyle(kind: .dark))
                Button("Écrire le nom moi-même") { showManual = true; step = .candidates }.buttonStyle(PillButtonStyle(kind: .outline))
            } else {
                ProgressView().controlSize(.large).tint(.ink)
                Text("Je regarde ça de près… 🔍").font(.brico(18, .bold))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var candidatesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                photoView(height: 170)
                if let id = identification, !id.isPlant || id.candidates.isEmpty {
                    Text("Hmm, je ne reconnais pas de plante 🤔").font(.brico(22, .heavy)).padding(.top, 8)
                    Text("Reprends une photo, ou écris son nom.").font(.brico(14)).foregroundStyle(Color.muted)
                } else if !(identification?.candidates.isEmpty ?? true) {
                    Text("Je pense que c'est…").font(.brico(24, .heavy)).padding(.top, 8)
                    Text("Compare avec les photos de référence. Touche une photo pour l'agrandir.")
                        .font(.brico(13)).foregroundStyle(Color.muted)
                    ForEach(identification?.candidates ?? []) { c in
                        CandidateRow(candidate: c, selected: selected == c) {
                            selected = c
                            showManual = false
                        }
                    }
                }

                if showManual {
                    TextField("Nom de la plante (ex. Ficus lyrata)", text: $manualName)
                        .font(.brico(16)).padding(14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                        .padding(.top, 6)
                } else {
                    Button("Aucune ? Écrire le nom") { showManual = true; selected = nil }
                        .font(.brico(14)).underline().foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity).padding(.top, 6)
                }

                Button("C'est elle !") { confirmSpecies() }
                    .buttonStyle(PillButtonStyle(kind: .fill))
                    .disabled(selected == nil && manualName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 10)
                Button("Reprendre une photo") { step = .source; image = nil }
                    .font(.brico(14)).foregroundStyle(Color.muted).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var detailsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(speciesName).font(.brico(30, .heavy)).tracking(-0.5)
                Text("Plus que quelques questions.").font(.brico(15)).foregroundStyle(Color.muted)

                label("Dernier arrosage", required: true)
                Segmented(options: LastWatered.allCases, selection: $lastWatered, label: \.label)

                label("Pièce")
                RoomPicker(room: $room, existing: Array(Set(allPlants.compactMap(\.room))).sorted())

                label("Lumière")
                FlowLayout(spacing: 6) {
                    ForEach(LightLevel.allCases, id: \.self) { l in
                        Chip(text: l.label, on: light == l) { light = light == l ? nil : l }
                    }
                }

                label("Dernier rempotage")
                Segmented(options: Repot.allCases, selection: $repot, label: \.label)

                if let error {
                    Text(error).font(.brico(14, .semibold)).foregroundStyle(Color.vermillon).padding(.top, 10)
                }

                Button("Ajouter à mes plantes") { create() }
                    .buttonStyle(PillButtonStyle(kind: .fill))
                    .padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            if let plant = created, let p = plant.profile {
                ScrollView {
                    VStack(spacing: 14) {
                        PlantIllustration(plant: plant, mood: .happy)
                            .frame(width: 230, height: 230)
                            .padding(.top, 20)
                        Text(p.intro)
                            .font(.brico(16, .bold))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 4, bottomTrailingRadius: 20, topTrailingRadius: 20))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            essential("💧 Arrosage", "\(Fmt.everyDays(CareEngine.baseInterval(p, season: Season.of(Date())))) (\(Season.of(Date()).label.lowercased()))")
                            essential("🚿 Quantité", p.watering.quantity)
                            essential("☀️ Lumière", p.light)
                            essential("🧪 Engrais", p.fertilizing.map { f in
                                let m = f.months.sorted()
                                return m.isEmpty ? "—" : "\(Fmt.monthName(m.first!).capitalizedFirst) → \(Fmt.monthName(m.last!))"
                            } ?? "Pas besoin")
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                Button("Bienvenue à la maison") { dismiss() }
                    .buttonStyle(PillButtonStyle(kind: .dark))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Petits morceaux

    @ViewBuilder
    private func photoView(height: CGFloat) -> some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(maxWidth: .infinity).frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func label(_ t: String, required: Bool = false) -> some View {
        (Text(t).font(.brico(14, .heavy)) + Text(required ? " *" : "  facultatif").font(.brico(12)).foregroundColor(.muted))
            .padding(.top, 16)
    }

    private func essential(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.brico(12))
            Text(value).font(.brico(14, .heavy)).lineLimit(3).minimumScaleFactor(0.85)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var speciesName: String {
        selected?.commonName ?? manualName.trimmingCharacters(in: .whitespaces).capitalizedFirst
    }

    // MARK: - Logique

    private func start(with img: UIImage) {
        image = img
        error = nil
        identification = nil
        selected = nil
        step = .identifying
        Task {
            do {
                guard let jpeg = ImageUtils.jpeg(img, maxSide: 1024, quality: 0.7) else { return }
                let id = try await PlantAI(settings: settings).identify(jpeg: jpeg)
                identification = id
                selected = id.candidates.first
                showManual = !id.isPlant || id.candidates.isEmpty
                step = .candidates
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func confirmSpecies() {
        let common: String, scientific: String
        if let s = selected {
            common = s.commonName; scientific = s.scientificName
        } else {
            common = manualName.trimmingCharacters(in: .whitespaces).capitalizedFirst; scientific = ""
        }
        let ai = PlantAI(settings: settings)
        profileTask?.cancel()
        profileTask = Task { try await ai.careProfile(commonName: common, scientificName: scientific.isEmpty ? "à déterminer" : scientific) }
        error = nil
        step = .details
    }

    private func create() {
        guard let task = profileTask else { return }
        creating = true
        error = nil
        Task {
            defer { creating = false }
            do {
                let profile = try await task.value
                let cal = Calendar.current
                let now = Date()
                let last = lastWatered.daysAgo.flatMap { cal.date(byAdding: .day, value: -$0, to: now) }
                let photo = image.flatMap { ImageUtils.jpeg($0, maxSide: 1600, quality: 0.8) }
                let plant = Plant(profile: profile, photo: photo, room: room, light: light,
                                  potStyleIndex: Plant.nextPotIndex(existing: allPlants), lastWateredAt: last, now: now)
                ctx.insert(plant)
                if let months = repot.monthsAgo, let d = cal.date(byAdding: .month, value: -months, to: now) {
                    plant.log(.repotting, date: d, in: ctx)
                }
                if let last { plant.log(.watering, date: last, in: ctx) }
                try? ctx.save()
                created = plant
                step = .welcome
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                // Relance au prochain essai.
                confirmSpeciesRetry()
            }
        }
    }

    private func confirmSpeciesRetry() {
        let ai = PlantAI(settings: settings)
        let common = speciesName
        let scientific = selected?.scientificName ?? "à déterminer"
        profileTask = Task { try await ai.careProfile(commonName: common, scientificName: scientific) }
    }

    private func cancel() {
        profileTask?.cancel()
        dismiss()
    }
}

/// Appareil photo (UIKit).
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPick(nil) }
    }
}

/// Une espèce proposée, avec des photos de référence pour comparer.
struct CandidateRow: View {
    let candidate: SpeciesCandidate
    let selected: Bool
    var onSelect: () -> Void

    @State private var photos: SpeciesPhotos?
    @State private var loading = true
    @State private var galleryIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.commonName).font(.brico(17, .heavy))
                        Text("\(candidate.scientificName) · \(candidate.confidenceLabel)").font(.brico(12.5)).italic().foregroundStyle(Color.muted)
                    }
                    Spacer()
                    Circle()
                        .strokeBorder(selected ? Color.vermillon : Color.ink, lineWidth: 2)
                        .background(Circle().fill(selected ? Color.vermillon : .clear).padding(5))
                        .frame(width: 24, height: 24)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if let photos {
                        ForEach(Array(photos.urls.enumerated()), id: \.offset) { i, url in
                            Button { galleryIndex = i } label: {
                                RemotePhoto(url: url).frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    } else if loading {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 14).fill(Color.cream).frame(width: 96, height: 96)
                                .overlay(ProgressView().tint(.muted))
                        }
                    } else {
                        Text("Pas de photo de référence trouvée.").font(.brico(12.5)).foregroundStyle(Color.muted)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? Color.ink : .clear, lineWidth: 3))
        .task {
            photos = await SpeciesPhotoService.shared.photos(scientificName: candidate.scientificName, commonName: candidate.commonName)
            loading = false
        }
        .fullScreenCover(item: Binding(get: { galleryIndex.map { GalleryIndex(value: $0) } }, set: { galleryIndex = $0?.value })) { idx in
            ReferenceGallery(title: candidate.commonName, photos: photos, start: idx.value) {
                galleryIndex = nil
                onSelect()
            }
        }
    }
}

struct GalleryIndex: Identifiable { let value: Int; var id: Int { value } }

struct RemotePhoto: View {
    let url: URL
    var fit = false
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                if fit { img.resizable().scaledToFit() } else { img.resizable().scaledToFill() }
            case .failure:
                Color.cream.overlay(Image(systemName: "leaf").foregroundStyle(Color.muted))
            default:
                Color.cream.overlay(ProgressView().tint(.muted))
            }
        }
    }
}

/// Photos de référence en grand, pour comparer avec sa plante.
struct ReferenceGallery: View {
    let title: String
    let photos: SpeciesPhotos?
    let start: Int
    var onChoose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(title).font(.brico(22, .heavy)).foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(.white.opacity(0.2), in: Circle())
                }
            }
            .padding(.horizontal, 20)
            TabView(selection: $page) {
                ForEach(Array((photos?.urls ?? []).enumerated()), id: \.offset) { i, url in
                    RemotePhoto(url: url, fit: true).tag(i).padding(.horizontal, 8)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Text(photos?.credit ?? "").font(.brico(11)).foregroundStyle(.white.opacity(0.6))
            Button("Choisir celle-ci", action: onChoose)
                .buttonStyle(PillButtonStyle(kind: .fill))
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
        .background(Color.ink.ignoresSafeArea())
        .onAppear { page = start }
    }
}

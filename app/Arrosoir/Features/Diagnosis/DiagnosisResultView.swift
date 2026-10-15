import SwiftUI
import SwiftData

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
                    HStack {
                        Text(plant.commonName).font(.brico(14, .bold))
                        Spacer()
                        Button { if let onDone { onDone() } else { dismiss() } } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.ink)
                                .frame(width: 32, height: 32).background(Color.white, in: Circle())
                        }
                        .accessibilityLabel("Fermer")
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 12)

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

                    if r.isAnswer, !diagnosis.note.isEmpty {
                        Text("« \(diagnosis.note) »").font(.brico(14)).italic().foregroundStyle(Color.muted).padding(.top, 12)
                    }

                    Sticker(text: r.plantSays).padding(.top, 12)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(r.isAnswer ? "Réponse" : severityLabel(r.severity)).font(.brico(12, .heavy)).tracking(1).textCase(.uppercase).opacity(0.85)
                        Text(r.title).font(.brico(22, .heavy))
                        Text(r.summary).font(.brico(14.5))
                    }
                    .foregroundStyle(r.isAnswer || r.severity != .ok ? Color.white : Color.ink)
                    .card(r.isAnswer ? .leafGreen : severityColor(r.severity))
                    .padding(.top, 14)

                    if !r.causes.isEmpty && !r.isAnswer {
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
                        SectionTitle(text: r.isAnswer ? "Bon à savoir" : "À faire")
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

                    if let days = r.followUpDays, days > 0, !r.isAnswer {
                        Text("🔁 Redemande au docteur dans ~\(days) jours pour voir si ça s'améliore.")
                            .font(.brico(13)).foregroundStyle(Color.muted).padding(.top, 14)
                    }

                    if !diagnosis.note.isEmpty && !r.isAnswer {
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
                .readable(640)
                .padding(.bottom, 30)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.cream.ignoresSafeArea())
        .fullScreenCover(isPresented: $showPhoto) { PhotoViewer(data: diagnosis.photo) }
    }

    private func mood(_ r: DiagnosisResult) -> Mood {
        if r.isAnswer { return .happy }
        switch r.severity {
        case .ok: return .happy
        case .watch: return .ok
        case .urgent: return .thirsty
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


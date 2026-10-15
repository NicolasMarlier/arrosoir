import SwiftUI
import SwiftData

struct LogCareSheet: View {
    let plant: Plant
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CareKind = .repotting
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Noter un soin").font(.brico(26, .heavy)).padding(.top, 24)
            FlowLayout(spacing: 6) {
                ForEach(CareKind.loggable) { k in
                    Chip(text: "\(k.emoji) \(k.label)", on: kind == k) { kind = k }
                }
            }
            DatePicker("Quand ?", selection: $date, in: ...Date(), displayedComponents: .date)
                .font(.brico(16, .bold))
                .environment(\.locale, Fmt.locale)
                .padding(.top, 6)
            Spacer()
            Button("Noter") {
                plant.log(kind, date: date, in: ctx)
                dismiss()
            }
            .buttonStyle(PillButtonStyle(kind: .dark))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(Color.cream.ignoresSafeArea())
    }
}

struct EditPlantSheet: View {
    @Bindable var plant: Plant
    let rooms: [String]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var room: String?
    @State private var light: LightLevel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Modifier").font(.brico(26, .heavy)).padding(.top, 24)
                Text("Nom").font(.brico(13, .heavy)).padding(.top, 10)
                TextField("Nom", text: $name)
                    .font(.brico(16))
                    .padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                Text("Pièce").font(.brico(13, .heavy)).padding(.top, 10)
                RoomPicker(room: $room, existing: rooms)
                Text("Lumière").font(.brico(13, .heavy)).padding(.top, 10)
                FlowLayout(spacing: 6) {
                    ForEach(LightLevel.allCases, id: \.self) { l in
                        Chip(text: l.label, on: light == l) { light = light == l ? nil : l }
                    }
                }
                Text("La lumière sert à affiner la fiche : utilise « Régénérer la fiche » si tu la changes beaucoup.")
                    .font(.brico(12)).foregroundStyle(Color.muted)
                Button("Enregistrer") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { plant.commonName = n }
                    plant.room = room
                    plant.light = light
                    try? ctx.save()
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(kind: .dark))
                .padding(.top, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.cream.ignoresSafeArea())
        .onAppear {
            name = plant.commonName
            room = plant.room
            light = plant.light
        }
    }
}

struct GraveyardView: View {
    @Query(filter: #Predicate<Plant> { $0.archivedAt != nil }, sort: \Plant.archivedAt, order: .reverse) private var plants: [Plant]
    @Environment(\.modelContext) private var ctx

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Le jardin du souvenir").font(.brico(32, .heavy)).tracking(-0.8)
                Text("Elles ont fait de leur mieux.").font(.brico(15)).foregroundStyle(Color.muted)
                ForEach(plants) { p in
                    HStack(spacing: 12) {
                        PlantIllustration(plant: p, mood: p.archiveReason == .given ? .happy : .ghost)
                            .frame(width: 68, height: 68)
                            .background(p.archiveReason == .given ? p.potStyle.tintColor : Color(hex: 0xEFEAF3), in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.commonName).font(.brico(18, .heavy))
                            Text(dates(p)).font(.brico(12)).foregroundStyle(Color.muted)
                            Text((p.archiveReason == .given ? "🎁 " : "") + (p.epitaph ?? ""))
                                .font(.brico(13, .semibold))
                        }
                    }
                    .card()
                    .contextMenu {
                        Button("Elle est de retour !", systemImage: "arrow.uturn.backward") {
                            p.archivedAt = nil
                            p.archiveReasonRaw = nil
                            try? ctx.save()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color.cream)
    }

    private func dates(_ p: Plant) -> String {
        let f = DateFormatter()
        f.locale = Fmt.locale
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return "\(f.string(from: p.createdAt)) → \(p.archivedAt.map { f.string(from: $0) } ?? "")"
    }
}

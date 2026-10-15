import SwiftUI

struct Chip: View {
    let text: String
    let on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.brico(14, .bold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(on ? Color.white : Color.ink)
                .background(on ? Color.ink : Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Contrôle segmenté maison.
struct Segmented<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { o in
                let on = selection == o
                Button {
                    withAnimation(.snappy) { selection = o }
                } label: {
                    Text(label(o))
                        .font(.brico(13, .bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(on ? Color.white : Color.ink)
                        .background(on ? Color.ink : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white, in: Capsule())
    }
}

struct RoomPicker: View {
    @Binding var room: String?
    var existing: [String] = []
    @State private var custom = ""
    @State private var addingCustom = false

    private var options: [String] {
        var base = ["Salon", "Chambre", "Cuisine", "Bureau", "Salle de bain"]
        for r in existing where !base.contains(r) { base.append(r) }
        if let room, !base.contains(room) { base.append(room) }
        return base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(options, id: \.self) { o in
                    Chip(text: o, on: room == o) { withAnimation(.snappy) { room = room == o ? nil : o } }
                }
                Button {
                    addingCustom.toggle()
                } label: {
                    Text("+ Autre").font(.brico(14, .bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(Color.ink, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                }
                .buttonStyle(.plain)
            }
            if addingCustom {
                HStack {
                    TextField("Nom de la pièce", text: $custom)
                        .font(.brico(15))
                        .padding(10).background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .submitLabel(.done)
                        .onSubmit(commit)
                    Button("OK", action: commit).buttonStyle(PillButtonStyle(kind: .dark, compact: true))
                }
            }
        }
    }

    private func commit() {
        let t = custom.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { room = t.capitalizedFirst }
        custom = ""
        addingCustom = false
    }
}

/// Mise en page qui passe à la ligne (pour les pastilles).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += lineH + spacing; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += lineH + spacing; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

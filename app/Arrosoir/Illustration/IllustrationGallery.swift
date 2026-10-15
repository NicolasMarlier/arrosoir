import SwiftUI

/// Planche de contrôle de toutes les illustrations (lancer avec -gallery).
struct IllustrationGallery: View {
    var body: some View {
        ScrollView {
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(Array(PlantArchetype.allCases.enumerated()), id: \.offset) { i, a in
                    GridRow {
                        Text(a.rawValue).font(.brico(10, .bold)).frame(width: 60, alignment: .leading)
                        ForEach(Mood.allCases, id: \.self) { m in
                            PlantIllustration(archetype: a, mood: m, pot: .at(i))
                                .frame(width: 62, height: 62)
                                .background(PotStyle.at(i).tintColor, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(Color.cream)
    }
}

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

/// Aperçu des propositions d'espèces avec photos (lancer avec -candidatesDemo).
struct CandidatesDemo: View {
    @State private var selected: SpeciesCandidate?
    let list = [
        SpeciesCandidate(commonName: "Rose du désert", scientificName: "Adenium obesum", confidence: 0.85),
        SpeciesCandidate(commonName: "Frangipanier", scientificName: "Plumeria rubra", confidence: 0.1),
        SpeciesCandidate(commonName: "Pachypodium", scientificName: "Pachypodium lamerei", confidence: 0.05),
    ]
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(list) { c in CandidateRow(candidate: c, selected: selected == c) { selected = c } }
            }
            .padding(20)
        }
        .background(Color.cream)
    }
}

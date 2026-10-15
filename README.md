# 🪴 Arrosoir

App iOS perso pour savoir quand arroser (et soigner) ses plantes d'intérieur.
Direction artistique « Papiers découpés × La Coloc » : chaque plante est un petit personnage dont l'humeur change (en forme, soif, dodo, juste arrosée).

## Contenu du dossier

| Fichier | Rôle |
|---|---|
| `SPEC.md` | Décisions produit (V1 / V2 / hors scope) |
| `questions*.html`, `maquettes-v1.html`, `identite-v*.html` | Grill produit, wireframes, recherche d'identité |
| `design/icon.svg` | Source de l'icône (rendu 1024 px dans `design/icon-1024.png`) |
| `app/` | Le projet Xcode (SwiftUI, iOS 18+) |

## Lancer l'app

```bash
cd app
xcodegen generate        # régénère Arrosoir.xcodeproj depuis project.yml (brew install xcodegen)
open Arrosoir.xcodeproj
```

Dans Xcode : choisir ton iPhone (branché ou en Wi-Fi) → ▶︎. La signature est automatique avec l'équipe `ZBL8NZ2ZE7`.
Au premier lancement : **Mes plantes → ⚙️ → Clé API Anthropic** (stockée dans le trousseau), puis **+** pour ajouter une plante en photo.

Arguments de lancement utiles (Scheme → Run → Arguments) :
- `-demo` : ajoute 6 plantes d'exemple si la base est vide
- `-inMemory` : base éphémère
- `-plantsTab`, `-open "Monstera"`, `-add` : ouvrir directement un écran
- `-gallery` : planche de toutes les illustrations × humeurs

Tests : `xcodebuild test -project app/Arrosoir.xcodeproj -scheme Arrosoir -destination 'platform=iOS Simulator,name=iPhone 17'`

## Architecture

```
app/Arrosoir/
  App/            point d'entrée, barre d'onglets
  Model/          Plant, CareEvent (SwiftData), CareProfile (fiche générée par Claude)
  Engine/         CareEngine (calcul pur et testé : statut, saisons, dormance, apprentissage), actions, formatage FR
  Illustration/   plantes dessinées en Canvas (11 familles × 5 humeurs), visage « yeux découpés »
  Services/       client API Anthropic, PlantAI (identification, fiche, épitaphe), trousseau, filet de sécurité
  Features/       Today (À faire), Plants, Detail, Add (parcours photo), Settings
  Content/        petites phrases des plantes, données de démo
```

### Logique d'arrosage
- Intervalle = base de l'espèce **par saison** (fiche Claude) × facteur appris × réglette manuelle. En dormance, au moins le rythme d'hiver.
- Échéance atteinte → « Vérifier » ; retard ≥ 30 % → « Arroser ».
- « Encore humide » : repousse de ~25 % de l'intervalle (1 à 10 j) et allonge le rythme de 12 %.
- « Arrosé » sans report préalable : resserre le rythme de 3 % (l'app explore doucement, tes « encore humide » la recalent).
- Brumisation, rotation, engrais (en saison) apparaissent dans « À faire » ; rempotage et taille restent « À l'horizon » sur la fiche.

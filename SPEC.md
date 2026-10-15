# Arrosoir — Spec produit (v0.4, DA choisie)

App iOS perso (SwiftUI) pour savoir quand arroser / soigner ses plantes d'intérieur. 3 à 10 plantes. Paris, appartement, plantes fixes.

## Principes
- Usage : on ouvre l'app tous les quelques jours → elle montre **ce qu'il y a à faire**.
- Ton chaleureux et ludique, adulte. Les plantes « parlent » avec parcimonie. Pas de séries ni de badges.
- Français (structure prête pour l'i18n). Données locales (SwiftData). Clé Anthropic dans les réglages.

## V1
- **Ajout uniquement par photo** → Claude identifie (avec des alternatives si doute) → confirmation → fiche générée et stockée.
  - Champs facultatifs : pièce, exposition. Obligatoire : date approximative du dernier arrosage. Pas de surnom.
- **Fiche d'entretien** (générée par le LLM) : intervalle de base par saison, quantité indicative (qualitative), méthode (dessus / soucoupe / trempage, type d'eau), dormance, soins.
- **Recommandation** = espèce × saison (Paris), avec un intervalle corrigeable à la main (réglette).
- **Apprentissage** : boutons « Arrosé » / « Encore humide » → l'intervalle s'ajuste automatiquement.
- **Dormance** affichée explicitement (« en repos jusqu'en mars »).
- **Soins** : arrosage, brumisation, rotation, engrais, rempotage, taille, nettoyage. Tous à la fois journalisés et rappelés, avec deux échelles :
  - court terme (arrosage, brumisation, rotation, engrais) → apparaissent dans « À faire » ;
  - long terme (rempotage, taille…) → indications douces sur la fiche (« rempotée il y a plus de 2 ans, à prévoir au printemps »), jamais de rappel insistant.
- **Écrans** : « À faire » (accueil) / « Mes plantes » (vue d'ensemble, regroupée par pièce) / fiche plante / ajout / archives. Navigation : 2 onglets + bouton « + » central.
- « Encore humide » : l'app décide seule du report (pas de question).
- Ajout : photo uniquement ; saisie du nom seulement en recours si l'identification échoue.
- Fiche plante : afficher le **dernier** arrosage (pas d'historique complet).
- Bouton « tout arroser ».
- Fin de vie → archivage (« cimetière », ton léger).
- Notifications : aucune par défaut (on ouvre l'app soi-même). Option : filet de sécurité si une plante est très en retard.
- Visuels : **illustrations** dont l'état change (en forme, soif, repos, juste arrosée) ; la vraie photo reste sur la fiche.
- **Direction artistique** : « Papiers découpés » (aplats sans contour, crème / nuit / vermillon / moutarde / cobalt / vert / rose, Bricolage Grotesque) + **visages sur les pots** (inspirés de « La Coloc »). Pas de mode sombre.
- « Mes plantes » groupé par pièce.

## V2
- Photos de suivi analysées par Claude (lumière, santé, conseils), historique photo.
- Mode vacances.
- Partage avec une autre personne (nécessitera un backend).
- Facteurs avancés : pot, lumière, météo.
- Proxy serveur pour la clé API si l'app est ouverte au public.

## Hors scope
Widget, Apple Watch, Siri, mesure de la quantité d'eau, ajout manuel sans photo, surnoms.

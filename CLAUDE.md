# Arrosoir — consignes pour l'agent

## « Il y a eu un problème » → Sentry
Quand Nicolas signale un bug (réponse illisible, crash, écran bizarre…), sans forcément de détail :
1. `scripts/sentry-issues.sh` → issues non résolues (14 derniers jours). Repérer la plus récente / celle qui correspond.
2. `scripts/sentry-issues.sh <id>` → détail : tags (`feature`, `ai.model`, `ai.error`), extras (`stop_reason`, `usage`, `user_message`), fil d'Ariane, et pièces jointes (`claude-response.json` = réponse brute de Claude, `tool-input.json`). Un « Retour utilisateur » (tag `feature: user_feedback`) contient son message.
3. Corriger dans un **worktree séparé** (`git worktree add -b fix/<sujet> ../arrosoir-<sujet>`), ajouter un test si c'est du décodage (cf. `ArrosoirTests`, réponses brutes de Sentry comme fixtures), `xcodebuild test`.
4. Rebase sur `main`, merge `--ff-only`, push, supprimer le worktree et la branche.
5. Résoudre l'issue : `curl -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"status":"resolved"}' https://de.sentry.io/api/0/organizations/nicolas-marlier/issues/<id>/` (jeton dans `~/.sentryclirc`).

Config : org `nicolas-marlier`, projet `arrosoir`, région UE (`de.sentry.io`). DSN dans `app/Config/Secrets.xcconfig` (non versionné, à copier dans tout nouveau worktree avant de builder). Le repo GitHub est **public** : jamais de DSN ni de jeton dans un commit.

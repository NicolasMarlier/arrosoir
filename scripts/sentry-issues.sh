#!/usr/bin/env bash
# Récupère les bugs remontés par l'app depuis Sentry (pour les lire / les corriger depuis le terminal).
#   scripts/sentry-issues.sh                → liste des issues non résolues
#   scripts/sentry-issues.sh <issue-id>     → dernier événement complet + pièces jointes (réponse brute de Claude…)
# Config : SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT (env, ou lus dans app/Config/Secrets.xcconfig / ~/.sentryclirc).
set -euo pipefail
cd "$(dirname "$0")/.."

cfg() { grep -E "^[[:space:]]*$1[[:space:]]*=" app/Config/Secrets.xcconfig 2>/dev/null | head -1 | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]+$//; s/\$\(\)//g'; }
SENTRY_ORG="${SENTRY_ORG:-$(cfg SENTRY_ORG)}"
SENTRY_PROJECT="${SENTRY_PROJECT:-$(cfg SENTRY_PROJECT)}"
SENTRY_URL="${SENTRY_URL:-$(cfg SENTRY_URL)}"; SENTRY_URL="${SENTRY_URL:-https://sentry.io}"
if [ -z "${SENTRY_AUTH_TOKEN:-}" ] && [ -f ~/.sentryclirc ]; then
  SENTRY_AUTH_TOKEN="$(grep -E '^token' ~/.sentryclirc | sed -E 's/^token[[:space:]]*=[[:space:]]*//')"
fi
: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN manquant}" "${SENTRY_ORG:?SENTRY_ORG manquant}" "${SENTRY_PROJECT:?SENTRY_PROJECT manquant}"

api() { curl -fsSL -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "$SENTRY_URL/api/0/$1"; }

if [ $# -eq 0 ]; then
  api "projects/$SENTRY_ORG/$SENTRY_PROJECT/issues/?query=is:unresolved&statsPeriod=14d" | python3 -c '
import json, sys
for i in json.load(sys.stdin):
    t = i.get("metadata", {}).get("value") or i["title"]
    print(f"{i[\"id\"]:>12}  {i[\"level\"]:<7} x{i[\"count\"]:<4} {i[\"lastSeen\"][:16]}  [{i.get(\"culprit\") or \"\"}] {t}")'
  exit 0
fi

ISSUE="$1"
EVENT=$(api "organizations/$SENTRY_ORG/issues/$ISSUE/events/latest/")
echo "$EVENT" | python3 -c '
import json, sys
e = json.load(sys.stdin)
print("#", e.get("title"))
print("Date :", e.get("dateCreated"), "| release :", (e.get("release") or {}).get("version"))
print("Tags :", {t["key"]: t["value"] for t in e.get("tags", [])})
ctx = e.get("context") or {}
if ctx: print("Extra :", json.dumps(ctx, ensure_ascii=False, indent=2))
for entry in e.get("entries", []):
    if entry["type"] == "exception":
        for v in entry["data"]["values"]:
            print("\nException :", v.get("type"), "-", v.get("value"))
            for f in (v.get("stacktrace") or {}).get("frames", [])[-15:]:
                if f.get("inApp"): print("   ", f.get("function"), f.get("filename"), f.get("lineNo"))
    if entry["type"] == "breadcrumbs":
        print("\nFil d’Ariane :")
        for b in entry["data"]["values"][-25:]:
            print("   ", (b.get("timestamp") or "")[11:19], b.get("category"), "-", b.get("message") or "", b.get("data") or "")
'
EVENT_ID=$(echo "$EVENT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["eventID"])')
api "projects/$SENTRY_ORG/$SENTRY_PROJECT/events/$EVENT_ID/attachments/" | python3 -c 'import json,sys; [print(a["id"], a["name"]) for a in json.load(sys.stdin)]' |
while read -r id name; do
  echo; echo "── Pièce jointe : $name"
  api "projects/$SENTRY_ORG/$SENTRY_PROJECT/events/$EVENT_ID/attachments/$id/?download=1" | head -c 20000; echo
done

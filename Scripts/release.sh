#!/bin/bash
# Publie une nouvelle version : Scripts/release.sh 1.1.0
# Met à jour VERSION, valide, crée l'étiquette v1.1.0 et la pousse : GitHub Actions compile, signe et publie la release.
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -eq 1 ] || { echo "Usage : Scripts/release.sh X.Y.Z"; exit 1; }
V="$1"
echo "$V" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}$' || { echo "Version invalide : $V (attendu : 1.2.0)"; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "Des changements ne sont pas validés (git commit) : faites-le d'abord."; exit 1; }
echo "$V" > VERSION
git add VERSION
git commit -m "Version $V" --allow-empty
git tag "v$V"
git push origin HEAD "v$V"
echo "→ v$V poussée. Suivez la publication dans l'onglet Actions du dépôt ; les utilisateurs recevront la mise à jour dès que la release est publiée."

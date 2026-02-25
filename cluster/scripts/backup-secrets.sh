#!/usr/bin/env bash
# backup-secrets.sh — Talos + SOPS Age Secrets verschlüsselt sichern
#
# Erzeugt ein passphrase-verschlüsseltes Archiv aller lokalen Secrets.
# Kein age.key nötig zum Entschlüsseln — nur die Passphrase.
#
# Ausführen aus dem Repo-Root:
#   bash cluster/scripts/backup-secrets.sh
#   bash cluster/scripts/backup-secrets.sh ~/usb-stick/
#
# Wiederherstellen:
#   age -d talos-backup-YYYYMMDD.tar.gz.age | tar xzf -

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTDIR="${1:-$HOME}"
OUTFILE="${OUTDIR}/talos-backup-$(date +%Y%m%d).tar.gz.age"

# --- Prüfen ob age installiert ist ---
if ! command -v age &>/dev/null; then
  echo "ERROR: 'age' nicht gefunden. Installation: https://github.com/FiloSottile/age"
  exit 1
fi

cd "$REPO_ROOT"

# --- Dateien prüfen ---
MISSING=()
[[ -f cluster/talsecret.yaml           ]] || MISSING+=("cluster/talsecret.yaml")
[[ -d cluster/clusterconfig            ]] || MISSING+=("cluster/clusterconfig/")
[[ -f age.key                          ]] || MISSING+=("age.key")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "WARNUNG: Folgende Dateien fehlen und werden übersprungen:"
  printf '  - %s\n' "${MISSING[@]}"
  echo ""
fi

# --- Backup erstellen ---
echo "Erstelle verschlüsseltes Backup: $OUTFILE"
echo "(Bitte eine starke Passphrase wählen und sicher aufbewahren!)"
echo ""

tar czf - \
  --ignore-failed-read \
  $([ -f cluster/talsecret.yaml ] && echo "cluster/talsecret.yaml") \
  $([ -d cluster/clusterconfig  ] && echo "cluster/clusterconfig/") \
  $([ -f age.key                ] && echo "age.key") \
  | age -p -o "$OUTFILE"

echo ""
echo "Backup gespeichert: $OUTFILE"
echo ""
echo "Nächste Schritte:"
echo "  1. Datei an sicheren Ort kopieren (Bitwarden, USB, NAS, ...)"
echo "  2. Passphrase im Passwort-Manager speichern"
echo ""
echo "Wiederherstellen:"
echo "  age -d $OUTFILE | tar xzf -"

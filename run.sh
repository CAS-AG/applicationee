#!/usr/bin/env bash
set -euo pipefail

# Bewerbungs-Pipeline starten: interaktive Claude-Code-Session im Container, mit dem
# eigenen Arbeitsordner (z. B. im lokalen OneDrive) als /workspace gemountet.
#
# Nutzung:
#   ./run.sh <Pfad-zum-Arbeitsordner> [Image]
#
# Beispiel (macOS):
#   ./run.sh "$HOME/Library/CloudStorage/OneDrive-CASAG/Bewerbungen"
#
# Der Arbeitsordner sollte eine ausgefuellte Master-Profil.md enthalten (Vorlage:
# Master-Profil.template.md im Image, siehe README). Zugangsdaten kommen aus
# .env.local (siehe .env.local.example) im selben Verzeichnis wie dieses Script.
#
# Windows: dieses Script braucht Bash (Git Bash oder WSL). Ein reiner
# PowerShell/CMD-Aufruf ohne run.sh steht im README.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${1:?Nutzung: ./run.sh <Pfad-zum-Arbeitsordner> [Image]}"
IMAGE="${2:-ghcr.io/<owner>/bewerbungs-pipeline:latest}"
ENV_FILE="$SCRIPT_DIR/.env.local"

if [ ! -f "$ENV_FILE" ]; then
  echo "Fehlt: $ENV_FILE (siehe .env.local.example) -- Zugangsdaten fehlen." >&2
  exit 1
fi

mkdir -p "$WORKSPACE"

# Auf /workspace/daten mounten, NICHT auf /workspace selbst -- sonst wuerde der
# Bind-Mount den im Image eingebauten Skill verdecken. Master-Profil.md und alle
# generierten Job-Ordner landen entsprechend unter daten/.
docker run -it --rm \
  -v "$WORKSPACE:/workspace/daten" \
  --env-file "$ENV_FILE" \
  "$IMAGE"

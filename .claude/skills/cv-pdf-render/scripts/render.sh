#!/usr/bin/env bash
# Rendert eine Markdown-Datei per pandoc/latex-Docker-Image (xelatex) zu PDF.
# Läuft auf dem Host (Mac mit Rancher Desktop), NICHT im Bewerbungs-Pipeline-Container.
#
# Aufruf (Pfade relativ zum aktuellen Verzeichnis oder absolut):
#   .claude/skills/cv-pdf-render/scripts/render.sh <input.md> <output.pdf>
#
# Input und Output müssen im selben Ordnerbaum liegen; gemountet wird das
# gemeinsame Elternverzeichnis von Input und Output.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: render.sh <input.md> <output.pdf>" >&2
  exit 1
fi

in_abs="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
out_dir="$(mkdir -p "$(dirname "$2")" && cd "$(dirname "$2")" && pwd)"
out_abs="$out_dir/$(basename "$2")"

# Gemeinsames Elternverzeichnis bestimmen
root="$out_dir"
while [ "${in_abs#"$root"/}" = "$in_abs" ]; do root="$(dirname "$root")"; done

if ! docker info >/dev/null 2>&1; then
  echo "Docker läuft nicht (Rancher Desktop starten)." >&2
  exit 2
fi

# pandoc/latex hat kein arm64-Manifest -> amd64-Emulation erzwingen.
docker run --rm --platform linux/amd64 \
  -v "$root":/data -w /data \
  pandoc/latex:latest \
  "${in_abs#"$root"/}" --pdf-engine=xelatex -o "${out_abs#"$root"/}" 2>&1 \
  | grep -v 'Ticker: poll failed' || true

[ -s "$out_abs" ] || { echo "PDF wurde nicht erzeugt: $out_abs" >&2; exit 3; }
echo "OK: $out_abs"

# Bewerbungs-Pipeline: Claude Code + Chromium (fuer PDF-Rendering) in einem Image.
# Kein separater PDF-Sidecar mehr noetig -- Chromium laeuft nativ in diesem
# Linux-Container (das Mac-Host-Sandbox-Problem, das den alten docker-compose-Sidecar
# noetig machte, existiert hier nicht).
FROM node:22-bookworm-slim

# Chromium-Laufzeit-Abhaengigkeiten + Werkzeuge fuer den Claude-Code-Installer.
# "chromium" (Debians eigenes Paket) statt Chrome-for-Testing/@puppeteer/browsers:
# Google veroeffentlicht Chrome for Testing nicht nativ fuer Linux-arm64 -- ein
# ueber @puppeteer/browsers heruntergeladenes "chrome@stable" ist auf arm64 in
# Wahrheit ein x64-Build, der ohne Rosetta/QEMU im Container nicht startet.
# Debians chromium-Paket ist dagegen fuer jede Zielarchitektur nativ verfuegbar.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    bash \
    gnupg \
    git \
    chromium \
    fonts-liberation \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Nicht-root-Nutzer fuer alles Weitere (Claude-Code-Install, npm, Laufzeit).
RUN useradd --create-home --shell /bin/bash appuser \
    && mkdir -p /workspace \
    && chown -R appuser:appuser /workspace

USER appuser
ENV HOME=/home/appuser
WORKDIR /home/appuser

# Claude Code CLI, nativer Installer (empfohlener Weg laut offizieller Doku).
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/appuser/.local/bin:${PATH}"

WORKDIR /workspace

# Node-Abhaengigkeiten der Pipeline-Skripte (xlsx, puppeteer-core). puppeteer-core
# braucht keinen eigenen Chromium-Download -- render-pdf.mjs zeigt auf das apt-Paket
# unter /usr/bin/chromium (siehe oben).
COPY --chown=appuser:appuser package.json package-lock.json* ./
RUN npm ci --omit=dev

# Skill-Dateien (Scripts + HTML-Templates + SKILL.md). Bewusst NICHT kopiert:
# Master-Profil.md, generierte Job-Ordner, .git -- die bleiben ausserhalb des Images,
# siehe .dockerignore und README.
COPY --chown=appuser:appuser .claude/skills/bewerbungs-pipeline/ .claude/skills/bewerbungs-pipeline/

# WICHTIG: Nutzdaten werden zur Laufzeit auf /workspace/daten gemountet, NICHT auf
# /workspace selbst -- sonst wuerde der Bind-Mount den hier eingebauten Skill
# (.claude/skills/..., node_modules) komplett verdecken. /workspace/daten existiert
# schon jetzt mit passenden Rechten, falls ohne -v getestet wird.
RUN mkdir -p /workspace/daten && chown -R appuser:appuser /workspace/daten

# docker run -it <image>            -> interaktive Claude-Code-Session in /workspace
# docker run -it <image> bash       -> Shell zum Debuggen
CMD ["claude"]

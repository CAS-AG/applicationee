# Bewerbungen

Ein Docker-Image mit Claude Code und eingebauten Skills, die aus einem
persönlichen Profil und Stellenanzeigen automatisiert zugeschnittene CVs und
Anschreiben erzeugt. Läuft komplett im Container — kein lokales Setup außer Docker
nötig, funktioniert für jeden mit eigenem Profil und eigenem Claude-Code-Zugang.

## Struktur (dieses Entwicklungs-Repo)

```
Dockerfile                    Image: Node + Chromium + Claude Code CLI in einem.
.dockerignore                 Schliesst persoenliche/generierte Dateien vom Image aus.
.github/workflows/            GitHub Actions: baut das Image und pusht es nach GHCR.
package.json                  Node-Dependencies der Pipeline-Skripte (xlsx, puppeteer-core).
run.sh                        Wrapper um `docker run` (Mount + Zugangsdaten).
.env.local.example            Vorlage fuer Zugangsdaten (CLAUDE_CODE_OAUTH_TOKEN / ANTHROPIC_API_KEY).
Master-Profil.md              Das eigene Profil. Es kann selbst geschrieben werden und/oder mit Hilfe von KI aus dem Master Profil pdf erstellt werden. Es liegt (s.u.) ein Template hierfür vor.

.claude/skills/
  bewerbungs-pipeline/         Der Skill selbst -- wird 1:1 ins Image kopiert.
    SKILL.md                  Ablauflogik und Konventionen.
    Master-Profil.template.md Leere Profil-Vorlage fuer andere Nutzer (im Image enthalten).
    scripts/
      parse-excel.mjs         Excel mit Job-Links einlesen (optional).
      render-pdf.mjs          HTML -> PDF (A4, 2 cm Rand) per Chromium.
    templates/
      cv-template.html        CV-Vorlage mit {{Platzhaltern}}.
      anschreiben-template.html Anschreiben-Vorlage, gleiches Design.

<Firma> – <Jobtitel>/         Pro Bewerbung ein Ordner, entsteht zur Laufzeit in
                               /workspace/daten (siehe unten):
    Jobanzeige_<Datum>.md      Original-Anzeigentext + Quelle + Abrufdatum
    CV_<Name> - ....pdf        Zugeschnittenes CV
    Anschreiben_<Name> - ....pdf Zugeschnittenes Anschreiben
    _quellen/                  HTML-Arbeitsdateien der beiden Dokumente
```

## Image nutzen

Voraussetzung: Docker (Docker Desktop) läuft lokal.

1. Zugang einrichten — `.env.local.example` nach `.env.local` kopieren und
   eine der beiden Variablen setzen:
   - `CLAUDE_CODE_OAUTH_TOKEN` — für ein eigenes Claude.ai-Abo (Pro/Max/Team/
     Enterprise). Einmalig erzeugen:
     ```
     docker run -it --rm ghcr.io/<owner>/bewerbungs-pipeline:latest claude setup-token
     ```
     Link im Browser öffnen/bestätigen, ausgegebenes Token in `.env.local`
     eintragen (gültig ca. 1 Jahr).
   - `ANTHROPIC_API_KEY` — falls stattdessen ein Anthropic-Console-/API-Zugang
     verwendet wird.
2. Eigenes Profil anlegen — irgendwo ein Arbeitsverzeichnis anlegen (siehe
   OneDrive-Beispiele unten), `Master-Profil.template.md` hineinkopieren, in
   `Master-Profil.md` umbenennen und mit echten Daten befüllen (am einfachsten:
   Claude Code im Container starten und gemeinsam ausfüllen).
3. **Starten:**
   ```
   ./run.sh "<Pfad-zum-Arbeitsordner>"
   ```
   Das öffnet eine interaktive Claude-Code-Session im Container. Danach z. B.:
   „Erstelle CV und Anschreiben für <Job-URL oder eingefügter Anzeigentext>."

### Ohne `run.sh` (z. B. Windows PowerShell)

```powershell
docker run -it --rm `
  -v "C:\Users\<user>\OneDrive - CAS AG\Bewerbungen:/workspace/daten" `
  --env-file .env.local `
  ghcr.io/<owner>/bewerbungs-pipeline:latest
```

(Auf `/workspace/daten` mounten, nicht auf `/workspace` selbst — sonst wird der im
Image eingebaute Skill überdeckt.)

## Ausgabe → OneDrive

Der Arbeitsordner (Mount-Ziel `/workspace/daten` — bewusst nicht `/workspace` selbst,
siehe unten) sollte direkt im lokal synchronisierten
OneDrive-Ordner liegen — dann tauchen alle generierten Dateien automatisch im
OneDrive des jeweiligen Nutzers auf, ganz ohne zusätzliche Cloud-Anbindung im
Container. Beispielpfade:

- **macOS:** `~/Library/CloudStorage/OneDrive-CASAG/Bewerbungen`
- **Windows:** `C:\Users\<user>\OneDrive - CAS AG\Bewerbungen` (Leerzeichen im
  Namen beachten, in Anführungszeichen setzen)

Der Arbeitsordner selbst ist **kein Git-Repo** — nur reine Nutzdaten (eigenes
`Master-Profil.md` + generierte Job-Ordner). Dieses Entwicklungs-Repo mit
Dockerfile/Skill bleibt davon getrennt.

## Für Kollegen: eigene Instanz nutzen

Kollegen brauchen keinen Checkout dieses Repos — nur:

1. Docker installiert
2. Das Image: `docker pull ghcr.io/<owner>/bewerbungs-pipeline:latest`
3. Einen eigenen Zugang (Token oder API-Key, siehe oben)
4. Ihr eigenes `Master-Profil.md` (aus `Master-Profil.template.md` im Image, per
   `docker run -it --rm ghcr.io/<owner>/bewerbungs-pipeline:latest cat
   .claude/skills/bewerbungs-pipeline/Master-Profil.template.md > Master-Profil.md`
   oder direkt interaktiv im Container ausfüllen)
5. `run.sh` (oder den PowerShell-Einzeiler oben) mit dem eigenen Arbeitsordner

Jede Instanz ist vollständig unabhängig — kein gemeinsamer Zustand, keine
gemeinsamen Dateien zwischen Kollegen.

## Image bauen und veröffentlichen (Maintainer)

Push auf `main` (bei Änderungen an `Dockerfile`, Skill oder Workflow-Datei) löst
automatisch `.github/workflows/build-and-push.yml` aus: baut multi-arch
(amd64 + arm64) und pusht nach `ghcr.io/<owner>/bewerbungs-pipeline:latest`.

Lokal bauen/testen ohne CI:
```
docker build -t bewerbungs-pipeline:dev .
./run.sh "<Testordner>" bewerbungs-pipeline:dev
```

## Warum kein separater PDF-Container mehr

Früher lief PDF-Rendering über einen verschachtelten Docker-Sidecar, weil headless
Chromium auf einem bestimmten Mac beim Prozessstart zuverlässig abstürzte
(vermutlich eine Code-Signing-/Sandbox-Eigenheit dieses einen Hosts). Jetzt laufen
Claude Code und Chromium im selben Linux-Container — das Problem trat dort nie
auf, ein Sidecar ist überflüssig geworden.

## Vertraulichkeit

`CAS AG_Beraterprofil_Stefan Bollmann.pdf` (falls lokal vorhanden) ist laut eigenem
Vermerk vertraulich und nicht für Weitergabe an Dritte bestimmt — es ist bewusst in
`.gitignore`/`.dockerignore` und wird weder versioniert noch ins Image kopiert. Die
relevanten Inhalte stehen bereits aufbereitet in `Master-Profil.md`. Ebenso landen
`.env.local` (Zugangsdaten) und alle generierten `<Firma> – <Jobtitel>/`-Ordner nie
im Image oder im Git-Repo.

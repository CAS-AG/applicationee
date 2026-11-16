---
name: bewerbungs-pipeline
description: Verarbeitet eine Excel-Liste mit Job-Links zu fertigen Bewerbungsunterlagen — legt pro Job einen neuen Ordner an, speichert den Anzeigentext mit Abrufdatum, und erzeugt ein zugeschnittenes CV plus Anschreiben als PDF. Benutzen, wenn Stefan eine Excel/CSV mit Stellenanzeigen-Links gibt und daraus automatisiert Bewerbungsmappen erstellt werden sollen (z.B. "verarbeite die Jobliste", "erstelle Bewerbungen aus dieser Excel", "Bewerbungs-Pipeline starten").
---

# Bewerbungs-Pipeline

Erzeugt aus einer Excel-Liste von Job-Links pro Zeile einen eigenen Bewerbungsordner
mit drei Artefakten: der Original-Anzeigentext, ein auf die Stelle zugeschnittenes CV
(PDF) und ein Anschreiben (PDF). Basiert auf dem Design und der Docker-basierten
PDF-Rendering-Lösung, die für die Constaff-Bewerbung (Senior API & Integration
Engineer) entwickelt wurde.

**Diese Pipeline verschickt nichts.** Sie erzeugt ausschließlich Entwurfsdokumente im
Projektordner. Das tatsächliche Absenden/Hochladen bleibt immer ein manueller,
bewusster Schritt von Stefan.

## Voraussetzungen

Dieser Skill läuft innerhalb des Bewerbungs-Pipeline-Docker-Containers (Claude Code
und Chromium sind dort bereits im selben Image installiert — kein separater
PDF-Rendering-Container mehr nötig). Das Arbeitsverzeichnis im Container ist
`/workspace` und enthält:

- `.claude/skills/bewerbungs-pipeline/` — Scripts und Templates, bereits im Image
  enthalten, keine Installation nötig. Alle `node .claude/skills/...`-Aufrufe in
  dieser Anleitung beziehen sich auf diesen (festen) Pfad.
- `daten/` — **alle Nutzdaten** (per Bind-Mount eingehängt, nicht Teil des Images):
  `Master-Profil.md`, generierte Job-Ordner, ggf. eine Excel-Jobliste. Bewusst ein
  eigenes Unterverzeichnis und nicht `/workspace` selbst, da ein Bind-Mount direkt
  auf `/workspace` den dort eingebauten Skill überdecken würde.

`Master-Profil.md` (unter `daten/Master-Profil.md`) ist die persönliche
Wahrheitsquelle des jeweiligen Nutzers. Existiert sie noch nicht, zuerst
`.claude/skills/bewerbungs-pipeline/Master-Profil.template.md` nach
`daten/Master-Profil.md` kopieren und mit dem Nutzer gemeinsam befüllen, bevor
irgendein CV erzeugt wird.

## Ablauf

### 0. Excel-Datei lokalisieren

Wenn der Nutzer keinen Pfad nennt, in `daten/` nach `.xlsx`/`.xls`-Dateien suchen und
nachfragen, welche gemeint ist, falls mehrdeutig.

### 1. Excel einlesen

```
node .claude/skills/bewerbungs-pipeline/scripts/parse-excel.mjs "daten/<Dateiname>.xlsx"
```

Das Skript erkennt zwei Layouts automatisch:

- **Hyperlink-Matrix** (der Normalfall bei Ressourcen-/Job-Tracker-Sheets à la
  "Ressourcenmanagement Stefan.xlsx": eine Zeile pro Plattform/Agentur, mehrere als
  Zellen-Hyperlink verlinkte Job-Titel in unregelmäßigen Spalten pro Zeile). Jede
  Zelle mit echtem Excel-Hyperlink wird ein Eintrag (`platform`, `title`, `url`).
  HTML-Entities in der URL (`&amp;` etc.) werden automatisch dekodiert.
- **Flache Liste** als Fallback, falls das Sheet keine Hyperlink-Zellen enthält:
  erste Zelle pro Zeile, deren Klartext wie eine URL aussieht.

Duplikate (identische URL) werden zusammengefasst.

**Danach immer erst die Liste sichten, bevor verarbeitet wird:** viele Zeilen sind
Portal-Wurzelseiten oder generische Bewerbungs-/Upload-Links, keine einzelnen
Stellenanzeigen (z. B. "Projektportal | Constaff GmbH" oder "Bewerbung: Lebenslauf
hochladen" bei Hays) — die klar an Titel/URL erkennbar generische bzw.
Portal-Startseiten sind, aussortieren. Ebenso Jobs, für die bereits ein Ordner/PDF
existiert, nicht erneut verarbeiten (siehe 2b).

Dem Nutzer die gefilterte Liste (Plattform, Titel, URL) kurz zeigen und **vor dem
Loslegen bestätigen lassen**, besonders wenn es mehr als ~8 echte Stellenanzeigen
sind oder Rollen dabei sind, die deutlich von Stefans Kernprofil abweichen (z. B.
reine Frontend-Rollen) — dort ggf. kurz einordnen, ob eine Bewerbung sinnvoll
erscheint, statt blind für jede Zeile Unterlagen zu erzeugen.

### 2. Pro Job-Zeile

Für jede Zeile mit gültiger URL:

**a) Anzeige abrufen**
Per WebFetch den vollständigen Anzeigentext holen: Jobtitel, Firma/Kunde, Ort,
Remote-Anteil, Start, Laufzeit/Befristung, Anforderungen (Muss/Kann getrennt),
Ansprechpartner falls genannt, sowie den Rohtext. Wenn der Abruf fehlschlägt (z.B.
Login nötig, 404), das für die Abschlussmeldung vormerken und zur nächsten Zeile
springen statt die ganze Pipeline abzubrechen.

**b) Ordner anlegen**
Ordnername: `<Firma> – <Jobtitel>` (Dateisystem-unschädlich gemacht: `/ \ : * ? " < > |`
durch `-` ersetzen). Liegt direkt in `daten/`.

Falls der Ordner schon existiert: nicht stillschweigend überschreiben — kurz beim
Nutzer nachfragen (erneut generieren vs. überspringen), es sei denn er hat das für den
Lauf schon pauschal geklärt.

Unterordner `_quellen/` darin für die HTML-Arbeitsdateien.

**c) Anzeigentext speichern**
Datei `Jobanzeige_<YYYY-MM-DD>.md` (Datum = heutiges Abrufdatum) im Job-Ordner, mit:
- Firma, Jobtitel, Quelle-URL, Abrufdatum
- Rahmendaten (Ort, Remote-Anteil, Start, Laufzeit) sofern vorhanden
- vollständiger Anzeigentext (Rohtext, nicht zusammengefasst)

**d) CV zuschneiden**
`daten/Master-Profil.md` lesen (kanonische Wahrheitsquelle — niemals Fähigkeiten
oder Erfahrungen erfinden, die dort nicht stehen). Existiert die Datei nicht, zuerst
Schritt "Voraussetzungen" oben nachholen (Template kopieren, mit dem Nutzer
befüllen), statt mit Platzhalterdaten weiterzumachen. Name und E-Mail für
`{{NAME}}`/`{{EMAIL}}` sowie alle Dateinamen (siehe 2f) immer aus dem Abschnitt
"Personendaten" von `daten/Master-Profil.md` übernehmen — nie hartkodieren.

Gegen die Anforderungen der aktuellen Anzeige abgleichen, dann
`.claude/skills/bewerbungs-pipeline/templates/cv-template.html` nach
`daten/<Jobordner>/_quellen/cv.html` kopieren und die `{{PLATZHALTER}}` befüllen:

- `{{ROLLE}}` / `{{ROLLE_KURZ}}`: an den Jobtitel angelehnter Rollentitel
- `{{VERFUEGBARKEIT}}`: Start/Laufzeit/Ort/Remote-Anteil aus der Anzeige
- `{{KURZPROFIL}}`: 3–5 Sätze, auf die Stelle zugeschnitten
- `{{KERNQUALIFIKATIONEN}}`: `<li>`-Liste, die konkret auf die Muss-Anforderungen der
  Anzeige einzahlt (siehe `.quals`-Markup im Template für die genaue Struktur)
- Tech-Stack-Lücken **ehrlich benennen** im `.callout`-Block (Muster: siehe
  `daten/Master-Profil.md`, Abschnitt AWS-Praxis, falls vorhanden — je nach Nutzer
  anderer Inhalt). Wenn es keine nennenswerte Lücke gibt, den gesamten
  `.callout`-Block aus der Kopie entfernen statt ihn leer zu lassen.
- `{{PROJEKTE}}`: 4–6 `.project`-Blöcke, relevanteste Projekte zuerst (Struktur wie im
  bestehenden Template-Kommentar), aus `daten/Master-Profil.md` → Abschnitt "Projekte"
- `{{WEITERE_PROJEKTE}}`: die übrigen Projekte knapp zusammengefasst (ein Absatz)
- `{{ZERTIFIZIERUNGEN}}` / `{{AUSBILDUNG}}` / `{{TECH_TABELLE}}`: aus
  `daten/Master-Profil.md`, nach Relevanz für diese Stelle vorsortiert bzw. gekürzt

Gleiches Vorgehen wie beim ursprünglichen Constaff-CV: kein Erfinden von Skills, Lücken
transparent machen, Reihenfolge nach Relevanz für genau diese Anzeige.

**e) Anschreiben verfassen**
`.claude/skills/bewerbungs-pipeline/templates/anschreiben-template.html` nach
`daten/<Jobordner>/_quellen/anschreiben.html` kopieren und befüllen:

- `{{ORT_DATUM}}`: aktuelles Datum (kein Ort, da Wohnort nicht im Profil — Format z.B.
  "25. August 2026")
- `{{FIRMA}}` / `{{ANSPRECHPARTNER}}` / `{{FIRMA_ADRESSE}}`: aus der Anzeige, wenn
  nicht bekannt, `{{ANSPRECHPARTNER}}` durch "Sehr geehrte Damen und Herren" in der
  `{{ANREDE}}` ersetzen und die leeren Zeilen im Template entfernen statt Platzhalter
  stehen zu lassen
- `{{BETREFF}}`: "Bewerbung als {Jobtitel}"
- `{{ABSATZ_1}}`–`{{ABSATZ_4}}`: konkret auf die Anzeige bezogen, keine Textbausteine
  von der Stange — Bezug zur Ausschreibung, 2–3 belegte Erfahrungen aus dem
  Master-Profil, ggf. ehrliches Wort zu einer Lücke plus Einarbeitungsbereitschaft,
  Verfügbarkeit/Rahmen, Abschluss mit Gesprächsangebot

**f) Rendern**

> **Lokal auf dem Mac (außerhalb des Containers, z. B. direkt im Repo-Checkout):**
> nicht `render-pdf.mjs`/Chrome verwenden, sondern den Skill `cv-pdf-render`
> (Markdown-Quelle `_quellen/cv.md` → `pandoc/latex`-Docker-Image, Seitenprüfung per
> PDFKit). Der folgende Weg gilt nur innerhalb des Containers.

`<Name>` (aus `daten/Master-Profil.md` → Personendaten) und `<Jobtitel>` in den
Dateinamen genauso dateisystem-sicher machen wie den Ordnernamen (Schritt 2b) —
Jobtitel enthalten oft `/` (z. B. "Senior Testmanager / Testkoordinator").
```
node .claude/skills/bewerbungs-pipeline/scripts/render-pdf.mjs \
  "daten/<Jobordner>/_quellen/cv.html" \
  "daten/<Jobordner>/CV_<Name> - <Jobtitel>.pdf"

node .claude/skills/bewerbungs-pipeline/scripts/render-pdf.mjs \
  "daten/<Jobordner>/_quellen/anschreiben.html" \
  "daten/<Jobordner>/Anschreiben_<Name> - <Jobtitel>.pdf"
```

(Beispiel: bei Name "Stefan Bollmann" also `CV_Stefan Bollmann - <Jobtitel>.pdf`.)

Danach beide PDFs kurz per `pdftoppm` (poppler-utils, direkt im Image installiert,
z. B. `pdftoppm -png -r 100 <pdf> <prefix>`) in PNG wandeln und mit dem Read-Tool
visuell prüfen: Ränder da, keine abgeschnittenen Abschnitte, Platzhalter vollständig
ersetzt (kein `{{` mehr sichtbar). Preview-PNGs danach löschen. Bei Auffälligkeiten
HTML korrigieren und neu rendern, bevor zur nächsten Zeile gegangen wird.

### 3. Abschlussmeldung

Am Ende kurz zusammenfassen: wie viele Jobs erfolgreich verarbeitet, welche Ordner
entstanden sind, und welche Zeilen übersprungen wurden (fehlende URL, Abruf
fehlgeschlagen, Ordner-Konflikt) — mit Grund, nicht nur Anzahl.

## Bekannte Stolpersteine (aus der Entwicklung dieser Pipeline)

- **Kein `docker` innerhalb dieses Containers verwenden** — Chromium, Node und
  `pdftoppm` sind bereits direkt im Image installiert, es gibt keinen Sidecar mehr.
  Ein Docker-Aufruf von hier aus würde Docker-in-Docker (Zugriff auf den
  Host-Docker-Socket) voraussetzen, was dieses Image bewusst nicht macht.
- Falls `Master-Profil.md` beim Start fehlt: nicht raten oder mit Platzhaltern
  weiterarbeiten, sondern erst gemeinsam mit dem Nutzer aus
  `Master-Profil.template.md` ein echtes Profil erstellen (siehe
  "Voraussetzungen").
- Bei sehr vielen Job-Zeilen die Renderings trotzdem nacheinander abarbeiten statt
  parallel — schont Arbeitsspeicher und macht Fehler pro Job leichter zuzuordnen.

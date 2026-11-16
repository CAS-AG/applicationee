---
name: cv-pdf-render
description: Rendert CVs (und andere Bewerbungsdokumente) aus Markdown per pandoc/latex-Docker-Image zu PDF und prüft jede Seite visuell — für die lokale Arbeit auf Stefans Mac außerhalb des Bewerbungs-Pipeline-Containers. Benutzen, wenn ein CV/Anschreiben als PDF erzeugt oder neu gerendert werden soll (z. B. "CV als PDF", "PDF neu rendern", "erstelle das CV-PDF") oder wenn die bewerbungs-pipeline lokal statt im Container läuft.
---

# CV-PDF-Rendering (Markdown → pandoc/latex)

Lokaler Render-Weg auf Stefans Mac: Markdown-Quelle → `pandoc/latex`-Docker-Image
(xelatex) → PDF, danach Prüfung jeder Seite per PDFKit-Vorschau.

**Nicht verwenden:** lokales Chrome/puppeteer (`render-pdf.mjs`). Chrome braucht dafür
einen Sandbox-Bypass, den Stefan abgelehnt hat. `pdftoppm` ist von der IT blockiert,
`sips` zeigt nur Seite 1.

**Innerhalb des Bewerbungs-Pipeline-Containers** gilt dieser Skill nicht: dort gibt
es kein Docker (kein Docker-in-Docker). Dort weiter `render-pdf.mjs` und `pdftoppm`
laut `bewerbungs-pipeline` verwenden.

## Voraussetzungen

- Docker über Rancher Desktop (`~/.rd/docker.sock`). Wenn `docker info` fehlschlägt,
  Stefan bitten, Rancher Desktop zu starten. Nicht auf einen anderen Render-Weg
  ausweichen.
- Das Image `pandoc/latex:latest` wird beim ersten Lauf automatisch gezogen
  (amd64-Emulation, der erste Lauf dauert deshalb länger).

## Ablauf

### 1. Markdown-Quelle anlegen

Pro Job-Ordner unter `_quellen/`:
- `cv.md`: Variante ohne Kommentierung, die zum Versand
- `cv-mit-kommentierung.md`: interne Variante mit Muss-/Soll-Abgleich (siehe
  Namenskonvention unten)

Jede Datei beginnt mit dem YAML-Header aus `templates/cv-header.yaml`. Am
Referenz-CV erprobter Aufbau:

```markdown
# <Name>

### <Rollentitel passend zur Anzeige>

**E-Mail:** … · Jahrgang … · <Abschluss> · <aktuelle Position>\
**Verfügbar:** ab <Start> · <Laufzeit> · <Ort/Remote>

---

## Kurzprofil
## Kernqualifikationen            (kommentierte Variante: "… im Abgleich zur Ausschreibung")
## Relevante Projekterfahrung (…)
   **<Projekt>**\
   <Branche> · <Zeitraum>\
   *Rolle: …*
   - Aufgaben-Bullets
   - *Technik:* …
## Weitere Projekterfahrung
## Zertifizierungen
## Ausbildung
## Technologie-Übersicht           (Pipe-Tabelle, Trennzeile `|:--|:--------|`)
```

Inhaltlich gelten die Regeln aus `bewerbungs-pipeline` (Schritt 2d): ausschließlich
Fakten aus `Master-Profil.md`, Lücken ehrlich benennen, Reihenfolge nach Relevanz.
Neue Fakten, die Stefan im Gespräch nennt, **zuerst in `Master-Profil.md`** eintragen
(mit Eintrag in der Änderungshistorie), dann in die CVs übernehmen.

**Kommentierte Variante:** direkt unter der Rollenzeile den Banner aus
`templates/variant-banner.tex` einfügen. Den Hinweis zum Abgleich als Blockzitat
(`> **Hinweis zum Abgleich:** …`) setzen.

### 2. Rendern

Aus dem Repo-Root, Dateinamen genauso dateisystem-sicher wie den Ordnernamen:

```
.claude/skills/cv-pdf-render/scripts/render.sh \
  "<Jobordner>/_quellen/cv.md" \
  "<Jobordner>/CV_<Name> - <Jobtitel>.pdf"

.claude/skills/cv-pdf-render/scripts/render.sh \
  "<Jobordner>/_quellen/cv-mit-kommentierung.md" \
  "<Jobordner>/CV_<Name> - <Jobtitel> (mit Eignungskommentierung).pdf"
```

`<Name>` kommt aus `Master-Profil.md` → Personendaten. Nacheinander rendern, nicht
parallel.

### 3. Visuell prüfen (jede Seite)

```
swift .claude/skills/cv-pdf-render/scripts/preview.swift "<pdf>" scratch/previews/<prefix>
```

Das Skript gibt die Seitenzahl aus und schreibt `<prefix>-1.png`, `<prefix>-2.png`, …
Jede Seite mit dem Read-Tool ansehen und prüfen:
- Nichts läuft über den rechten Rand (vor allem Banner, lange Tabellenzellen).
- Keine einzelne verwaiste Zeile oder Tabellenzeile auf der letzten Seite.
- Keine Platzhalter oder Markdown-Reste sichtbar.
- Ziel: 2 Seiten. Bei Überlauf zuerst Inhalt straffen. Für die interne Variante
  reicht auch ein knapperer Rand (`geometry: "a4paper,margin=2cm,top=1.4cm,bottom=1.4cm"`).

Danach die Preview-PNGs löschen. Temporäre Dateien immer nach `scratch/previews/` im
Repo schreiben (ist gitignored), nicht nach `/tmp` oder ins Session-Scratchpad.

## Namenskonvention

- `CV_<Name> - <Jobtitel>.pdf`: die Variante zum Versand, nie mit internem Vermerk.
- `CV_<Name> - <Jobtitel> (mit Eignungskommentierung).pdf`: intern, Banner im Dokument
  ist Pflicht.

## Bekannte Stolpersteine

- `pandoc/latex:latest` hat **kein arm64-Manifest**: immer `--platform linux/amd64`
  (macht `render.sh`).
- Das Image enthält **kein `enumitem.sty`**: keine `\setlist`-Header verwenden.
- Kein `mainfont` setzen: DejaVu u. a. fehlen im Image. Die Standardschrift (Latin
  Modern) kann Umlaute, „“, –, —, · und % über xelatex.
- Exotische Zeichen wie `≥` oder `→` vermeiden und lieber ausschreiben ("ab 3.x",
  "> 3 Jahre").
- Ein einfaches `\colorbox{…}{…}` bricht nicht um und läuft über den Rand: in eine
  `\parbox{\dimexpr\linewidth-2\fboxsep}` packen (siehe Banner-Template).
- Die Meldung `pandoc: Ticker: poll failed: Interrupted system call` ist Rauschen der
  amd64-Emulation und kein Fehler. `render.sh` filtert sie heraus.
- Im Image gibt es weder `gs` noch `pdftoppm`: Vorschau immer per `preview.swift`
  auf dem Host.

## Referenz

Erster mit diesem Weg erzeugter Job-Ordner (Aufbau und Formulierungen als Vorlage):
`mund consulting – Java Backend-Entwickler (Java, Spring Boot, JUnit) (m-w-d)/`

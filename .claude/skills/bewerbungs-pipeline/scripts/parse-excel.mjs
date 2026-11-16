// Liest eine Excel-Datei mit Job-Links ein und gibt sie als JSON-Array auf stdout aus.
//
// Unterstuetzt zwei Layouts:
//
// 1) Hyperlink-Matrix (typisch fuer Job-/Ressourcen-Tracker-Sheets, z.B. eine Zeile
//    pro Plattform mit mehreren als Zellen-Hyperlink verlinkten Job-Titeln in
//    unregelmaessigen Spalten): jede Zelle mit einem echten Excel-Hyperlink wird als
//    eigener Eintrag zurueckgegeben, mit `platform` = Wert von Spalte A derselben
//    Zeile (sofern vorhanden) und `title` = sichtbarer Zellentext.
//
// 2) Flache Liste mit URL als Klartext in einer Zelle: Fallback, falls das Sheet
//    keine einzige echte Hyperlink-Zelle enthaelt. Dann wird pro Datenzeile die erste
//    Zelle benutzt, deren Text wie eine URL aussieht.
//
// In beiden Faellen: Duplikate (gleiche URL) werden zusammengefasst, die Liste ist
// eine ERSTE ROHFASSUNG zum Gegenlesen -- generische Portal-/Upload-Links (kein
// echtes Stellenangebot) muessen von Hand aussortiert werden, bevor die Pipeline
// pro Eintrag CV+Anschreiben erzeugt.
//
// Aufruf (aus dem Arbeitsverzeichnis /workspace heraus, node_modules/xlsx muss
// installiert sein -- einmalig im Image per "npm ci" beim Build erledigt):
//   node .claude/skills/bewerbungs-pipeline/scripts/parse-excel.mjs <Jobliste.xlsx> [Sheetname]

import XLSX from 'xlsx';
import path from 'path';

const [, , fileArg, sheetArg] = process.argv;

if (!fileArg) {
  console.error('Usage: parse-excel.mjs <Jobliste.xlsx> [Sheetname]');
  process.exit(1);
}

const filePath = path.resolve(process.cwd(), fileArg);
const workbook = XLSX.readFile(filePath);
const sheetName = sheetArg || workbook.SheetNames[0];
const sheet = workbook.Sheets[sheetName];

if (!sheet) {
  console.error(`Sheet "${sheetName}" nicht gefunden. Verfuegbar: ${workbook.SheetNames.join(', ')}`);
  process.exit(1);
}

if (!sheet['!ref']) {
  console.log('[]');
  process.exit(0);
}

function decodeHtmlEntities(str) {
  return str
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

const range = XLSX.utils.decode_range(sheet['!ref']);
const hyperlinkEntries = [];

for (let r = range.s.r; r <= range.e.r; r++) {
  const platformAddr = XLSX.utils.encode_cell({ r, c: range.s.c });
  const platformCell = sheet[platformAddr];
  const platform = platformCell && typeof platformCell.v === 'string' ? platformCell.v.trim() : '';

  for (let c = range.s.c; c <= range.e.c; c++) {
    const addr = XLSX.utils.encode_cell({ r, c });
    const cell = sheet[addr];
    if (cell && cell.l && cell.l.Target) {
      hyperlinkEntries.push({
        platform,
        title: typeof cell.v === 'string' ? cell.v.trim() : String(cell.v ?? ''),
        url: decodeHtmlEntities(cell.l.Target),
        cell: addr,
      });
    }
  }
}

let entries;

if (hyperlinkEntries.length > 0) {
  entries = hyperlinkEntries;
} else {
  // Fallback: flache Liste, URL als Klartext irgendwo in der Zeile
  const rows = XLSX.utils.sheet_to_json(sheet, { defval: '' });
  const urlPattern = /^https?:\/\/\S+$/i;
  entries = rows
    .map((row, i) => {
      let url = '';
      for (const value of Object.values(row)) {
        if (typeof value === 'string' && urlPattern.test(value.trim())) {
          url = value.trim();
          break;
        }
      }
      return { rowIndex: i, url, title: '', platform: '', ...row };
    })
    .filter((e) => e.url);
}

// Duplikate (gleiche URL) zusammenfassen
const seen = new Map();
for (const e of entries) {
  if (!seen.has(e.url)) seen.set(e.url, e);
}

console.log(JSON.stringify([...seen.values()], null, 2));

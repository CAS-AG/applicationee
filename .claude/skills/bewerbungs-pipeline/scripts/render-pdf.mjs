// Rendert eine HTML-Datei per Headless-Chromium zu PDF (A4, 2cm Rand).
// Laeuft direkt im Bewerbungs-Pipeline-Container (Claude Code + Chromium im selben
// Image) -- kein separater PDF-Sidecar-Container mehr noetig.
//
// Aufruf (aus dem Arbeitsverzeichnis /workspace heraus):
//   node .claude/skills/bewerbungs-pipeline/scripts/render-pdf.mjs <input.html> <output.pdf>
//
// Pfade sind relativ zum aktuellen Arbeitsverzeichnis.

import puppeteer from 'puppeteer-core';
import path from 'path';

const [, , inputArg, outputArg] = process.argv;

if (!inputArg || !outputArg) {
  console.error('Usage: render-pdf.mjs <input.html> <output.pdf>');
  process.exit(1);
}

const inputPath = path.resolve(process.cwd(), inputArg);
const outputPath = path.resolve(process.cwd(), outputArg);

// Debians "chromium"-Paket (im Dockerfile installiert) liegt architekturunabhaengig
// immer unter diesem Pfad -- kein Download/keine Versionsermittlung noetig, und
// funktioniert (anders als ein via @puppeteer/browsers geladenes "chrome@stable")
// auch nativ auf arm64, da Google Chrome for Testing dort keine Builds anbietet.
const CHROMIUM_PATH = process.env.CHROMIUM_PATH || '/usr/bin/chromium';

(async () => {
  const browser = await puppeteer.launch({
    executablePath: CHROMIUM_PATH,
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });
  const page = await browser.newPage();
  await page.goto('file://' + inputPath, { waitUntil: 'networkidle0' });
  await page.evaluateHandle('document.fonts.ready');
  await new Promise((r) => setTimeout(r, 300));
  await page.emulateMediaType('print');
  await page.pdf({
    path: outputPath,
    format: 'A4',
    printBackground: true,
    margin: { top: '2cm', bottom: '2cm', left: '2cm', right: '2cm' },
    preferCSSPageSize: false,
  });
  await browser.close();
  console.log('PDF geschrieben:', outputArg);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

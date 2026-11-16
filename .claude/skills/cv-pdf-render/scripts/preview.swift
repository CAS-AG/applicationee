// Rendert jede Seite eines PDFs als PNG (PDFKit, macOS) für die visuelle Prüfung.
// Ersatz für pdftoppm (auf Stefans Mac von der IT blockiert) und sips (nur Seite 1).
//
// Aufruf:
//   swift .claude/skills/cv-pdf-render/scripts/preview.swift <input.pdf> <prefix>
// Erzeugt <prefix>-1.png, <prefix>-2.png, ... und gibt die Seitenzahl aus.
import PDFKit
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
  FileHandle.standardError.write("Usage: preview.swift <input.pdf> <prefix>\n".data(using: .utf8)!)
  exit(1)
}
print("pages:", doc.pageCount)
for i in 0..<doc.pageCount {
  let page = doc.page(at: i)!
  let img = page.thumbnail(of: NSSize(width: 900, height: 1270), for: .mediaBox)
  let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
  try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "\(args[2])-\(i + 1).png"))
}

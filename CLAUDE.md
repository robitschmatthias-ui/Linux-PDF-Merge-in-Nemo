# CLAUDE.md – PDF Merge in Nemo

## Verbindliche Entscheidungen – nicht erneut nachfragen

Getroffen vom Repo-Inhaber am 12.10.2026:

- **Windows-Version liegt in einem eigenen Repo**, nicht in diesem. Dieses Repo bleibt Linux/Nemo-only.
- **„Als PDF konvertieren" überschreibt nie**: Existiert die Ziel-PDF, wird automatisch `Name (2).pdf`, `Name (3).pdf` … verwendet und in der Abschlussmeldung genannt.
- **Advanced Merge, A4 + Hoch-/Querformat**: falsch ausgerichtete Seiten werden erst um 90° gedreht, dann auf A4 eingepasst (nicht nur verkleinert).

## Verhältnis zum PDF-OCR-Converter

Der [PDF-OCR-Converter](https://github.com/robitschmatthias-ui/PDF-OCR-Converter) („Merge & OCR to DOCX") fügt PDFs **selbst** per pypdf zusammen (`src/merge_and_ocr.py`) und ruft dieses Repo nicht auf – geprüft am 12.10.2026. Dessen README.de.md nennt unter Linux Mint noch „Quick Merge aus Linux-PDF-Merge-in-Nemo"; das ist veraltet.

## Technik

- Skripte müssen mit **LF**-Zeilenenden eingecheckt werden (bash bricht sonst auf Linux).
- pdftk-Drehung immer **relativ** (`right`), nie absolut (`east`) – sonst bleiben Seiten mit bestehender `/Rotate` ungedreht.
- LibreOffice immer über `lo_konvertieren` aufrufen (eigenes Profil per `-env:UserInstallation`), sonst schlägt die Konvertierung fehl, wenn LibreOffice offen ist.
- Texte in zenity-Dialogen sind Pango-Markup: dynamische Inhalte (Dateinamen, Fehlertexte) durch `esc` schicken.

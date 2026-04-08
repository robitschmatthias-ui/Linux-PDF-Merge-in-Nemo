# PDF Merge in Nemo

Bash-Skripte zum Zusammenfügen von Dateien zu PDF direkt aus dem Nemo-Dateimanager (Linux Mint / Ubuntu).

---

## Features

- **Zwei Merge-Modi per Rechtsklick:**
  - **PDF Quick Merge** – sofort zusammenfügen, keine weiteren Fragen
  - **PDF Advanced Merge** – Reihenfolge per Drag & Drop festlegen, Seitengröße und Ausrichtung wählen
- **Unterstützte Formate:** PDF, Bilder (JPG, PNG, TIFF, BMP, WebP, GIF), Office-Dokumente (ODT, ODS, ODP, DOCX, XLSX, PPTX, DOC)
- **A4-Anpassung** (Advanced) – große Seiten werden auf A4 verkleinert (300 DPI), kleine Bilder unter 200 DPI bleiben in Originalgröße und werden zentriert
- **Ausrichtung** (Advanced) – Original beibehalten, Hochformat oder Querformat erzwingen
- **PDF nach Merge öffnen** (Advanced) – optionale Checkbox um das Ergebnis direkt im Standard-PDF-Programm zu bearbeiten
- **Eigenes Icon** – blaues PDF-Merge-Icon im Kontextmenü
- **Automatischer Installer** – prüft und installiert alle Abhängigkeiten

## Voraussetzungen

Das Installationsskript kümmert sich um alles. Folgende Pakete werden automatisch installiert:

| Paket | Zweck |
|---|---|
| `libreoffice` | Konvertierung von Office-Dokumenten |
| `pdftk` | Zusammenfügen der PDF-Dateien |
| `img2pdf` | Konvertierung von Bildern |
| `zenity` | GUI-Dialoge |
| `yad` | Erweiterte Dialoge |
| `ghostscript` | Seitengrößen-Anpassung und Ausrichtung |

Python 3 mit GTK3 (vorinstalliert auf Ubuntu/Linux Mint) wird für den Advanced-Dialog verwendet.

## Installation

```bash
git clone https://github.com/robitschmatthias-ui/Linux-PDF-Merge-in-Nemo.git
cd Linux-PDF-Merge-in-Nemo
git checkout feature/v2-improvements
sudo bash install.sh
nemo -q && nemo &
```

Der Installer prüft welche Abhängigkeiten bereits vorhanden sind und installiert nur die fehlenden Pakete. Nach der Installation und dem Nemo-Neustart erscheinen zwei Einträge im Rechtsklick-Menü.

## Verwendung

### PDF Quick Merge

1. Dateien in Nemo markieren
2. Rechtsklick → **PDF Quick Merge**
3. Speicherort wählen
4. Fertig

### PDF Advanced Merge

1. Dateien in Nemo markieren
2. Rechtsklick → **PDF Advanced Merge**
3. Im Dialog:
   - Dateien per **Drag & Drop** in die gewünschte Reihenfolge ziehen
   - **Seitengröße** wählen (Original oder A4-Anpassung)
   - **Ausrichtung** wählen (Original, Hochformat, Querformat)
   - Optional: **PDF nach Merge öffnen** ankreuzen
4. Speicherort wählen
5. Fertig

> Tipp: Mit „PDF Arranger" (separat installierbar) können einzelne Seiten nachträglich gedreht oder verschoben werden.

## Deinstallation

```bash
rm ~/.local/bin/"PDF zusammenfügen.sh"
rm ~/.local/bin/advanced_dialog.py
rm ~/.local/share/icons/pdf-merge-icon.svg
rm ~/.local/share/nemo/actions/pdf-quick-merge.nemo_action
rm ~/.local/share/nemo/actions/pdf-advanced-merge.nemo_action
nemo -q && nemo &
```

---

## Lizenz

MIT License – frei verwendbar, veränderbar und weitergebbar.

## Hinweis

Der Code wurde vollständig mit KI generiert. Es funktioniert bei mir im Test wunderbar. Das ist mein erstes Projekt in GitHub. Nennt es gerne VibeCoding, aber seid bitte freundlich.
# Linux-Programme

Sammlung von Bash-Skripten für den täglichen Gebrauch unter Linux (Ubuntu / Linux Mint).

---

## PDF zusammenfügen

> Mehrere Dateien unterschiedlicher Formate per Rechtsklick zu einem einheitlichen A4-PDF zusammenführen.

### Features

- **Unterstützte Formate:** PDF, Bilder (JPG, PNG, TIFF, BMP, WebP, GIF), Office-Dokumente (ODT, ODS, ODP, DOCX, XLSX, PPTX, DOC)
- **Reihenfolge per GUI festlegen** – Dateien in einem Dialog mit ⬆/⬇-Buttons sortieren
- **A4-Normalisierung** – alle Seiten werden automatisch auf einheitliches A4-Format skaliert, egal ob Scan, Foto oder Dokument
- **Nemo-Integration** – direkt per Rechtsklick im Dateimanager aufrufbar
- **Automatischer Installer** – installiert alle Abhängigkeiten selbstständig

### Voraussetzungen

Das Installationsskript kümmert sich um alles. Folgende Pakete werden automatisch installiert:

| Paket | Zweck |
|---|---|
| `libreoffice` | Konvertierung von Office-Dokumenten |
| `pdftk` | Zusammenfügen der PDF-Dateien |
| `img2pdf` | Konvertierung von Bildern |
| `zenity` | GUI-Dialoge |
| `yad` | Sortier-Dialog mit Buttons |
| `ghostscript` | A4-Normalisierung |

### Installation

```bash
git clone https://github.com/robitschmatthias-ui/Linux-Programme.git
cd Linux-Programme/paket
sudo bash install.sh
```

Nach der Installation erscheint **„PDF zusammenfügen"** direkt im Rechtsklick-Menü von Nemo.

### Verwendung

1. Dateien in Nemo markieren (PDF, Bilder, Office-Dokumente – auch gemischt)
2. Rechtsklick → **PDF zusammenfügen**
3. Reihenfolge per Dialog festlegen
4. Speicherort wählen
5. Fertig – alle Seiten werden automatisch auf A4 normalisiert

Es empfielt sich die Installation von "PDF Arranger" um ggf. einzelne Seiten zu drehen oder die Reihenfolge nachträglich zu optimieren.

### Deinstallation

```bash
sudo rm /usr/local/bin/pdf-zusammenfuehren.sh
sudo rm /usr/share/nemo/actions/pdf-zusammenfuehren.nemo_action
nemo -q && nemo
```

---

## Lizenz

MIT License – frei verwendbar, veränderbar und weiterggebbar.

## Hinweis

Der Code wurde vollständig mit KI geeriert. Es funktioniert bei mir im Test wunderbar. Ich werde ab sofort testen. Das ist mein erstes Projekt in GitHub. Nennt es gerne VibeCoding, aber seid bitte freundlich.


Linux-Programme
Sammlung von Bash-Skripten für den täglichen Gebrauch unter Linux (Ubuntu / Linux Mint).

PDF zusammenfügen
Mehrere Dateien unterschiedlicher Formate per Rechtsklick zu einem einheitlichen A4-PDF zusammenführen.

Features
Unterstützte Formate: PDF, Bilder (JPG, PNG, TIFF, BMP, WebP, GIF), Office-Dokumente (ODT, ODS, ODP, DOCX, XLSX, PPTX, DOC)
Reihenfolge per GUI festlegen – Dateien in einem Dialog mit ⬆/⬇-Buttons sortieren
A4-Normalisierung – alle Seiten werden automatisch auf einheitliches A4-Format skaliert, egal ob Scan, Foto oder Dokument
Nemo-Integration – direkt per Rechtsklick im Dateimanager aufrufbar
Automatischer Installer – prüft und installiert alle Abhängigkeiten selbstständig
Voraussetzungen
Das Installationsskript kümmert sich um alles. Folgende Pakete werden automatisch installiert:

Paket	Zweck
libreoffice	Konvertierung von Office-Dokumenten
pdftk	Zusammenfügen der PDF-Dateien
img2pdf	Konvertierung von Bildern
zenity	GUI-Dialoge
yad	Sortier-Dialog mit Buttons
ghostscript	A4-Normalisierung
Installation

git clone https://github.com/robitschmatthias-ui/Linux-Programme.git
cd Linux-Programme
sudo bash install.sh
Der Installer prüft welche Abhängigkeiten bereits vorhanden sind und installiert nur die fehlenden Pakete. Nach der Installation erscheint „PDF zusammenfügen" direkt im Rechtsklick-Menü von Nemo.

Verwendung
Dateien in Nemo markieren (PDF, Bilder, Office-Dokumente – auch gemischt)
Rechtsklick → PDF zusammenfügen
Reihenfolge per Dialog festlegen
Speicherort wählen
Fertig – alle Seiten werden automatisch auf A4 normalisiert
Es empfiehlt sich die Installation von "PDF Arranger" um ggf. einzelne Seiten zu drehen oder die Reihenfolge nachträglich zu optimieren.

Deinstallation

rm ~/.local/bin/"PDF zusammenfügen.sh"
rm ~/.local/share/nemo/actions/pdf-zusammenfuegen.nemo_action
nemo -q && nemo &
Lizenz
MIT License – frei verwendbar, veränderbar und weitergebbar.

Hinweis
Der Code wurde vollständig mit KI generiert. Es funktioniert bei mir im Test wunderbar. Ich werde ab sofort testen. Das ist mein erstes Projekt in GitHub. Nennt es gerne VibeCoding, aber seid bitte freundlich.

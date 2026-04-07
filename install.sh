#!/bin/bash
# install.sh – Installiert "PDF zusammenfügen" und alle Abhängigkeiten

SCRIPT_NAME="PDF zusammenfügen.sh"
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
INSTALL_DIR="$REAL_HOME/.local/bin"
NEMO_ACTIONS_DIR="$REAL_HOME/.local/share/nemo/actions"
ACTION_FILE="pdf-zusammenfuegen.nemo_action"

echo ""
echo "=== PDF zusammenfügen – Installer ==="
echo ""
echo "Dieses Skript führt folgende Schritte aus:"
echo "  1. Prüft ob folgende Abhängigkeiten installiert sind:"
echo "     libreoffice, pdftk, img2pdf, zenity, ghostscript, yad"
echo "  2. Installiert fehlende Pakete automatisch (apt)"
echo "  3. Kopiert das Skript nach $INSTALL_DIR/"
echo "  4. Richtet die Nemo-Rechtsklick-Integration ein"
echo ""

# Prüfen ob als root ausgeführt
if [ "$EUID" -ne 0 ]; then
    echo "FEHLER: Bitte mit sudo ausführen: sudo bash install.sh"
    exit 1
fi

# Prüfen ob Hauptskript vorhanden ist
if [ ! -f "$SCRIPT_NAME" ]; then
    echo "FEHLER: '$SCRIPT_NAME' nicht gefunden."
    echo "Installer muss aus dem Repository-Ordner ausgeführt werden."
    exit 1
fi

# Einmalige Bestätigung
read -rp "Fortfahren? (j/n): " ANSWER
if [[ "$ANSWER" != "j" && "$ANSWER" != "J" ]]; then
    echo "Installation abgebrochen."
    exit 0
fi

echo ""

# ── Schritt 1: Abhängigkeiten prüfen ─────────────────────────────────────────
echo "→ Prüfe Abhängigkeiten..."
NEEDED=()
for CMD in libreoffice pdftk img2pdf zenity gs yad; do
    if command -v "$CMD" &>/dev/null; then
        echo "  ✓ $CMD – bereits installiert"
    else
        echo "  ✗ $CMD – fehlt"
        NEEDED+=("$CMD")
    fi
done

# ── Schritt 2: Fehlende Pakete installieren ───────────────────────────────────
if [ ${#NEEDED[@]} -gt 0 ]; then
    # gs → ghostscript im Paketnamen
    PACKAGES=()
    for CMD in "${NEEDED[@]}"; do
        if [ "$CMD" = "gs" ]; then
            PACKAGES+=("ghostscript")
        else
            PACKAGES+=("$CMD")
        fi
    done

    echo ""
    echo "→ Installiere fehlende Pakete: ${PACKAGES[*]} ..."
    apt-get update -qq
    apt-get install -y "${PACKAGES[@]}"

    # Verifizieren
    echo ""
    echo "→ Prüfe Installation..."
    FAILED=()
    for CMD in "${NEEDED[@]}"; do
        if command -v "$CMD" &>/dev/null; then
            echo "  ✓ $CMD"
        else
            echo "  ✗ $CMD – Installation fehlgeschlagen"
            FAILED+=("$CMD")
        fi
    done

    if [ ${#FAILED[@]} -gt 0 ]; then
        echo ""
        echo "FEHLER: Nicht alle Pakete konnten installiert werden."
        printf '  - %s\n' "${FAILED[@]}"
        echo "Bitte manuell nachinstallieren und Installer erneut starten."
        exit 1
    fi
else
    echo ""
    echo "  Alle Abhängigkeiten sind bereits installiert."
fi

# ── Schritt 3: Skript installieren ────────────────────────────────────────────
echo ""
echo "→ Installiere Skript nach $INSTALL_DIR/ ..."
sudo -u "$REAL_USER" mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_NAME" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
chown "$REAL_USER:$REAL_USER" "$INSTALL_DIR/$SCRIPT_NAME"

# ── Schritt 4: Nemo-Integration einrichten ────────────────────────────────────
echo "→ Richte Nemo-Rechtsklick-Integration ein..."
sudo -u "$REAL_USER" mkdir -p "$NEMO_ACTIONS_DIR"

cat > "$NEMO_ACTIONS_DIR/$ACTION_FILE" << EOF
[Nemo Action]
Name=PDF zusammenfügen
Comment=Dateien zu einem A4-PDF zusammenfügen
Exec=bash "$INSTALL_DIR/$SCRIPT_NAME" %F
Icon-Name=application-pdf
Selection=Any
Extensions=pdf;doc;docx;odt;ods;odp;pptx;xlsx;jpg;jpeg;png;gif;tiff;tif;bmp;webp;
EOF

chown "$REAL_USER:$REAL_USER" "$NEMO_ACTIONS_DIR/$ACTION_FILE"

# ── Fertig ────────────────────────────────────────────────────────────────────
echo ""
echo "=== Installation erfolgreich abgeschlossen! ==="
echo ""
echo "Nemo neu starten um den Rechtsklick-Eintrag zu aktivieren:"
echo "  nemo -q && nemo &"
echo ""

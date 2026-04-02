#!/bin/bash
# Abhängigkeiten: libreoffice, pdftk, img2pdf, zenity, ghostscript, yad
# sudo apt install libreoffice pdftk img2pdf zenity ghostscript yad

TMPDIR=$(mktemp -d)

# Sperrdateien (LibreOffice .~lock.*#) und nicht unterstützte Typen herausfiltern
ORDERED_FILES=()
for F in "$@"; do
    BASENAME=$(basename "$F")
    [[ "$BASENAME" == .~lock.* ]] && continue
    ORDERED_FILES+=("$F")
done

if [ ${#ORDERED_FILES[@]} -eq 0 ]; then
    zenity --error --title="Fehler" --text="Keine verwertbaren Dateien ausgewählt."
    exit 1
fi

# ── Schritt 1: Reihenfolge per Dialog festlegen ──────────────────────────────
# yad-Buttons mit festen Exit-Codes:
#   2 = ⬆ Nach oben  |  4 = ⬇ Nach unten  |  0 = ✓ Fertig  |  1/252 = Abbrechen
while true; do
    LIST_ITEMS=()
    for i in "${!ORDERED_FILES[@]}"; do
        LIST_ITEMS+=("$((i+1))" "$(basename "${ORDERED_FILES[$i]}")" "${ORDERED_FILES[$i]}")
    done

    SELECTED=$(yad --list \
        --title="Reihenfolge festlegen" \
        --text="Datei auswählen und mit den Pfeilen verschieben." \
        --column="Nr." \
        --column="Dateiname" \
        --column="Pfad" \
        --hide-column=3 \
        --print-column=3 \
        --button="⬆ Nach oben:2" \
        --button="⬇ Nach unten:4" \
        --button="✓ Fertig:0" \
        --button="Abbrechen:1" \
        --width=600 --height=400 \
        "${LIST_ITEMS[@]}" 2>/dev/null)

    EXIT_CODE=$?

    case $EXIT_CODE in
        0)  # ✓ Fertig
            break
            ;;
        1|252)  # Abbrechen oder Fenster geschlossen
            zenity --question \
                --title="Abbrechen?" \
                --text="Wirklich abbrechen? Bisher getroffene Auswahl geht verloren." \
                --ok-label="Ja, abbrechen" \
                --cancel-label="Weitermachen"
            [ $? -eq 0 ] && { rm -rf "$TMPDIR"; exit 0; }
            ;;
        2|4)  # ⬆ Nach oben oder ⬇ Nach unten
            # yad hängt ein | ans Ende – entfernen
            SELECTED="${SELECTED%|}"

            SELECTED_IDX=-1
            for i in "${!ORDERED_FILES[@]}"; do
                [ "${ORDERED_FILES[$i]}" = "$SELECTED" ] && SELECTED_IDX=$i && break
            done
            [ $SELECTED_IDX -eq -1 ] && continue

            if [ $EXIT_CODE -eq 2 ] && [ $SELECTED_IDX -gt 0 ]; then
                SWAP=$((SELECTED_IDX - 1))
                TEMP="${ORDERED_FILES[$SWAP]}"
                ORDERED_FILES[$SWAP]="${ORDERED_FILES[$SELECTED_IDX]}"
                ORDERED_FILES[$SELECTED_IDX]="$TEMP"
            elif [ $EXIT_CODE -eq 4 ] && [ $SELECTED_IDX -lt $((${#ORDERED_FILES[@]} - 1)) ]; then
                SWAP=$((SELECTED_IDX + 1))
                TEMP="${ORDERED_FILES[$SWAP]}"
                ORDERED_FILES[$SWAP]="${ORDERED_FILES[$SELECTED_IDX]}"
                ORDERED_FILES[$SELECTED_IDX]="$TEMP"
            fi
            ;;
    esac
done

# ── Schritt 2: Reihenfolge zur Bestätigung anzeigen ──────────────────────────
SUMMARY=""
for i in "${!ORDERED_FILES[@]}"; do
    SUMMARY+="$((i+1)). $(basename "${ORDERED_FILES[$i]}")\n"
done

zenity --question \
    --title="Reihenfolge bestätigen" \
    --text="PDF wird in dieser Reihenfolge erstellt:\n\n$SUMMARY\nFortfahren?" \
    --ok-label="Ja, weiter" \
    --cancel-label="Abbrechen" \
    --width=450

[ $? -ne 0 ] && { rm -rf "$TMPDIR"; exit 0; }

# ── Schritt 3: Speicherort und Dateiname festlegen ───────────────────────────
OUTPUT=$(zenity --file-selection \
    --save \
    --confirm-overwrite \
    --title="Speicherort und Dateiname wählen" \
    --filename="$HOME/zusammengefuehrt.pdf" \
    --file-filter="PDF-Dateien | *.pdf")

[ -z "$OUTPUT" ] && { rm -rf "$TMPDIR"; exit 0; }

# .pdf-Endung sicherstellen
[[ "$OUTPUT" != *.pdf ]] && OUTPUT="$OUTPUT.pdf"

# ── Schritt 4: Konvertieren & zusammenfügen ───────────────────────────────────
PDF_LIST=()
ERRORS=()
COUNTER=0

for FILE in "${ORDERED_FILES[@]}"; do
    EXT_LOWER=$(echo "${FILE##*.}" | tr '[:upper:]' '[:lower:]')

    case "$EXT_LOWER" in
        pdf)
            PDF_LIST+=("$FILE")
            ;;
        doc|docx|odt|ods|odp|pptx|xlsx)
            COUNTER=$((COUNTER+1))
            BASENAME=$(basename "${FILE%.*}")
            LO_OUT="$TMPDIR/$BASENAME.pdf"
            CONVERTED="$TMPDIR/${COUNTER}_$BASENAME.pdf"
            libreoffice --headless --convert-to pdf "$FILE" --outdir "$TMPDIR" 2>/dev/null
            if [ -f "$LO_OUT" ]; then
                mv "$LO_OUT" "$CONVERTED"
                PDF_LIST+=("$CONVERTED")
            else
                ERRORS+=("$(basename "$FILE")")
            fi
            ;;
        jpg|jpeg|png|gif|tiff|tif|bmp|webp)
            COUNTER=$((COUNTER+1))
            BASENAME=$(basename "${FILE%.*}")
            CONVERTED="$TMPDIR/${COUNTER}_$BASENAME.pdf"
            img2pdf "$FILE" -o "$CONVERTED" 2>/dev/null
            if [ -f "$CONVERTED" ]; then
                PDF_LIST+=("$CONVERTED")
            else
                ERRORS+=("$(basename "$FILE")")
            fi
            ;;
        *)
            # Dateityp anhand Inhalt erkennen (keine bekannte Erweiterung)
            FILETYPE=$(file --mime-type -b "$FILE")
            case "$FILETYPE" in
                image/jpeg|image/png|image/gif|image/tiff|image/bmp|image/webp)
                    COUNTER=$((COUNTER+1))
                    BASENAME=$(basename "$FILE")
                    CONVERTED="$TMPDIR/${COUNTER}_$BASENAME.pdf"
                    img2pdf "$FILE" -o "$CONVERTED" 2>/dev/null
                    if [ -f "$CONVERTED" ]; then
                        PDF_LIST+=("$CONVERTED")
                    else
                        ERRORS+=("$(basename "$FILE")")
                    fi
                    ;;
                application/pdf)
                    PDF_LIST+=("$FILE")
                    ;;
                *)
                    ERRORS+=("$(basename "$FILE") [nicht unterstützt: $FILETYPE]")
                    ;;
            esac
            ;;
    esac
done

if [ ${#ERRORS[@]} -gt 0 ]; then
    zenity --warning \
        --title="Hinweis" \
        --text="Folgende Dateien konnten nicht konvertiert werden:\n\n$(printf '%s\n' "${ERRORS[@]}")\n\nDie restlichen Dateien werden trotzdem zusammengefügt."
fi

if [ ${#PDF_LIST[@]} -eq 0 ]; then
    zenity --error --title="Fehler" --text="Keine verwertbaren Dateien gefunden. Abbruch."
    rm -rf "$TMPDIR"
    exit 1
fi

MERGED="$TMPDIR/merged.pdf"
pdftk "${PDF_LIST[@]}" cat output "$MERGED"

if [ $? -ne 0 ]; then
    zenity --error --title="Fehler" --text="pdftk ist fehlgeschlagen. Ist pdftk installiert?"
    rm -rf "$TMPDIR"
    exit 1
fi

# ── Schritt 5: Alle Seiten auf A4 normalisieren ───────────────────────────────
# A4 = 595.28 x 841.89 Punkte (72 Punkte/Zoll)
gs -dBATCH -dNOPAUSE -q \
   -sDEVICE=pdfwrite \
   -dFIXEDMEDIA \
   -dPDFFitPage \
   -dAutoRotatePages=/All \
   -dDEVICEWIDTHPOINTS=595.28 \
   -dDEVICEHEIGHTPOINTS=841.89 \
   -sOutputFile="$OUTPUT" \
   "$MERGED"

if [ $? -eq 0 ]; then
    zenity --info \
        --title="Fertig!" \
        --text="✅ PDF erfolgreich erstellt:\n<b>$OUTPUT</b>\n\nAlle Seiten wurden auf A4 normalisiert." \
        --width=450
else
    zenity --error --title="Fehler" --text="Ghostscript ist fehlgeschlagen. Ist ghostscript installiert?\nsudo apt install ghostscript"
fi

rm -rf "$TMPDIR"

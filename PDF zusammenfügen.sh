#!/bin/bash
# Abhängigkeiten: libreoffice, pdftk, img2pdf, zenity, ghostscript, yad
# Installation: sudo bash install.sh

MODE="$1"
shift

TMPDIR=$(mktemp -d)

# Sperrdateien (LibreOffice .~lock.*#) herausfiltern
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

# ══════════════════════════════════════════════════════════════════════════════
# Gemeinsame Funktionen
# ══════════════════════════════════════════════════════════════════════════════

konvertiere_dateien() {
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
}

speicherort_waehlen() {
    OUTPUT=$(zenity --file-selection \
        --save \
        --confirm-overwrite \
        --title="Speicherort und Dateiname wählen" \
        --filename="$HOME/zusammengefuehrt.pdf" \
        --file-filter="PDF-Dateien | *.pdf")

    [ -z "$OUTPUT" ] && { rm -rf "$TMPDIR"; exit 0; }
    [[ "$OUTPUT" != *.pdf ]] && OUTPUT="$OUTPUT.pdf"
}

zusammenfuegen() {
    MERGED="$TMPDIR/merged.pdf"
    pdftk "${PDF_LIST[@]}" cat output "$MERGED"

    if [ $? -ne 0 ]; then
        zenity --error --title="Fehler" --text="pdftk ist fehlgeschlagen."
        rm -rf "$TMPDIR"
        exit 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# QUICK MERGE – keine Dialoge, direkt zusammenfügen
# ══════════════════════════════════════════════════════════════════════════════

quick_merge() {
    speicherort_waehlen
    konvertiere_dateien
    zusammenfuegen

    # Quick: direkt kopieren, kein Ghostscript
    cp "$MERGED" "$OUTPUT"

    if [ $? -eq 0 ]; then
        zenity --info \
            --title="Fertig!" \
            --text="PDF erfolgreich erstellt:\n<b>$OUTPUT</b>" \
            --width=400
    else
        zenity --error --title="Fehler" --text="PDF konnte nicht erstellt werden."
    fi

    rm -rf "$TMPDIR"
}

# ══════════════════════════════════════════════════════════════════════════════
# ADVANCED MERGE – Reihenfolge, Orientierung, Ghostscript
# ══════════════════════════════════════════════════════════════════════════════

advanced_merge() {
    # ── Kombinierter Dialog: Reihenfolge + Optionen ──────────────────────────
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    DIALOG_OUTPUT=$(python3 "$SCRIPT_DIR/advanced_dialog.py" "${ORDERED_FILES[@]}")

    [ $? -ne 0 ] && { rm -rf "$TMPDIR"; exit 0; }

    # Ergebnis parsen
    ORDERED_FILES=()
    SIZE_OPT=""
    ORIENT_OPT=""
    OPEN_AFTER=""
    while IFS= read -r line; do
        case "$line" in
            FILE=*)   ORDERED_FILES+=("${line#FILE=}") ;;
            SIZE=*)   SIZE_OPT="${line#SIZE=}" ;;
            ORIENT=*) ORIENT_OPT="${line#ORIENT=}" ;;
            OPEN=*)   OPEN_AFTER="${line#OPEN=}" ;;
        esac
    done <<< "$DIALOG_OUTPUT"

    # ── Speicherort, Konvertierung, Zusammenfügen ────────────────────────────
    speicherort_waehlen
    konvertiere_dateien
    zusammenfuegen

    # ── Nachbearbeitung je nach Optionen ─────────────────────────────────────
    if [ "$SIZE_OPT" = "original" ] && [ "$ORIENT_OPT" = "original" ]; then
        # Keine Anpassung – direkt kopieren
        cp "$MERGED" "$OUTPUT"
    else
        # Ghostscript-Parameter zusammenbauen
        GS_ARGS=(-dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite)

        # Größe
        if [ "$SIZE_OPT" = "a4" ]; then
            GS_ARGS+=(-dFIXEDMEDIA -dPDFFitPage)
            if [ "$ORIENT_OPT" = "querformat" ]; then
                GS_ARGS+=(-dDEVICEWIDTHPOINTS=841.89 -dDEVICEHEIGHTPOINTS=595.28)
            else
                GS_ARGS+=(-dDEVICEWIDTHPOINTS=595.28 -dDEVICEHEIGHTPOINTS=841.89)
            fi
            if [ "$ORIENT_OPT" = "original" ]; then
                GS_ARGS+=(-dAutoRotatePages=/None)
            fi
        fi

        # Nur Ausrichtung ändern, keine Größenanpassung
        if [ "$SIZE_OPT" = "original" ] && [ "$ORIENT_OPT" != "original" ]; then
            if [ "$ORIENT_OPT" = "hochformat" ]; then
                GS_ARGS+=(-dAutoRotatePages=/All -dDEVICEWIDTHPOINTS=595.28 -dDEVICEHEIGHTPOINTS=841.89)
            elif [ "$ORIENT_OPT" = "querformat" ]; then
                GS_ARGS+=(-dAutoRotatePages=/All -dDEVICEWIDTHPOINTS=841.89 -dDEVICEHEIGHTPOINTS=595.28)
            fi
        fi

        gs "${GS_ARGS[@]}" -sOutputFile="$OUTPUT" "$MERGED"
    fi

    if [ $? -eq 0 ]; then
        zenity --info \
            --title="Fertig!" \
            --text="PDF erfolgreich erstellt:\n<b>$OUTPUT</b>" \
            --width=400
        [ "$OPEN_AFTER" = "yes" ] && xdg-open "$OUTPUT" &
    else
        zenity --error --title="Fehler" --text="PDF konnte nicht erstellt werden."
    fi

    rm -rf "$TMPDIR"
}

# ══════════════════════════════════════════════════════════════════════════════
# Modus starten
# ══════════════════════════════════════════════════════════════════════════════

case "$MODE" in
    --quick)    quick_merge ;;
    --advanced) advanced_merge ;;
    *)
        zenity --error --title="Fehler" --text="Unbekannter Modus: $MODE\n\nVerwendung:\n  $0 --quick DATEIEN...\n  $0 --advanced DATEIEN..."
        exit 1
        ;;
esac
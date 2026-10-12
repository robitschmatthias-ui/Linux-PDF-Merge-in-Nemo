#!/bin/bash
# Abhängigkeiten: libreoffice, pdftk, img2pdf (inkl. python3-pil), zenity, ghostscript, bc, file, python3-gi
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

# Maskiert &, < und > für zenity-Texte (Pango-Markup) – sonst brechen
# Dateinamen wie "Angebot & Rechnung.pdf" die Meldung.
# "\&" statt "&": ab bash 5.2 steht ein nacktes & im Ersetzungstext für den
# Treffer (patsub_replacement) – aus "<" würde sonst "<lt;".
esc() {
    local S="$1"
    S="${S//&/\&amp;}"
    S="${S//</\&lt;}"
    S="${S//>/\&gt;}"
    printf '%s' "$S"
}

# Konvertiert eine Office-Datei ($1) per LibreOffice nach $2 (Ordner).
# Eigenes Profil im TMPDIR: Ist LibreOffice bereits geöffnet, hängt sich der
# Headless-Aufruf sonst an die laufende Instanz und erzeugt keine PDF.
lo_konvertieren() {
    libreoffice -env:UserInstallation="file://$TMPDIR/lo_profile" \
        --headless --norestore --convert-to pdf "$1" --outdir "$2" 2>/dev/null
}

# Liefert einen freien Dateinamen: Ordner/Name.pdf, sonst "Name (2).pdf" usw.
freier_pdf_name() {
    local DIR="$1" NAME="$2" N=2
    local KANDIDAT="$DIR/$NAME.pdf"
    while [ -e "$KANDIDAT" ]; do
        KANDIDAT="$DIR/$NAME ($N).pdf"
        N=$((N+1))
    done
    printf '%s' "$KANDIDAT"
}

# Bild ($1) für Advanced "Auf A4 anpassen" direkt als A4-Seite ($2) anlegen:
# - erreicht das Bild auf voller A4-Fläche mindestens 200 DPI, füllt es die Seite
#   (wird also auch vergrößert)
# - darunter bleibt es in Originalgröße zentriert (nur verkleinert, falls es
#   größer als A4 ist) – kleine Bilder würden sonst grob verpixelt aufgeblasen
# Hoch-/Querformat der Seite richtet sich nach dem Bild.
bild_auf_a4() {
    local IN="$1" OUT="$2" FIT
    FIT=$(python3 - "$IN" 2>/dev/null <<'PY'
import sys
from PIL import Image
with Image.open(sys.argv[1]) as im:
    w, h = im.size
# DPI, die das Bild hätte, wenn es A4 (297 x 210 mm) ausfüllt
dpi = min(max(w, h) / (297 / 25.4), min(w, h) / (210 / 25.4))
print("into" if dpi >= 200 else "shrink")
PY
)
    [ -z "$FIT" ] && FIT="into"
    img2pdf "$IN" --pagesize A4 --auto-orient --fit "$FIT" -o "$OUT" 2>/dev/null
}

# Bild ($1) für den Merge nach $2: bei A4-Anpassung als A4-Seite, sonst in Bildgröße
bild_fuer_merge() {
    if [ "$SIZE_OPT" = "a4" ]; then
        bild_auf_a4 "$1" "$2"
    else
        img2pdf "$1" -o "$2" 2>/dev/null
    fi
}

# Verarbeitet eine einzelne Datei und aktualisiert PDF_LIST/ERRORS/COUNTER
# Benötigt: TMPDIR, PDF_LIST, ERRORS, COUNTER im aufrufenden Scope
verarbeite_datei() {
    local FILE="$1"
    local EXT_LOWER BASENAME LO_OUT CONVERTED FILETYPE

    EXT_LOWER=$(echo "${FILE##*.}" | tr '[:upper:]' '[:lower:]')

    case "$EXT_LOWER" in
        pdf)
            PDF_LIST+=("$FILE")
            ;;
        doc|docx|odt|ods|odp|pptx|xlsx|txt|rtf)
            if ! command -v libreoffice &>/dev/null; then
                ERRORS+=("$(basename "$FILE") [LibreOffice nicht im PATH – Symlink prüfen]")
                return
            fi
            COUNTER=$((COUNTER+1))
            BASENAME=$(basename "${FILE%.*}")
            LO_OUT="$TMPDIR/$BASENAME.pdf"
            CONVERTED="$TMPDIR/${COUNTER}_$BASENAME.pdf"
            lo_konvertieren "$FILE" "$TMPDIR"
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
            bild_fuer_merge "$FILE" "$CONVERTED"
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
                    bild_fuer_merge "$FILE" "$CONVERTED"
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
}

konvertiere_dateien() {
    local TOTAL=${#ORDERED_FILES[@]}
    local LIST_FILE="$TMPDIR/pdflist.bin"
    local ERRORS_FILE="$TMPDIR/convert_errors.txt"

    # Konvertierung mit Fortschrittsanzeige. Die Subshell gibt PDF_LIST und
    # ERRORS über Dateien zurück (Variablen gehen nach der Pipe verloren).
    (
    PDF_LIST=()
    ERRORS=()
    COUNTER=0

    for IDX in "${!ORDERED_FILES[@]}"; do
        FILE="${ORDERED_FILES[$IDX]}"
        CURRENT=$((IDX + 1))
        echo $(( (CURRENT - 1) * 100 / TOTAL ))
        echo "# Datei $CURRENT von $TOTAL: $(esc "$(basename "$FILE")")"
        verarbeite_datei "$FILE"
    done

    [ ${#PDF_LIST[@]} -gt 0 ] && printf '%s\0' "${PDF_LIST[@]}" > "$LIST_FILE"
    [ ${#ERRORS[@]} -gt 0 ]   && printf '%s\n' "${ERRORS[@]}"   > "$ERRORS_FILE"
    echo "100"
    ) | zenity --progress \
        --title="PDF Advanced Merge" \
        --text="Dateien werden konvertiert..." \
        --percentage=0 \
        --auto-close \
        --no-cancel \
        --width=350

    PDF_LIST=()
    [ -s "$LIST_FILE" ] && mapfile -d '' -t PDF_LIST < "$LIST_FILE"

    if [ -s "$ERRORS_FILE" ]; then
        zenity --warning \
            --title="Hinweis" \
            --text="Folgende Dateien konnten nicht konvertiert werden:\n\n$(esc "$(cat "$ERRORS_FILE")")\n\nDie restlichen Dateien werden trotzdem zusammengefügt."
    fi

    if [ ${#PDF_LIST[@]} -eq 0 ]; then
        zenity --error --title="Fehler" --text="Keine verwertbaren Dateien gefunden. Abbruch."
        rm -rf "$TMPDIR"
        exit 1
    fi
}

# $1 = optionaler Default-Pfad (inkl. Dateiname)
speicherort_waehlen() {
    local DEFAULT="${1:-$HOME/zusammengefuehrt.pdf}"
    OUTPUT=$(zenity --file-selection \
        --save \
        --confirm-overwrite \
        --title="Speicherort und Dateiname wählen" \
        --filename="$DEFAULT" \
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

# Passt ein einzelnes PDF ($1) auf A4 an ($2), Orientierung bleibt erhalten.
# Identische Logik wie der Advanced-Merge-Pfad "A4 + Original-Ausrichtung".
auf_a4_anpassen() {
    local IN="$1" OUT="$2"
    local PAGE_DATA W H ROT GS_W GS_H
    PAGE_DATA=$(pdftk "$IN" dump_data)
    # pdftk formatiert große Zahlen mit Tausender-Komma (z.B. "2,250") – entfernen, sonst scheitert bc
    W=$(echo "$PAGE_DATA" | grep "PageMediaDimensions" | head -1 | awk '{print $2}' | tr -d ',')
    H=$(echo "$PAGE_DATA" | grep "PageMediaDimensions" | head -1 | awk '{print $3}' | tr -d ',')
    ROT=$(echo "$PAGE_DATA" | grep "PageMediaRotation" | head -1 | awk '{print $2}')

    if [ "$ROT" = "90" ] || [ "$ROT" = "270" ]; then
        local T="$W"; W="$H"; H="$T"
    fi

    if (( $(echo "$W > $H" | bc -l) )); then
        GS_W=841.89; GS_H=595.28
    else
        GS_W=595.28; GS_H=841.89
    fi

    gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite \
       -dPDFFitPage -dFIXEDMEDIA -dAutoRotatePages=/None \
       -dDEVICEWIDTHPOINTS="$GS_W" -dDEVICEHEIGHTPOINTS="$GS_H" \
       -sOutputFile="$OUT" "$IN" 2>/dev/null
}

# Dreht jede Seite von $1, die nicht in der Ausrichtung $ORIENT_OPT
# (hochformat/querformat) liegt, um 90° und schreibt das Ergebnis nach $2.
seiten_ausrichten() {
    local IN="$1" OUT="$2"
    local PAGE_COUNT
    PAGE_COUNT=$(pdftk "$IN" dump_data | grep "NumberOfPages" | awk '{print $2}')

    (
    ROTATED_PAGES=()
    for ((i=1; i<=PAGE_COUNT; i++)); do
        PAGE_PDF="$TMPDIR/page_${i}.pdf"
        PAGE_OUT="$TMPDIR/page_${i}_rot.pdf"
        pdftk "$IN" cat "$i" output "$PAGE_PDF"

        # Seitenmaße und Rotation auslesen
        PAGE_DATA=$(pdftk "$PAGE_PDF" dump_data)
        W=$(echo "$PAGE_DATA" | grep "PageMediaDimensions" | head -1 | awk '{print $2}' | tr -d ',')
        H=$(echo "$PAGE_DATA" | grep "PageMediaDimensions" | head -1 | awk '{print $3}' | tr -d ',')
        ROT=$(echo "$PAGE_DATA" | grep "PageMediaRotation" | head -1 | awk '{print $2}')

        # Bei Rotation 90°/270° sind Breite und Höhe effektiv vertauscht
        if [ "$ROT" = "90" ] || [ "$ROT" = "270" ]; then
            TEMP="$W"; W="$H"; H="$TEMP"
        fi

        # Aktuelle Orientierung feststellen
        IS_LANDSCAPE=0
        if (( $(echo "$W > $H" | bc -l) )); then
            IS_LANDSCAPE=1
        fi

        # Drehen nur wenn aktuelle Ausrichtung nicht passt.
        # "right" dreht relativ um +90°; "east" würde die Rotation absolut
        # auf 90° setzen und Seiten mit bestehender /Rotate 90 nicht drehen.
        if [ "$ORIENT_OPT" = "querformat" ] && [ "$IS_LANDSCAPE" = "0" ]; then
            pdftk "$PAGE_PDF" cat 1right output "$PAGE_OUT"
        elif [ "$ORIENT_OPT" = "hochformat" ] && [ "$IS_LANDSCAPE" = "1" ]; then
            pdftk "$PAGE_PDF" cat 1right output "$PAGE_OUT"
        else
            cp "$PAGE_PDF" "$PAGE_OUT"
        fi

        ROTATED_PAGES+=("$PAGE_OUT")
        echo $(( i * 100 / PAGE_COUNT ))
        echo "# Seite $i von $PAGE_COUNT wird ausgerichtet..."
    done

    pdftk "${ROTATED_PAGES[@]}" cat output "$OUT"
    echo "100"
    ) | zenity --progress \
        --title="Ausrichtung ändern" \
        --text="Seiten werden gedreht..." \
        --percentage=0 \
        --auto-close \
        --no-cancel \
        --width=350
}

# ══════════════════════════════════════════════════════════════════════════════
# QUICK MERGE – kein Dialog, direkt in Ordner der Quelldatei speichern
# ══════════════════════════════════════════════════════════════════════════════

quick_merge() {
    # Speicherort: Ordner der ersten Quelldatei, Dateiname Merge / Merge2 / Merge3 …
    local OUTDIR
    OUTDIR=$(dirname "${ORDERED_FILES[0]}")
    OUTPUT="$OUTDIR/Merge.pdf"
    if [ -f "$OUTPUT" ]; then
        local N=2
        while [ -f "$OUTDIR/Merge${N}.pdf" ]; do
            N=$((N+1))
        done
        OUTPUT="$OUTDIR/Merge${N}.pdf"
    fi

    TOTAL=${#ORDERED_FILES[@]}
    ERRORS_FILE="$TMPDIR/errors.txt"
    PDFTK_LOG="$TMPDIR/pdftk.log"

    (
    PDF_LIST=()
    ERRORS=()
    COUNTER=0

    for IDX in "${!ORDERED_FILES[@]}"; do
        FILE="${ORDERED_FILES[$IDX]}"
        CURRENT=$((IDX + 1))
        echo $(( CURRENT * 90 / TOTAL ))
        echo "# Datei $CURRENT von $TOTAL: $(esc "$(basename "$FILE")")"
        verarbeite_datei "$FILE"
    done

    # Fehler an Datei weitergeben (Subshell-Variablen gehen sonst verloren)
    if [ ${#ERRORS[@]} -gt 0 ]; then
        printf '%s\n' "${ERRORS[@]}" > "$ERRORS_FILE"
    fi

    echo "95"
    echo "# PDF wird zusammengefügt..."

    if [ ${#PDF_LIST[@]} -gt 0 ]; then
        pdftk "${PDF_LIST[@]}" cat output "$OUTPUT" 2> "$PDFTK_LOG"
    else
        echo "Keine verwertbaren Dateien gefunden." > "$PDFTK_LOG"
    fi
    echo "100"
    ) | zenity --progress \
        --title="PDF Quick Merge" \
        --text="Dateien werden verarbeitet..." \
        --percentage=0 \
        --auto-close \
        --no-cancel \
        --width=350

    # Ergebnis auswerten – außerhalb der Subshell, damit Fehler sichtbar sind
    ERROR_CONTENT=""
    [ -s "$ERRORS_FILE" ] && ERROR_CONTENT=$(esc "$(cat "$ERRORS_FILE")")

    if [ -f "$OUTPUT" ]; then
        if [ -n "$ERROR_CONTENT" ]; then
            zenity --warning \
                --title="Teilweise erfolgreich" \
                --text="PDF wurde erstellt, aber folgende Dateien konnten nicht konvertiert werden:\n\n$ERROR_CONTENT\n\nGespeichert als:\n<b>$(esc "$OUTPUT")</b>" \
                --width=450
        else
            zenity --info \
                --title="Fertig!" \
                --text="PDF erfolgreich erstellt:\n<b>$(esc "$OUTPUT")</b>" \
                --width=400
        fi
    else
        PDFTK_ERR=""
        [ -s "$PDFTK_LOG" ] && PDFTK_ERR=$(esc "$(cat "$PDFTK_LOG")")
        FEHLER_TEXT="PDF konnte nicht erstellt werden."
        [ -n "$ERROR_CONTENT" ] && FEHLER_TEXT="$FEHLER_TEXT\n\nFehlgeschlagene Dateien:\n$ERROR_CONTENT"
        [ -n "$PDFTK_ERR" ]     && FEHLER_TEXT="$FEHLER_TEXT\n\nDetails:\n$PDFTK_ERR"
        zenity --error \
            --title="Fehler" \
            --text="$FEHLER_TEXT" \
            --width=450
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

    # ── Speicherort: Default = Name der ersten Datei im Zielordner ───────────
    local DEFAULT_DIR DEFAULT_NAME
    DEFAULT_DIR=$(dirname "${ORDERED_FILES[0]}")
    DEFAULT_NAME=$(basename "${ORDERED_FILES[0]%.*}")
    speicherort_waehlen "$DEFAULT_DIR/$DEFAULT_NAME.pdf"

    konvertiere_dateien
    zusammenfuegen

    # ── Nachbearbeitung je nach Optionen ─────────────────────────────────────
    if [ "$SIZE_OPT" = "original" ] && [ "$ORIENT_OPT" = "original" ]; then
        # Keine Anpassung – direkt kopieren
        cp "$MERGED" "$OUTPUT"
    elif [ "$SIZE_OPT" = "a4" ] && [ "$ORIENT_OPT" = "original" ]; then
        # A4 + Original-Ausrichtung: jede Seite einzeln verarbeiten,
        # damit Querformat-Seiten als A4-Querformat erhalten bleiben
        PAGE_COUNT=$(pdftk "$MERGED" dump_data | grep "NumberOfPages" | awk '{print $2}')
        A4_PAGES=()

        (
        for ((i=1; i<=PAGE_COUNT; i++)); do
            PAGE_PDF="$TMPDIR/page_${i}.pdf"
            PAGE_A4="$TMPDIR/page_${i}_a4.pdf"
            pdftk "$MERGED" cat "$i" output "$PAGE_PDF"

            # Seitenmaße und Rotation auslesen
            PAGE_DATA=$(pdftk "$PAGE_PDF" dump_data)
            W=$(echo "$PAGE_DATA" | grep "PageMediaDimensions" | head -1 | awk '{print $2}' | tr -d ',')
            H=$(echo "$PAGE_DATA" | grep "PageMediaDimensions" | head -1 | awk '{print $3}' | tr -d ',')
            ROT=$(echo "$PAGE_DATA" | grep "PageMediaRotation" | head -1 | awk '{print $2}')

            # Bei Rotation 90°/270° sind Breite und Höhe vertauscht
            if [ "$ROT" = "90" ] || [ "$ROT" = "270" ]; then
                TEMP="$W"; W="$H"; H="$TEMP"
            fi

            # Querformat erkennen (effektive Breite > Höhe)
            if (( $(echo "$W > $H" | bc -l) )); then
                GS_W=841.89; GS_H=595.28
            else
                GS_W=595.28; GS_H=841.89
            fi

            gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite \
               -dPDFFitPage -dFIXEDMEDIA -dAutoRotatePages=/None \
               -dDEVICEWIDTHPOINTS="$GS_W" -dDEVICEHEIGHTPOINTS="$GS_H" \
               -sOutputFile="$PAGE_A4" "$PAGE_PDF"

            A4_PAGES+=("$PAGE_A4")
            echo $(( i * 100 / PAGE_COUNT ))
            echo "# Seite $i von $PAGE_COUNT wird auf A4 angepasst..."
        done

        pdftk "${A4_PAGES[@]}" cat output "$OUTPUT"
        echo "100"
        ) | zenity --progress \
            --title="A4-Anpassung" \
            --text="Seiten werden auf A4 angepasst..." \
            --percentage=0 \
            --auto-close \
            --no-cancel \
            --width=350
    elif [ "$SIZE_OPT" = "original" ] && [ "$ORIENT_OPT" != "original" ]; then
        # Original-Größe + feste Ausrichtung: nur drehen
        seiten_ausrichten "$MERGED" "$OUTPUT"
    else
        # A4 + feste Ausrichtung: erst falsch ausgerichtete Seiten drehen,
        # dann alle Seiten auf A4 in der gewünschten Ausrichtung einpassen
        ROTATED="$TMPDIR/rotated.pdf"
        seiten_ausrichten "$MERGED" "$ROTATED"

        GS_ARGS=(-dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -dPDFFitPage -dFIXEDMEDIA -dAutoRotatePages=/None)

        case "$ORIENT_OPT" in
            "hochformat")
                GS_ARGS+=(-dDEVICEWIDTHPOINTS=595.28 -dDEVICEHEIGHTPOINTS=841.89)
                ;;
            "querformat")
                GS_ARGS+=(-dDEVICEWIDTHPOINTS=841.89 -dDEVICEHEIGHTPOINTS=595.28)
                ;;
        esac

        [ -s "$ROTATED" ] && gs "${GS_ARGS[@]}" -sOutputFile="$OUTPUT" "$ROTATED"
    fi

    # Erfolg prüfen: Output-Datei muss existieren und nicht leer sein
    # ($? ist nach einer Pipe zu zenity unbrauchbar)
    if [ -s "$OUTPUT" ]; then
        zenity --info \
            --title="Fertig!" \
            --text="PDF erfolgreich erstellt:\n<b>$(esc "$OUTPUT")</b>" \
            --width=400
        [ "$OPEN_AFTER" = "yes" ] && xdg-open "$OUTPUT" &
    else
        zenity --error \
            --title="Fehler" \
            --text="PDF konnte nicht erstellt werden.\n\nDie Nachbearbeitung (Größe/Ausrichtung) ist fehlgeschlagen." \
            --width=450
    fi

    rm -rf "$TMPDIR"
}

# ══════════════════════════════════════════════════════════════════════════════
# BATCH CONVERT – jede Datei einzeln als PDF im selben Ordner speichern
# ══════════════════════════════════════════════════════════════════════════════

batch_convert() {
    TOTAL=${#ORDERED_FILES[@]}
    ERRORS_FILE="$TMPDIR/errors.txt"
    SKIPPED_FILE="$TMPDIR/skipped.txt"
    SUCCESS_FILE="$TMPDIR/success.txt"
    RENAMED_FILE="$TMPDIR/renamed.txt"

    (
    ERRORS=()
    SKIPPED=()
    RENAMED=()
    SUCCESS=0
    COUNTER=0

    for IDX in "${!ORDERED_FILES[@]}"; do
        FILE="${ORDERED_FILES[$IDX]}"
        CURRENT=$((IDX + 1))
        echo $(( CURRENT * 100 / TOTAL ))
        echo "# Datei $CURRENT von $TOTAL: $(esc "$(basename "$FILE")")"

        local OUTDIR FNAME EXT_LOWER OUT_PDF FILETYPE
        OUTDIR=$(dirname "$FILE")
        FNAME=$(basename "${FILE%.*}")
        EXT_LOWER=$(echo "${FILE##*.}" | tr '[:upper:]' '[:lower:]')
        # Vorhandene PDFs nie überschreiben: bericht.pdf → bericht (2).pdf
        OUT_PDF=$(freier_pdf_name "$OUTDIR" "$FNAME")
        SUCCESS_VORHER=$SUCCESS

        case "$EXT_LOWER" in
            pdf)
                SKIPPED+=("$(basename "$FILE")")
                ;;
            doc|docx|odt|ods|odp|pptx|xlsx|txt|rtf)
                if ! command -v libreoffice &>/dev/null; then
                    ERRORS+=("$(basename "$FILE") [LibreOffice nicht im PATH]")
                    continue
                fi
                COUNTER=$((COUNTER+1))
                LO_OUT="$TMPDIR/$FNAME.pdf"
                lo_konvertieren "$FILE" "$TMPDIR"
                if [ -f "$LO_OUT" ]; then
                    mv "$LO_OUT" "$OUT_PDF"
                    SUCCESS=$((SUCCESS+1))
                else
                    ERRORS+=("$(basename "$FILE")")
                fi
                ;;
            jpg|jpeg|png|gif|tiff|tif|bmp|webp)
                COUNTER=$((COUNTER+1))
                TMP_PDF="$TMPDIR/${COUNTER}_$FNAME.pdf"
                img2pdf "$FILE" -o "$TMP_PDF" 2>/dev/null
                if [ -f "$TMP_PDF" ]; then
                    auf_a4_anpassen "$TMP_PDF" "$OUT_PDF"
                    if [ -f "$OUT_PDF" ]; then
                        SUCCESS=$((SUCCESS+1))
                    else
                        ERRORS+=("$(basename "$FILE")")
                    fi
                else
                    ERRORS+=("$(basename "$FILE")")
                fi
                ;;
            *)
                FILETYPE=$(file --mime-type -b "$FILE")
                case "$FILETYPE" in
                    image/jpeg|image/png|image/gif|image/tiff|image/bmp|image/webp)
                        COUNTER=$((COUNTER+1))
                        TMP_PDF="$TMPDIR/${COUNTER}_$(basename "$FILE").pdf"
                        img2pdf "$FILE" -o "$TMP_PDF" 2>/dev/null
                        if [ -f "$TMP_PDF" ]; then
                            auf_a4_anpassen "$TMP_PDF" "$OUT_PDF"
                            if [ -f "$OUT_PDF" ]; then
                                SUCCESS=$((SUCCESS+1))
                            else
                                ERRORS+=("$(basename "$FILE")")
                            fi
                        else
                            ERRORS+=("$(basename "$FILE")")
                        fi
                        ;;
                    application/pdf)
                        SKIPPED+=("$(basename "$FILE")")
                        ;;
                    *)
                        ERRORS+=("$(basename "$FILE") [nicht unterstützt: $FILETYPE]")
                        ;;
                esac
                ;;
        esac

        # Nur erfolgreich erzeugte PDFs unter neuem Namen melden
        if [ "$SUCCESS" -gt "$SUCCESS_VORHER" ] && [ "$OUT_PDF" != "$OUTDIR/$FNAME.pdf" ]; then
            RENAMED+=("$(basename "$FILE") → $(basename "$OUT_PDF")")
        fi
    done

    echo "$SUCCESS" > "$SUCCESS_FILE"
    [ ${#ERRORS[@]} -gt 0 ]   && printf '%s\n' "${ERRORS[@]}"   > "$ERRORS_FILE"
    [ ${#SKIPPED[@]} -gt 0 ]  && printf '%s\n' "${SKIPPED[@]}"  > "$SKIPPED_FILE"
    [ ${#RENAMED[@]} -gt 0 ]  && printf '%s\n' "${RENAMED[@]}"  > "$RENAMED_FILE"
    echo "100"
    ) | zenity --progress \
        --title="Als PDF konvertieren" \
        --text="Dateien werden konvertiert..." \
        --percentage=0 \
        --auto-close \
        --no-cancel \
        --width=350

    SUCCESS_COUNT=0
    [ -f "$SUCCESS_FILE" ] && SUCCESS_COUNT=$(cat "$SUCCESS_FILE")
    ERROR_CONTENT=""
    [ -s "$ERRORS_FILE" ]  && ERROR_CONTENT=$(esc "$(cat "$ERRORS_FILE")")
    SKIPPED_CONTENT=""
    [ -s "$SKIPPED_FILE" ] && SKIPPED_CONTENT=$(esc "$(cat "$SKIPPED_FILE")")
    RENAMED_CONTENT=""
    [ -s "$RENAMED_FILE" ] && RENAMED_CONTENT=$(esc "$(cat "$RENAMED_FILE")")

    if [ "$SUCCESS_COUNT" -eq 0 ] && [ -z "$ERROR_CONTENT" ]; then
        zenity --info --title="Hinweis" \
            --text="Alle Dateien sind bereits PDFs – nichts zu konvertieren.\n\n$SKIPPED_CONTENT" \
            --width=400
    elif [ "$SUCCESS_COUNT" -gt 0 ] && [ -z "$ERROR_CONTENT" ]; then
        MSG="${SUCCESS_COUNT} Datei(en) erfolgreich konvertiert."
        [ -n "$RENAMED_CONTENT" ] && MSG="$MSG\n\nUnter neuem Namen gespeichert (PDF existierte bereits):\n$RENAMED_CONTENT"
        [ -n "$SKIPPED_CONTENT" ] && MSG="$MSG\n\nÜbersprungen (bereits PDF):\n$SKIPPED_CONTENT"
        zenity --info --title="Fertig!" --text="$MSG" --width=400
    elif [ "$SUCCESS_COUNT" -gt 0 ]; then
        MSG="${SUCCESS_COUNT} Datei(en) konvertiert.\n\nFehler bei:\n$ERROR_CONTENT"
        [ -n "$RENAMED_CONTENT" ] && MSG="$MSG\n\nUnter neuem Namen gespeichert:\n$RENAMED_CONTENT"
        [ -n "$SKIPPED_CONTENT" ] && MSG="$MSG\n\nÜbersprungen:\n$SKIPPED_CONTENT"
        zenity --warning --title="Teilweise erfolgreich" --text="$MSG" --width=450
    else
        zenity --error --title="Fehler" \
            --text="Keine Datei konvertiert.\n\n${ERROR_CONTENT}" \
            --width=450
    fi

    rm -rf "$TMPDIR"
}

# ══════════════════════════════════════════════════════════════════════════════
# Modus starten
# ══════════════════════════════════════════════════════════════════════════════

case "$MODE" in
    --quick)    quick_merge ;;
    --advanced) advanced_merge ;;
    --convert)  batch_convert ;;
    *)
        zenity --error --title="Fehler" --text="Unbekannter Modus: $(esc "$MODE")\n\nVerwendung:\n  $0 --quick DATEIEN...\n  $0 --advanced DATEIEN...\n  $0 --convert DATEIEN..."
        exit 1
        ;;
esac

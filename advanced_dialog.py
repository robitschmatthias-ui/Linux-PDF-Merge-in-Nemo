#!/usr/bin/env python3
"""
Kombinierter Dialog für PDF Advanced Merge:
- Dateiliste mit Drag & Drop zum Sortieren
- A4-Anpassung und Ausrichtung mit Tooltips

Aufruf:  python3 advanced_dialog.py datei1.pdf datei2.jpg ...
Ausgabe: Zeilenweise die sortierten Dateipfade, danach SIZE= und ORIENT=
Exit 0 = OK, 1 = Abbrechen
"""

import sys
import os

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, Pango


class AdvancedMergeDialog(Gtk.Window):
    def __init__(self, files):
        super().__init__(title="PDF Advanced Merge")
        self.set_default_size(600, 520)
        self.set_border_width(12)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect("delete-event", self.on_cancel)

        self.result_files = None
        self.result_size = None
        self.result_orient = None

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.add(main_box)

        # ── Dateiliste mit Drag & Drop ──────────────────────────────
        frame_files = Gtk.Frame(label="  Reihenfolge der Dateien  ")
        frame_files.set_shadow_type(Gtk.ShadowType.ETCHED_IN)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(200)

        # ListStore: Nr, Dateiname, voller Pfad
        self.store = Gtk.ListStore(int, str, str)
        for i, f in enumerate(files):
            self.store.append([i + 1, os.path.basename(f), f])

        self.treeview = Gtk.TreeView(model=self.store)
        self.treeview.set_reorderable(True)
        self.treeview.set_tooltip_text(
            "Dateien per Drag & Drop in die gewünschte Reihenfolge ziehen"
        )

        # Spalten
        renderer_nr = Gtk.CellRendererText()
        renderer_nr.set_property("xalign", 0.5)
        col_nr = Gtk.TreeViewColumn("Nr.", renderer_nr, text=0)
        col_nr.set_min_width(40)
        self.treeview.append_column(col_nr)

        renderer_name = Gtk.CellRendererText()
        renderer_name.set_property("ellipsize", Pango.EllipsizeMode.MIDDLE)
        col_name = Gtk.TreeViewColumn("Dateiname", renderer_name, text=1)
        col_name.set_expand(True)
        self.treeview.append_column(col_name)

        # Nummern aktualisieren nach Drag & Drop
        self.store.connect("row-deleted", self.on_reorder)

        scroll.add(self.treeview)
        frame_files.add(scroll)
        main_box.pack_start(frame_files, True, True, 0)

        # ── Optionen ────────────────────────────────────────────────
        options_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)

        # Seitengröße
        frame_size = Gtk.Frame(label="  Seitengröße  ")
        frame_size.set_shadow_type(Gtk.ShadowType.ETCHED_IN)
        box_size = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box_size.set_border_width(10)

        self.radio_no_resize = Gtk.RadioButton.new_with_label(
            None, "Keine Anpassung"
        )
        self.radio_no_resize.set_tooltip_text(
            "Die Seiten behalten ihre Originalgröße.\n"
            "Unterschiedliche Seitenformate bleiben erhalten."
        )

        self.radio_a4 = Gtk.RadioButton.new_with_label_from_widget(
            self.radio_no_resize, "Auf A4 anpassen"
        )
        self.radio_a4.set_tooltip_text(
            "Seiten werden auf A4-Format skaliert.\n\n"
            "• Große Seiten → auf A4 verkleinert (300 DPI)\n"
            "• Bilder ab 200 DPI auf A4 → hochskaliert\n"
            "• Bilder unter 200 DPI → Originalgröße,\n"
            "  zentriert auf A4-Seite"
        )

        box_size.pack_start(self.radio_no_resize, False, False, 0)
        box_size.pack_start(self.radio_a4, False, False, 0)
        frame_size.add(box_size)
        options_box.pack_start(frame_size, True, True, 0)

        # Ausrichtung
        frame_orient = Gtk.Frame(label="  Ausrichtung  ")
        frame_orient.set_shadow_type(Gtk.ShadowType.ETCHED_IN)
        box_orient = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box_orient.set_border_width(10)

        self.radio_original = Gtk.RadioButton.new_with_label(
            None, "Original beibehalten"
        )
        self.radio_original.set_tooltip_text(
            "Jede Seite behält ihre aktuelle Ausrichtung.\n"
            "Hochformat bleibt Hochformat,\n"
            "Querformat bleibt Querformat."
        )

        self.radio_portrait = Gtk.RadioButton.new_with_label_from_widget(
            self.radio_original, "Hochformat"
        )
        self.radio_portrait.set_tooltip_text(
            "Alle Seiten werden ins Hochformat gedreht.\n"
            "Seiten die bereits im Hochformat sind\n"
            "bleiben unverändert."
        )

        self.radio_landscape = Gtk.RadioButton.new_with_label_from_widget(
            self.radio_original, "Querformat"
        )
        self.radio_landscape.set_tooltip_text(
            "Alle Seiten werden ins Querformat gedreht.\n"
            "Seiten die bereits im Querformat sind\n"
            "bleiben unverändert."
        )

        box_orient.pack_start(self.radio_original, False, False, 0)
        box_orient.pack_start(self.radio_portrait, False, False, 0)
        box_orient.pack_start(self.radio_landscape, False, False, 0)
        frame_orient.add(box_orient)
        options_box.pack_start(frame_orient, True, True, 0)

        main_box.pack_start(options_box, False, False, 0)

        # ── Nach dem Merge öffnen ───────────────────────────────────
        self.check_open = Gtk.CheckButton(label="PDF nach dem Merge im Standard-Programm öffnen")
        self.check_open.set_tooltip_text(
            "Öffnet die fertige PDF-Datei direkt im\n"
            "Standard-PDF-Programm, z.B. um einzelne\n"
            "Seiten zu drehen oder zu verschieben."
        )
        main_box.pack_start(self.check_open, False, False, 0)

        # ── Buttons ─────────────────────────────────────────────────
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        button_box.set_halign(Gtk.Align.END)

        btn_cancel = Gtk.Button(label="Abbrechen")
        btn_cancel.connect("clicked", self.on_cancel)
        button_box.pack_start(btn_cancel, False, False, 0)

        btn_ok = Gtk.Button(label="Weiter")
        btn_ok.get_style_context().add_class("suggested-action")
        btn_ok.connect("clicked", self.on_ok)
        button_box.pack_start(btn_ok, False, False, 0)

        main_box.pack_start(button_box, False, False, 0)

        self.show_all()

    def on_reorder(self, *args):
        """Nummern nach Drag & Drop aktualisieren."""
        for i, row in enumerate(self.store):
            row[0] = i + 1

    def on_ok(self, *args):
        self.result_files = [row[2] for row in self.store]
        self.result_size = "a4" if self.radio_a4.get_active() else "original"
        self.result_open = self.check_open.get_active()

        if self.radio_portrait.get_active():
            self.result_orient = "hochformat"
        elif self.radio_landscape.get_active():
            self.result_orient = "querformat"
        else:
            self.result_orient = "original"

        Gtk.main_quit()

    def on_cancel(self, *args):
        Gtk.main_quit()
        return True


def main():
    files = sys.argv[1:]
    if not files:
        print("Keine Dateien angegeben.", file=sys.stderr)
        return 1

    dialog = AdvancedMergeDialog(files)
    Gtk.main()

    if dialog.result_files is None:
        return 1

    for f in dialog.result_files:
        print(f"FILE={f}")
    print(f"SIZE={dialog.result_size}")
    print(f"ORIENT={dialog.result_orient}")
    print(f"OPEN={'yes' if dialog.result_open else 'no'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
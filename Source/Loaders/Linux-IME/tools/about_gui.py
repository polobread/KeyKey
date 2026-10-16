"""GTK About window shared by Linux and FreeBSD desktops."""

from pathlib import Path
import sys

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GdkPixbuf, Gio, GLib, Gtk, Pango


class Application(Gtk.Application):
    def __init__(self, version):
        super().__init__(application_id="org.chichi77.KeyKey.About",
                         flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.version = version
        self.window = None

    def do_activate(self):
        if self.window:
            self.window.present()
            return
        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title("關於琦琦輸入法")
        self.window.set_default_size(520, 600)
        self.window.connect("destroy", self.window_closed)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.window.add(scroll)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, margin=24)
        scroll.add(box)
        resources = Path(__file__).resolve().parent
        try:
            logo = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                str(resources / "chichi77.png"), 80, 80, True)
            box.pack_start(Gtk.Image.new_from_pixbuf(logo), False, False, 0)
        except GLib.Error:
            pass
        title = Gtk.Label()
        title.set_markup('<span size="x-large" weight="bold">琦琦輸入法</span>')
        box.pack_start(title, False, False, 0)
        box.pack_start(Gtk.Label(label=f"版本 {self.version}", selectable=True), False, False, 0)
        links = Gtk.Box(spacing=16, halign=Gtk.Align.CENTER)
        links.add(Gtk.LinkButton.new_with_label(
            "https://github.com/polobread/KeyKey", "GitHub 專案首頁"))
        links.add(Gtk.LinkButton.new_with_label(
            "https://github.com/polobread/KeyKey/releases/latest", "最新正式版本"))
        box.pack_start(links, False, False, 0)
        heading = Gtk.Label(xalign=0)
        heading.set_markup("<b>開發初衷</b>")
        box.pack_start(heading, False, False, 0)
        try:
            motivation = (resources / "ProjectMotivation.txt").read_text(encoding="utf-8").strip()
        except OSError:
            motivation = "無法載入開發初衷。"
        introduction = Gtk.Label(label=motivation, xalign=0, wrap=True, selectable=True)
        introduction.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        introduction.set_max_width_chars(46)
        box.pack_start(introduction, False, False, 0)
        credits = Gtk.Label(
            label="以 OpenVanilla 專案為基礎\n原始碼來自 Yahoo! 奇摩輸入法（Yahoo! KeyKey）\n"
                  "© 2008–2010 Yahoo! Taiwan，依 New BSD 授權發布。",
            xalign=0, wrap=True, selectable=True)
        credits.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        credits.set_max_width_chars(46)
        box.pack_start(credits, False, False, 0)
        self.window.show_all()

    def window_closed(self, *_):
        self.window = None


def main(version):
    Application(version).run(sys.argv)

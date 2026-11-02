"""Shared About and update information window for Linux and FreeBSD."""

import argparse
from pathlib import Path
import sys

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, Gio, GLib, Gtk, Pango

import update_notify as updates
import update_notify_gui as updater


def create_panel(version):
    """Build the shared About content without creating another window."""
    scroll = Gtk.ScrolledWindow()
    scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
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
    box.pack_start(Gtk.Label(label=f"版本 {version}", selectable=True), False, False, 0)
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
    return scroll


class Application(Gtk.Application):
    def __init__(self, version, system, executable, get=updates.fetch,
                 timeout=updates.CHECK_TIMEOUT, sync_preferences=None):
        super().__init__(application_id="org.chichi77.KeyKey.Information",
                         flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.version, self.system, self.executable = version, system, executable
        self.get, self.timeout = get, timeout
        self.sync_preferences = sync_preferences
        self.window = None
        self.notebook = None
        self.about_panel = None
        self.updates_panel = None

    def do_command_line(self, command_line):
        parser = argparse.ArgumentParser(prog="keykey-about")
        parser.add_argument("--section", choices=("about", "updates"), default="about")
        try:
            options = parser.parse_args(command_line.get_arguments()[1:])
        except SystemExit as error:
            return error.code
        self.activate()
        self.select_section(options.section)
        return 0

    def do_activate(self):
        if self.window:
            self.updates_panel.refresh()
            self.window.present()
            return
        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title("琦琦輸入法 — 關於與更新")
        self.window.set_default_size(620, 650)
        self.window.connect("destroy", self.window_closed)
        self.notebook = Gtk.Notebook()
        self.about_panel = create_panel(self.version)
        self.updates_panel = updater.create_embedded_panel(
            self.version, self.system, self.executable, self.window,
            get=self.get, timeout=self.timeout, sync_preferences=self.sync_preferences)
        self.notebook.append_page(self.about_panel, Gtk.Label(label="關於"))
        self.notebook.append_page(self.updates_panel, Gtk.Label(label="檢查更新"))
        self.notebook.connect("switch-page", self.section_changed)
        self.window.add(self.notebook)
        self.window.show_all()

    def section_changed(self, _notebook, _page, page_num):
        if page_num == 1 and self.updates_panel:
            self.updates_panel.refresh()

    def select_section(self, section):
        if self.notebook:
            self.notebook.set_current_page(1 if section == "updates" else 0)
            if section == "updates":
                self.updates_panel.controller.check_button.grab_focus()
            else:
                self.about_panel.grab_focus()

    def window_closed(self, *_):
        if self.updates_panel:
            self.updates_panel.dispose()
        self.window = None
        self.notebook = None
        self.about_panel = None
        self.updates_panel = None


def main(version, system, executable, section="about"):
    arguments = list(sys.argv)
    if not any(value == "--section" or value.startswith("--section=")
               for value in arguments[1:]):
        arguments.extend(["--section", section])
    return Application(version, system, executable).run(arguments)

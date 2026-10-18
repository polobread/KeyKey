"""Cangjie settings shared by Linux/FreeBSD; preserve unrelated Fcitx options."""
import configparser
import io
import os
from pathlib import Path
import tempfile

def config_path():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "fcitx5/conf/chichi77-keykey.conf"

def read_config(path):
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    if path.exists():
        parser.read_string("[__KeyKeyRoot__]\n" + path.read_text(encoding="utf-8"))
    return parser

def load(path):
    parser = read_config(path)
    def flag(key, default):
        return parser.getboolean("Cangjie", key, fallback=default)
    realtime = flag("ComposeWhileTyping", False)
    return realtime, flag("PrefixCandidates", False), flag("ClearOnError", True) and not realtime

def save(path, realtime, prefix, clear):
    parser = read_config(path)
    if not parser.has_section("Cangjie"):
        parser.add_section("Cangjie")
    for key, value in (("ComposeWhileTyping", realtime), ("PrefixCandidates", prefix),
                       ("ClearOnError", clear and not realtime)):
        parser.set("Cangjie", key, str(bool(value)))
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            serialized = io.StringIO()
            parser.write(serialized, space_around_delimiters=False)
            stream.write(serialized.getvalue().removeprefix("[__KeyKeyRoot__]\n"))
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)

def create_window(path, reload_config=lambda: None):
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk
    window = Gtk.Window(title="倉頡設定")
    window.set_default_size(420, 240)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=20)
    window.add(box)
    realtime = Gtk.CheckButton(label="即時候選")
    prefix = Gtk.CheckButton(label="未打完也能選字")
    clear = Gtk.CheckButton(label="錯碼清除")
    for control, enabled in zip((realtime, prefix, clear), load(path)):
        control.set_active(enabled)
        box.pack_start(control, False, False, 0)
    prefix.set_sensitive(realtime.get_active())
    changing = False
    def changed(sender):
        nonlocal changing
        if changing:
            return
        changing = True
        if sender is realtime and realtime.get_active():
            clear.set_active(False)
        if sender is clear and clear.get_active():
            realtime.set_active(False)
        prefix.set_sensitive(realtime.get_active())
        changing = False
    realtime.connect("toggled", changed)
    clear.connect("toggled", changed)
    help_text = Gtk.Label(label="即時候選與錯碼清除互斥。\n開啟即時候選後，才能使用前綴候選。", xalign=0)
    box.pack_start(help_text, False, False, 0)
    status = Gtk.Label(xalign=0)
    box.pack_start(status, False, False, 0)
    apply_button = Gtk.Button(label="套用")
    def apply(_button):
        try:
            save(path, realtime.get_active(), prefix.get_active(), clear.get_active())
            reload_config()
            status.set_text("已儲存")
        except (OSError, configparser.Error) as error:
            status.set_text("儲存失敗：" + str(error))
    apply_button.connect("clicked", apply)
    box.pack_start(apply_button, False, False, 0)
    return window, realtime, prefix, clear, apply_button

def main():
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gio, GLib, Gtk
    def reload_config():
        try:
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            bus.call_sync("org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1",
                          "ReloadAddonConfig", GLib.Variant("(s)", ("chichi77-keykey",)),
                          None, Gio.DBusCallFlags.NONE, 1000, None)
        except GLib.Error:
            pass # A stopped Fcitx reads the saved values on its next startup.
    window, *_controls = create_window(config_path(), reload_config)
    window.connect("destroy", Gtk.main_quit)
    window.show_all()
    Gtk.main()

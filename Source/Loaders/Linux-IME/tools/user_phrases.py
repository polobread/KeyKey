"""Native user phrase editor. All data operations go through Guanyinma's CLI."""
import json
import subprocess
import threading


class PhraseError(Exception):
    pass


class PhraseBackend:
    def __init__(self, executable="keykey-smart-phrases", environment=None):
        self.executable = str(executable)
        self.environment = environment

    def run(self, *arguments):
        try:
            result = subprocess.run([self.executable, *arguments], env=self.environment,
                                    capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise PhraseError(str(error)) from error
        if result.returncode:
            raise PhraseError((result.stderr or result.stdout).strip() or "詞庫操作失敗")
        return result.stdout

    def rows(self):
        try:
            rows = json.loads(self.run("list", "--json"))
            if not isinstance(rows, list) or any(
                not isinstance(row, dict) or
                not all(isinstance(row.get(key), str) for key in ("text", "reading"))
                for row in rows
            ):
                raise ValueError("無效詞庫資料")
            return [(row["text"], row["reading"]) for row in rows]
        except (ValueError, TypeError) as error:
            raise PhraseError("無法讀取自訂詞清單：" + str(error)) from error

    def readings(self, text):
        try:
            values = json.loads(self.run("readings", text))
            if not isinstance(values, list) or not all(isinstance(value, str) for value in values):
                raise ValueError("無效讀音資料")
            return values
        except (ValueError, TypeError) as error:
            raise PhraseError("無法查詢讀音：" + str(error)) from error


def reload_fcitx():
    from gi.repository import Gio, GLib
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        bus.call_sync("org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1",
                      "ReloadAddonConfig", GLib.Variant("(s)", ("chichi77-keykey",)),
                      None, Gio.DBusCallFlags.NONE, 1000, None)
    except GLib.Error:
        pass  # The next session also reads the saved database.


def create_window(backend=None, notify=reload_fcitx):
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import GLib, Gtk

    class Editor(Gtk.Dialog):
        def __init__(self, parent, original=None):
            super().__init__(title="編輯自訂詞" if original else "新增自訂詞",
                             transient_for=parent, modal=True)
            self.owner = parent
            self.original = original
            self.add_button("取消", Gtk.ResponseType.CANCEL)
            self.add_button("儲存", Gtk.ResponseType.OK)
            self.set_default_response(Gtk.ResponseType.OK)
            grid = Gtk.Grid(column_spacing=12, row_spacing=12, margin=16)
            self.get_content_area().add(grid)
            self.phrase = Gtk.Entry()
            self.phrase.set_hexpand(True)
            self.phrase.set_activates_default(True)
            self.reading = Gtk.ComboBoxText.new_with_entry()
            self.reading.set_hexpand(True)
            self.lookup = Gtk.Button(label="查詢讀音")
            self.message = Gtk.Label(xalign=0, wrap=True)
            for row, (label, control) in enumerate((("詞語", self.phrase), ("注音讀音", self.reading))):
                grid.attach(Gtk.Label(label=label, xalign=0), 0, row, 1, 1)
                grid.attach(control, 1, row, 1, 1)
            grid.attach(self.lookup, 2, 1, 1, 1)
            grid.attach(Gtk.Label(label="每個字對應一個注音音節，以空白分隔；可選讀音或自行修正。",
                                  xalign=0, wrap=True), 0, 2, 3, 1)
            grid.attach(self.message, 0, 3, 3, 1)
            if original:
                self.phrase.set_text(original[0])
                self.reading.get_child().set_text(original[1])
            self.lookup.connect("clicked", self.find_readings)
            self.connect("response", self.respond)
            self.connect("destroy", lambda _dialog: setattr(parent, "editor", None))
            self.show_all()

        def find_readings(self, _button):
            text = self.phrase.get_text().strip()
            if not text:
                self.message.set_text("請先輸入詞語。")
                return
            self.set_response_sensitive(Gtk.ResponseType.OK, False)
            self.lookup.set_sensitive(False)
            self.message.set_text("正在查詢…")
            def complete(values, error):
                if self.owner.editor is not self:
                    return
                self.set_response_sensitive(Gtk.ResponseType.OK, True)
                self.lookup.set_sensitive(True)
                if error:
                    self.message.set_text(str(error))
                    return
                if self.phrase.get_text().strip() != text:
                    self.message.set_text("詞語已變更，請重新查詢讀音。")
                    return
                self.reading.remove_all()
                for value in values:
                    self.reading.append_text(value)
                if values:
                    self.reading.set_active(0)
                self.message.set_text("請確認實際使用的讀音。" if values else "詞庫沒有讀音，請自行輸入。")
            self.owner.job(lambda: self.owner.backend.readings(text), complete, busy=False)

        def respond(self, _dialog, response):
            if response != Gtk.ResponseType.OK:
                self.destroy()
                return
            text = self.phrase.get_text().strip()
            reading = self.reading.get_child().get_text().strip()
            if not text or not reading:
                self.message.set_text("請填入詞語與讀音。")
                return
            command = ("update", *self.original, text, reading) if self.original else ("add", text, reading)
            self.set_response_sensitive(Gtk.ResponseType.OK, False)
            self.set_response_sensitive(Gtk.ResponseType.CANCEL, False)
            self.lookup.set_sensitive(False)
            def complete(_result, error):
                current = self.owner.editor is self
                if error:
                    if current:
                        self.set_response_sensitive(Gtk.ResponseType.OK, True)
                        self.set_response_sensitive(Gtk.ResponseType.CANCEL, True)
                        self.lookup.set_sensitive(True)
                        self.message.set_text(str(error))
                    else:
                        self.owner.status.set_text("儲存失敗：" + str(error))
                    return
                if current:
                    self.destroy()
                self.owner.changed("已儲存自訂詞。")
            self.owner.job(lambda: self.owner.backend.run(*command), complete)

    class Window(Gtk.Window):
        def __init__(self):
            super().__init__(title="琦琦輸入法 — 自訂詞與學習")
            self.set_default_size(760, 520)
            self.backend = backend or PhraseBackend()
            self.editor = None
            self.closed = False
            self.busy = False
            self.controls = []
            self.connect("destroy", lambda _window: setattr(self, "closed", True))
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=16)
            self.add(box)
            box.pack_start(Gtk.Label(label="管理自訂詞；內建詞庫為唯讀。", xalign=0), False, False, 0)
            self.search = Gtk.SearchEntry(placeholder_text="搜尋詞語或讀音")
            box.pack_start(self.search, False, False, 0)
            self.store = Gtk.ListStore(str, str)
            self.filtered = self.store.filter_new()
            self.filtered.set_visible_func(lambda model, iterator, _data: not self.search.get_text() or
                any(self.search.get_text().casefold() in model[iterator][column].casefold() for column in (0, 1)))
            self.search.connect("search-changed", lambda _entry: self.filtered.refilter())
            self.view = Gtk.TreeView(model=self.filtered)
            self.view.set_headers_visible(True)
            for column, title in enumerate(("詞語", "注音讀音")):
                renderer = Gtk.CellRendererText()
                cell = Gtk.TreeViewColumn(title, renderer, text=column)
                cell.set_expand(True)
                self.view.append_column(cell)
            self.view.connect("row-activated", lambda *_args: self.edit())
            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
            scroll.add(self.view)
            box.pack_start(scroll, True, True, 0)
            toolbar = Gtk.Box(spacing=8)
            box.pack_start(toolbar, False, False, 0)
            for label, callback, name in (("新增", lambda: self.open_editor(), "add_button"),
                                          ("編輯", self.edit, "edit_button"),
                                          ("刪除", self.remove, "remove_button"),
                                          ("重新整理", self.refresh, "refresh_button")):
                button = self.button(toolbar, label, callback)
                setattr(self, name, button)
            archive = Gtk.Box(spacing=8)
            box.pack_start(archive, False, False, 0)
            for label, callback in (("匯入備份…", lambda: self.choose_file("import")),
                                    ("匯出完整備份…", lambda: self.choose_file("export")),
                                    ("重設好打學習…", self.reset_learning)):
                self.button(archive, label, callback)
            self.status = Gtk.Label(xalign=0, wrap=True, selectable=True)
            box.pack_start(self.status, False, False, 0)
            self.refresh()

        def button(self, box, label, callback):
            button = Gtk.Button(label=label)
            button.connect("clicked", lambda _button: callback())
            box.pack_start(button, False, False, 0)
            self.controls.append(button)
            return button

        def job(self, operation, callback, busy=True):
            if busy:
                self.busy = True
                for control in self.controls:
                    control.set_sensitive(False)
            def finish(value, error):
                if self.closed:
                    return GLib.SOURCE_REMOVE
                if busy:
                    self.busy = False
                    for control in self.controls:
                        control.set_sensitive(True)
                callback(value, error)
                return GLib.SOURCE_REMOVE
            def worker():
                try:
                    value, error = operation(), None
                except Exception as failure:
                    value, error = None, failure
                GLib.idle_add(finish, value, error)
            threading.Thread(target=worker, daemon=True).start()

        def refresh(self, message=""):
            self.status.set_text("正在讀取詞庫…")
            def complete(rows, error):
                if error:
                    self.status.set_text("讀取失敗：" + str(error))
                    return
                self.store.clear()
                for row in rows:
                    self.store.append(row)
                self.status.set_text((message + " ").lstrip() + "共 " + str(len(rows)) + " 筆自訂詞。")
            self.job(self.backend.rows, complete)

        def changed(self, message):
            notify()
            self.refresh(message)

        def selected(self):
            model, iterator = self.view.get_selection().get_selected()
            return tuple(model[iterator]) if iterator else None

        def open_editor(self, original=None):
            if self.busy or self.editor:
                return
            self.editor = Editor(self, original)

        def edit(self):
            row = self.selected()
            if row:
                self.open_editor(row)
            else:
                self.status.set_text("請先選擇自訂詞。")

        def confirm(self, message, action):
            dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
                                       buttons=Gtk.ButtonsType.OK_CANCEL, text=message)
            def respond(_dialog, response):
                dialog.destroy()
                if response == Gtk.ResponseType.OK:
                    action()
            dialog.connect("response", respond)
            dialog.show_all()

        def command(self, arguments, message):
            self.status.set_text("正在處理…")
            def complete(_value, error):
                if error:
                    self.status.set_text("操作失敗：" + str(error))
                else:
                    self.changed(message)
            self.job(lambda: self.backend.run(*arguments), complete)

        def remove(self):
            row = self.selected()
            if row:
                self.confirm("刪除自訂詞「" + row[0] + "」？", lambda: self.command(("remove", *row), "已刪除。"))
            else:
                self.status.set_text("請先選擇自訂詞。")

        def reset_learning(self):
            self.confirm("清除好打注音的選字與相鄰詞學習？自訂詞會保留。",
                         lambda: self.command(("reset-learning",), "已重設好打學習。"))

        def choose_file(self, command):
            exporting = command == "export"
            chooser = Gtk.FileChooserDialog(title="匯出完整備份" if exporting else "匯入詞庫",
                transient_for=self, action=Gtk.FileChooserAction.SAVE if exporting else Gtk.FileChooserAction.OPEN)
            chooser.add_buttons("取消", Gtk.ResponseType.CANCEL,
                                "匯出" if exporting else "匯入", Gtk.ResponseType.OK)
            if exporting:
                chooser.set_current_name("keykey-user-data.json")
                chooser.set_do_overwrite_confirmation(True)
            pattern = Gtk.FileFilter()
            pattern.set_name("JSON 備份")
            pattern.add_pattern("*.json")
            chooser.add_filter(pattern)
            all_files = Gtk.FileFilter()
            all_files.set_name("所有檔案")
            all_files.add_pattern("*")
            chooser.add_filter(all_files)
            def respond(_chooser, response):
                filename = chooser.get_filename() if response == Gtk.ResponseType.OK else None
                chooser.destroy()
                if not filename:
                    return
                action = lambda: self.command((command, filename), "已匯出備份。" if exporting else "已匯入。")
                if exporting:
                    action()
                else:
                    self.confirm("匯入會合併自訂詞，並更新來源包含的學習紀錄。來源檔案保持不變。", action)
            chooser.connect("response", respond)
            chooser.show_all()

    window = Window()
    return window


def main():
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk
    window = create_window()
    window.connect("destroy", Gtk.main_quit)
    window.show_all()
    Gtk.main()

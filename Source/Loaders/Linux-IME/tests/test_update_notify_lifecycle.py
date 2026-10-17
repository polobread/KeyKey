#!/usr/bin/env python3
"""Exercise real query control with a headless event loop (no GTK/network)."""
import importlib.util
import os
from pathlib import Path
import queue
import sys
import tempfile
import threading
import time
import types
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import update_notify as updates
from test_update_notify import feed


class Loop:
    SOURCE_REMOVE = False

    def __init__(self):
        self.pending = queue.Queue()
        self.timers = {}
        self.serial = 0
        self.completed = 0

    def idle_add(self, callback, *args):
        self.pending.put((callback, args))

    def timeout_add(self, milliseconds, callback, *args):
        self.serial += 1
        self.timers[self.serial] = milliseconds, callback, args
        return self.serial

    def source_remove(self, timer):
        self.timers.pop(timer, None)

    def expire(self, timer):
        _, callback, args = self.timers.pop(timer)
        callback(*args)

    def pump_until(self, ready):
        deadline = time.monotonic() + 2
        while not ready() and time.monotonic() < deadline:
            try:
                callback, args = self.pending.get(timeout=0.01)
                callback(*args)
                self.completed += 1
            except queue.Empty:
                pass
        if not ready():
            raise AssertionError("Worker completion timed out")


class ApplicationBase:
    def __init__(self, **kwargs):
        self.holds = 0

    def hold(self):
        self.holds += 1

    def release(self):
        self.holds -= 1


class Label:
    def set_text(self, value):
        self.text = value


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = patch.dict(os.environ, {"XDG_STATE_HOME": self.temp.name,
                                          "XDG_CONFIG_HOME": self.temp.name})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.loop = Loop()
        gi = types.SimpleNamespace(require_version=lambda *_: None)
        repository = types.SimpleNamespace(
            GLib=self.loop, Gio=types.SimpleNamespace(ApplicationFlags=types.SimpleNamespace(HANDLES_COMMAND_LINE=1)),
            Gtk=types.SimpleNamespace(Application=ApplicationBase))
        spec = importlib.util.spec_from_file_location("headless_update_gui", TOOLS / "update_notify_gui.py")
        self.gui = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"gi": gi, "gi.repository": repository}):
            spec.loader.exec_module(self.gui)
        self.requests = []
        self.block = threading.Event()
        self.addCleanup(self.block.set)

    def app(self, get):
        app = self.gui.Application("1.3.1", "FreeBSD", "/usr/bin/keykey-update-notify", get)
        app.window = object()
        app.status = Label()
        app.refresh_buttons = lambda: None  # Native widget rendering has separate GTK tests.
        return app

    def blocked_get(self, url):
        self.requests.append(url)
        self.block.wait(2)
        return feed()

    def test_ten_second_deadline_does_not_block_ui_or_retry(self):
        app = self.app(self.blocked_get)
        app.check(True)
        self.assertEqual(self.loop.timers[app.check_timeout][0], 10000)
        self.loop.pump_until(lambda: bool(self.requests))
        heartbeat = []
        self.loop.idle_add(heartbeat.append, True)
        self.loop.pump_until(lambda: bool(heartbeat))
        self.assertTrue(app.busy)
        self.loop.expire(app.check_timeout)
        self.assertFalse(app.busy)
        self.assertIn("逾時", app.status.text)
        self.assertEqual(app.holds, 0)
        self.assertEqual(len(self.requests), 1)
        self.assertTrue(app.check_cancelled.is_set())

    def test_manual_retry_ignores_old_worker_completion(self):
        app = self.app(self.blocked_get)
        app.check(True)
        self.loop.pump_until(lambda: bool(self.requests))
        expired = app.active_check
        self.loop.expire(app.check_timeout)
        app.get = lambda _: feed()
        app.check(True)
        self.loop.pump_until(lambda: not app.busy)
        app.checked({"version": "99.0.0"}, False, True, expired)
        self.assertIsNone(app.result)
        self.assertIn("沒有較新", app.status.text)
        completed = self.loop.completed
        self.block.set()
        self.loop.pump_until(lambda: self.loop.completed > completed)
        self.assertEqual(app.holds, 0)
        self.assertIn("沒有較新", app.status.text)

    def test_close_cancels_request_and_drops_late_result(self):
        app = self.app(self.blocked_get)
        app.check(True)
        self.loop.pump_until(lambda: bool(self.requests))
        expired = app.active_check
        app.window_closed()
        self.assertFalse(app.busy)
        self.assertIsNone(app.check_timeout)
        self.assertEqual(app.holds, 0)
        app.checked({"version": "99.0.0"}, False, True, expired)
        self.assertIsNone(app.result)

    def test_unexpected_worker_error_allows_retry(self):
        def fail(_):
            raise RuntimeError("inert worker failure")
        app = self.app(fail)
        app.check(True)
        self.loop.pump_until(lambda: not app.busy)
        self.assertIn("檢查失敗", app.status.text)
        app.get = lambda _: feed()
        app.check(True)
        self.loop.pump_until(lambda: not app.busy)
        self.assertIn("沒有較新", app.status.text)
        self.assertEqual(app.holds, 0)


if __name__ == "__main__":
    unittest.main()

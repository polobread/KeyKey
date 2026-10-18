import configparser
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from cangjie_settings import load, save, read_config, create_window

class CangjieSettingsTest(unittest.TestCase):
    def test_defaults_persistence_and_unrelated_options(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.conf"
            self.assertEqual(load(path), (False, False, True))
            path.write_text("BopomofoLayout=Standard\n[Other]\nKeep=你好\n", encoding="utf-8")
            save(path, True, True, True)
            self.assertEqual(load(path), (True, True, False))
            self.assertEqual(read_config(path)["Other"]["Keep"], "你好")
            self.assertTrue(path.read_text().startswith("BopomofoLayout=Standard\n"))
            save(path, False, True, True)
            self.assertEqual(load(path), (False, True, True))

    def test_widgets_dependency_exclusion_and_apply(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.conf"
            reloads = []
            window, realtime, prefix, clear, apply = create_window(path, lambda: reloads.append(True))
            try:
                self.assertFalse(realtime.get_active())
                self.assertFalse(prefix.get_sensitive())
                self.assertTrue(clear.get_active())
                realtime.set_active(True)
                self.assertTrue(prefix.get_sensitive())
                self.assertFalse(clear.get_active())
                prefix.set_active(True)
                clear.set_active(True)
                self.assertFalse(realtime.get_active())
                self.assertFalse(prefix.get_sensitive())
                self.assertTrue(prefix.get_active())
                apply.clicked()
                self.assertEqual(load(path), (False, True, True))
                realtime.set_active(True)
                self.assertTrue(prefix.get_active())
                self.assertTrue(prefix.get_sensitive())
                self.assertFalse(clear.get_active())
                apply.clicked()
                self.assertEqual(load(path), (True, True, False))
                self.assertEqual(len(reloads), 2)
            finally:
                window.destroy()

if __name__ == "__main__":
    unittest.main()

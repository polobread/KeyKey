#!/usr/bin/env python3
"""Exercise the installed CLI contract against separate real stores."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    executable, model = map(lambda p: Path(p).resolve(), sys.argv[1:3])
    with tempfile.TemporaryDirectory(prefix="keykey-phrase-cli-") as temporary:
        root = Path(temporary)
        data = root / "data"
        data.mkdir()
        (data / "smart-mandarin.db").symlink_to(model)
        legacy = root / "legacy.db"
        rust = root / "rust.db"
        environment = dict(os.environ, CHICHI77_KEYKEY_DATA_DIR=str(data),
                           XDG_DATA_HOME=str(root / "normal-data"),
                           CHICHI77_KEYKEY_USER_DB=str(legacy),
                           CHICHI77_KEYKEY_GUANYINMA_USER_DB=str(rust))

        def run(*args, success=True, env=None):
            result = subprocess.run([str(executable), *args], env=env or environment,
                                    text=True, capture_output=True, timeout=20)
            assert (result.returncode == 0) == success, (args, result.stdout, result.stderr)
            return result.stdout

        run("add", "詞語", "ㄘˊ ㄩˇ")
        original = hashlib.sha256(legacy.read_bytes()).hexdigest()
        assert "詞語" in run("list")
        assert "詞語" in run("--core", "legacy", "list")
        assert not run("--core", "guanyinma", "list").strip()
        run("--core", "guanyinma", "import-legacy", str(legacy))
        assert "詞語" in run("--core", "guanyinma", "list")
        run("--core", "guanyinma", "add", "琦琦星", "ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ")
        run("--core", "guanyinma", "update", "琦琦星", "ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ", "琦琦光", "ㄑㄧˊ ㄑㄧˊ ㄍㄨㄤ")
        rows = run("--core", "guanyinma", "list")
        assert "琦琦光" in rows and "琦琦星" not in rows
        backup = root / "備份.json"
        run("--core", "guanyinma", "export", str(backup))
        archive = json.loads(backup.read_text())
        assert archive["format"] == "guanyinma_user_data"
        assert set(archive) == {"format", "schema_version", "phrases", "smart", "table"}
        assert "generation" not in backup.read_text() and "revision" not in backup.read_text()
        assert backup.stat().st_mode & 0o077 == 0
        run("--core", "guanyinma", "reset-learning")
        assert run("--core", "guanyinma", "list") == rows
        run("--core", "guanyinma", "remove", "琦琦光", "ㄑㄧˊ ㄑㄧˊ ㄍㄨㄤ")
        run("--core", "guanyinma", "import", str(backup))
        assert run("--core", "guanyinma", "list") == rows
        invalid = root / "invalid.json"
        invalid.write_text('{"format":"guanyinma_user_data","schema_version":1,"phrases":[{}]}')
        run("--core", "guanyinma", "import", str(invalid), success=False)
        assert run("--core", "guanyinma", "list") == rows
        run("--core", "guanyinma", "add", "字數錯誤", "ㄗˋ", success=False)
        for protected in (model, legacy, rust, Path(str(rust) + "-wal")):
            run("--core", "guanyinma", "export", str(protected), success=False)
        normal = root / "normal-data/chichi77-keykey"
        normal.mkdir(parents=True)
        for name in ("smart-mandarin-user.db", "guanyinma-user.db"):
            protected = normal / name
            protected.write_bytes(legacy.read_bytes())
            before = protected.read_bytes()
            run("--core", "guanyinma", "export", str(protected), success=False)
            assert protected.read_bytes() == before
        alias = root / "alias.json"
        alias.symlink_to(legacy)
        run("--core", "guanyinma", "export", str(alias), success=False)
        alias.unlink()
        os.link(legacy, alias)
        run("--core", "guanyinma", "export", str(alias), success=False)
        bad_environment = dict(environment, CHICHI77_KEYKEY_GUANYINMA_USER_DB=str(legacy))
        run("--core", "guanyinma", "list", success=False, env=bad_environment)
        assert hashlib.sha256(legacy.read_bytes()).hexdigest() == original
        assert "琦琦光" not in run("list")
        print("CLI CRUD, backup/import, explicit legacy migration and file protection passed")


if __name__ == "__main__":
    main()

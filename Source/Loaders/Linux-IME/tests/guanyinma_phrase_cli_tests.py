#!/usr/bin/env python3
"""Exercise the installed CLI contract against an isolated real Guanyinma store."""
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
        rust = root / "rust.db"
        environment = dict(os.environ, CHICHI77_KEYKEY_DATA_DIR=str(data),
                           XDG_DATA_HOME=str(root / "normal-data"),
                           CHICHI77_KEYKEY_GUANYINMA_USER_DB=str(rust))

        def run(*args, success=True, env=None):
            result = subprocess.run([str(executable), *args], env=env or environment,
                                    text=True, capture_output=True, timeout=20)
            assert (result.returncode == 0) == success, (args, result.stdout, result.stderr)
            return result.stdout

        for core in ("guanyinma", "legacy"):
            run("--core", core, "list", success=False)
        assert not rust.exists()

        run("add", "琦琦雲", "ㄑㄧˊ ㄑㄧˊ ㄩㄣˊ")
        assert rust.exists()
        initial = json.loads(run("list", "--json"))
        assert initial[0]["text"] == "琦琦雲" and initial[0]["reading"] == "ㄑㄧˊ ㄑㄧˊ ㄩㄣˊ"
        assert "ㄑㄧˊ ㄑㄧˊ ㄩㄣˊ" in json.loads(run("readings", "琦琦雲"))
        run("remove", "琦琦雲", "ㄑㄧˊ ㄑㄧˊ ㄩㄣˊ")
        assert not run("list").strip()
        run("add", "你好", "ㄋㄧˇ ㄏㄠˇ", success=False)
        run("remove", "琦琦雲", "ㄑㄧˊ ㄑㄧˊ ㄩㄣˊ", success=False)
        unsupported = root / "unsupported-input.db"
        original_source = b"not a supported backup"
        unsupported.write_bytes(original_source)
        original_store = rust.read_bytes()
        run("import-legacy", str(unsupported), success=False)
        for core in ("guanyinma", "legacy"):
            run("--core", core, "list", success=False)
        assert unsupported.read_bytes() == original_source and rust.read_bytes() == original_store
        run("add", "琦琦星", "ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ")
        run("update", "琦琦星", "ㄑㄧˊ ㄑㄧˊ ㄒㄧㄥ", "琦琦光", "ㄑㄧˊ ㄑㄧˊ ㄍㄨㄤ")
        rows = run("list")
        assert "琦琦光" in rows and "琦琦星" not in rows
        backup = root / "備份.json"
        run("export", str(backup))
        archive = json.loads(backup.read_text())
        assert archive["format"] == "guanyinma_user_data"
        assert set(archive) == {"format", "schema_version", "phrases", "smart", "table"}
        assert "generation" not in backup.read_text() and "revision" not in backup.read_text()
        assert backup.stat().st_mode & 0o077 == 0
        run("reset-learning")
        assert run("list") == rows
        run("remove", "琦琦光", "ㄑㄧˊ ㄑㄧˊ ㄍㄨㄤ")
        run("import", str(backup))
        assert run("list") == rows
        invalid = root / "invalid.json"
        invalid.write_text('{"format":"guanyinma_user_data","schema_version":1,"phrases":[{}]}')
        run("import", str(invalid), success=False)
        assert run("list") == rows
        run("add", "字數錯誤", "ㄗˋ", success=False)
        for protected in (model, rust, Path(str(rust) + "-wal")):
            run("export", str(protected), success=False)
        normal = root / "normal-data/chichi77-keykey"
        normal.mkdir(parents=True)
        for name in ("guanyinma-user.db",):
            protected = normal / name
            protected.write_bytes(rust.read_bytes())
            before = protected.read_bytes()
            run("export", str(protected), success=False)
            assert protected.read_bytes() == before
        alias = root / "alias.json"
        alias.symlink_to(rust)
        run("export", str(alias), success=False)
        alias.unlink()
        os.link(rust, alias)
        run("export", str(alias), success=False)
        model_hash = hashlib.sha256(model.read_bytes()).hexdigest()
        bad_environment = dict(environment, CHICHI77_KEYKEY_GUANYINMA_USER_DB=str(model))
        run("list", success=False, env=bad_environment)
        assert hashlib.sha256(model.read_bytes()).hexdigest() == model_hash
        assert "琦琦光" in run("list")
        assert "ㄑㄧˊ ㄑㄧˊ ㄍㄨㄤ" in json.loads(run("readings", "琦琦光"))
        assert json.loads(run("readings", "\U0001f600")) == []
        print("Guanyinma-only CLI, JSON/readings, CRUD, backup/import and rejected unsupported command passed")


if __name__ == "__main__":
    main()

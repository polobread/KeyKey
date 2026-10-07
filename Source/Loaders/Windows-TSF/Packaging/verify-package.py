"""Verify the actual ZIP bytes without installing or changing Windows settings."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
import sys
import zipfile

MODEL = Path(__file__).resolve().parents[4] / "DataSource/AISyntheticBigram/smart-mandarin-model-manifest.json"


def verify(package):
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)), "duplicate ZIP entries"
        manifests = [p for p in names if p.endswith("/PackageManifest.json")]
        assert len(manifests) == 1, "missing or ambiguous package manifest"
        prefix = manifests[0].removesuffix("PackageManifest.json")
        manifest = json.loads(archive.read(manifests[0]).decode("utf-8-sig"))
        assert manifest["SchemaVersion"] == 1
        assert re.fullmatch(r"\d+\.\d+\.\d+(?:\.\d+)?", manifest["Version"])
        architecture = manifest["Architecture"]
        assert architecture in ("x64", "x86")
        files = manifest["Files"]
        seen = set()
        database_hash = json.loads(MODEL.read_text(encoding="utf-8"))["canonical_database_sha256"]
        for entry in files:
            relative = entry["Path"].replace("\\", "/")
            parts = relative.split("/")
            assert not PurePosixPath(relative).is_absolute()
            assert all(p and p not in (".", "..") and ":" not in p for p in parts)
            assert relative.casefold() not in seen, "duplicate manifest path"
            seen.add(relative.casefold())
            data = archive.read(prefix + "Payload/" + relative)
            assert hashlib.sha256(data).hexdigest() == entry["Sha256"], relative
            if relative.endswith((".exe", ".dll")):
                assert data[:2] == b"MZ", relative
                offset = struct.unpack_from("<I", data, 0x3C)[0]
                assert data[offset:offset + 4] == b"PE\0\0", relative
                machine = struct.unpack_from("<H", data, offset + 4)[0]
                expected = 0x14C if architecture == "x86" or "_x86" in relative else 0x8664
                assert machine == expected, relative
            if relative == "Databases/KeyKey.db":
                assert entry["Sha256"] == database_hash, "non-canonical database"
        payload_prefix = prefix + "Payload/"
        actual = {p[len(payload_prefix):].casefold() for p in names
                  if p.startswith(payload_prefix) and not p.endswith("/")}
        assert actual == seen, "payload/manifest inventory mismatch"
        required = {"keykeytsf_x86.dll", "keykeysettings.exe", "keykeysettingsbackend.dll",
                    "keykeydeployment.exe", "keykeyregistration_x86.exe", "databases/keykey.db"}
        if architecture == "x64":
            required.add("keykeytsf_x64.dll")
        assert required <= seen, "incomplete payload"
        assert "licenses/openvanilla-hanconvert.txt" in seen, "missing Han conversion notices"
        guide = archive.read(prefix + "README.txt").decode("utf-8-sig")
        assert "新增鍵盤" in guide and "Windows 10" in guide and "Windows 11" in guide
        assert "chichi77-keykey-install.log" not in guide
        print(f"Verified {package.name}: {architecture}, {len(files)} files, hashes/PE/canonical DB/setup guide")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("Usage: verify-package.py ZIP [ZIP ...]")
    for argument in sys.argv[1:]:
        verify(Path(argument))

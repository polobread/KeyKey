#!/usr/bin/env python3
"""Verify the actual APK's offline component catalog and shared license bodies."""
import argparse
import hashlib
import json
import re
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("apk")
args = parser.parse_args()
with zipfile.ZipFile(args.apk) as archive:
    prefix = "assets/" if "assets/licenses/Guanyinma-Notices.json" in archive.namelist() else "base/assets/"
    catalog = json.loads(archive.read(prefix + "licenses/Guanyinma-Notices.json"))
    text = archive.read(prefix + "licenses/Guanyinma-Notices.txt").decode("utf-8")
    assert not any(name.endswith(".audit.json") for name in archive.namelist()), "Audit report leaked into APK"
assert catalog["schemaVersion"] == 1
bodies = {item["id"]: item["text"] for item in catalog["licenses"]}
components = {item["id"]: item for item in catalog["components"]}
assert len(bodies) == len(catalog["licenses"])
assert len(components) == len(catalog["components"])
for identity, body in bodies.items():
    assert identity == hashlib.sha256(" ".join(body.split()).encode()).hexdigest()
required = {"keykey", "yahoo", "formosa", "unicode", "mcbopomofo", "ai-data", "collection", "rust", "rust-compiler_builtins", "rust-libm", "sqlite", "ndk-compiler_rt", "ndk-libc++", "ndk-libc++abi", "ndk-libunwind"}
assert required <= components.keys()
assert any(k.startswith("android-com.android.billingclient:billing:") for k in components)
references = set()
for component in components.values():
    assert component["licenseIDs"] and set(component["licenseIDs"]) <= bodies.keys()
    assert component["sources"] and all(re.fullmatch("[a-f0-9]{64}", s["sha256"]) for s in component["sources"])
    references.update(component["licenseIDs"])
    if component["id"] == "rust" or component["id"].startswith("rust-"):
        content = component["attribution"] + "\n" + "\n".join(bodies[k] for k in component["licenseIDs"])
        assert "<!doctype html>" not in content.lower()
        assert "GNU GENERAL PUBLIC LICENSE" not in content
    assert not any(s["path"].endswith("Rust/licenses/GPL-3.0-or-later.txt") for s in component["sources"])
assert references == bodies.keys(), "Unreferenced notice bodies"
assert "----- BEGIN Rust" not in text
assert not any(k in components for k in ("cargo-cc", "cargo-pkg-config", "cargo-vcpkg", "cargo-serde_derive", "cargo-syn", "cargo-quote", "cargo-proc-macro2"))
print("APK notice catalog verified: %d components, %d shared text blocks, %d UTF-8 text bytes" %
      (len(components), len(bodies), len(text.encode())))

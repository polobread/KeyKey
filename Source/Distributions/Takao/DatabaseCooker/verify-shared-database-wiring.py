#!/usr/bin/env python3
"""Verify that every frontend consumes the same pre-generated KeyKey.db."""
from __future__ import annotations

import json
import re
from pathlib import Path
import sys

from smart_mandarin_model import verify_manifest


ROOT = Path(__file__).resolve().parents[4]
DATABASE = ROOT / "Source/Distributions/Takao/CookedDatabase/KeyKey.db"
MANIFEST = ROOT / "DataSource/AISyntheticBigram/smart-mandarin-model-manifest.json"

REQUIRED_REFERENCES = {
    "macOS": (
        ROOT / "Source/Takao.xcodeproj/project.pbxproj",
        ("Distributions/Takao/CookedDatabase/KeyKey.db",),
    ),
    "iOS": (
        ROOT / "Source/Loaders/iOS-Keyboard/KeyKeyiOS.xcodeproj/project.pbxproj",
        ("../../Distributions/Takao/CookedDatabase/KeyKey.db",),
    ),
    "Android": (
        ROOT / "Source/Loaders/Android-IME/app/build.gradle.kts",
        (
            "../../../Distributions/Takao/CookedDatabase/KeyKey.db",
            "dependsOn(verifySmartMandarinDatabase)",
        ),
    ),
    "Windows": (
        ROOT / "Source/Loaders/Windows-TSF/CMakeLists.txt",
        (
            "Source/Distributions/Takao/CookedDatabase/KeyKey.db",
            "must name the pre-generated shared KeyKey.db",
        ),
    ),
    "Linux": (
        ROOT / "Source/Loaders/Linux-IME/CMakeLists.txt",
        (
            "Source/Distributions/Takao/CookedDatabase/KeyKey.db",
            'RENAME "smart-mandarin.db"',
            '"${KEYKEY_SMART_MODEL_VERIFIER}"',
        ),
    ),
}


def main() -> int:
    try:
        model = verify_manifest(DATABASE, MANIFEST)
        for platform, (path, required) in REQUIRED_REFERENCES.items():
            text = path.read_text(encoding="utf-8")
            missing = [value for value in required if value not in text]
            if missing:
                raise ValueError(f"{platform}: {path} is missing {missing}")

        android_store = (ROOT / "Source/Loaders/Android-IME/app/src/main/java/"
                         "tw/chichi77/keykey/android/SmartMandarinStore.java").read_text(
                             encoding="utf-8")
        installed_name = re.search(r'INSTALLED_NAME\s*=\s*"([^"]+)"', android_store)
        expected_name = f"KeyKey-smart-{model['database_sha256'][:16]}.db"
        if installed_name is None or installed_name.group(1) != expected_name:
            raise ValueError(f"Android model cache must be named {expected_name}")

        cloud_script = (
            ROOT / "Source/Loaders/iOS-Keyboard/ci_scripts/ci_post_clone.sh"
        ).read_text(encoding="utf-8")
        if "make -C" in cloud_script or "verify-smart-mandarin-db.py" not in cloud_script:
            raise ValueError("iOS Xcode Cloud must verify the shared DB without cooking it")

        windows = (ROOT / "Source/Loaders/Windows-TSF/CMakeLists.txt").read_text(
            encoding="utf-8"
        )
        if "KeyKeyDatabaseCooker" in windows or "SmartMandarinCooker.rb" in windows:
            raise ValueError("Windows platform build still contains a database cooker path")

        makefile = (ROOT / "Source/Distributions/Takao/DatabaseCooker/Makefile").read_text(
            encoding="utf-8"
        )
        if "all: verify" not in makefile or "all: $(DB)" in makefile:
            raise ValueError("the default database Make target must verify without cooking")

        print(json.dumps({
            "status": "ok",
            "frontends": list(REQUIRED_REFERENCES),
            **model,
        }, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

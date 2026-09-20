#!/usr/bin/env python3
"""Build the GPL-2.0 GNOME Shell 46 panel as a separate Debian package."""

import argparse
import gzip
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
SOURCE = HERE / "upstream-v83"
PACKAGE = "gnome-shell-extension-keykey-kimpanel"
UUID = "kimpanel@kde.org"
FILES = {
    "extension.js": "5887f37967cc227f1c937ef67ac538603bdf5f2cc8a51a35c507cbb116f20ca6",
    "indicator.js": "dbac192c65a4569a74e719b5064cb6ecb3dab905a5d353f64c69c3f4f5e32473",
    "lib.js": "0239b285cfcd6bddcd766506ea592250f9bfca043b85c1fa9df2cdff02e3c80a",
    "menu.js": "66687c6db1302f21714868abef4456f8ac593edbdb198f2e3140749410c27479",
    "metadata.json": "45e06a80c7e0f7907a30c151156325e8f63e6ff8eb943045bad940be8b88115e",
    "panel.js": "fef4dc8852d7719aecb14c9496d2daccc81286054d172974f80005c30bd9dfba",
    "prefs.js": "91f72f3fcfefaf2e96832ca9db48f2d6be7fdd1d2eeff7e5edb9ecf16474020d",
    "stylesheet.css": "35af4ca54e8fdb36b210a4bdcbc80095fe85f1246face0769258166a22c6fab8",
    "schemas/org.gnome.shell.extensions.kimpanel.gschema.xml":
        "c9221d3020707b3a33c00a63608b0088737865f76de8f35c69abcf22495a7768",
}


def verify_source():
    actual_files = {str(path.relative_to(SOURCE)) for path in SOURCE.rglob("*")
                    if path.is_file() or path.is_symlink()}
    if actual_files != FILES.keys():
        raise RuntimeError(f"Unexpected upstream files: {actual_files ^ FILES.keys()}")
    for name, expected in FILES.items():
        path = SOURCE / name
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise RuntimeError(f"Upstream source mismatch: {name}")


def put_text(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--version", default="83+keykey1-1+ubuntu24.04")
    args = parser.parse_args()
    if not args.version or any(char not in "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.+:~-"
                               for char in args.version):
        raise RuntimeError("Invalid Debian version")
    source_epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "1789862400"))
    if source_epoch < 0:
        raise RuntimeError("SOURCE_DATE_EPOCH must be nonnegative")
    verify_source()
    output = args.output.resolve()
    if output.is_relative_to(SOURCE):
        raise RuntimeError("Output must be outside the pinned upstream source")
    output.mkdir(parents=True, exist_ok=True)
    package_path = output / f"{PACKAGE}_{args.version}_all.deb"
    with tempfile.TemporaryDirectory(prefix="keykey-kimpanel-") as temporary:
        temporary = Path(temporary)
        extension = temporary / "patched-extension"
        subprocess.run([sys.executable, str(HERE / "build-patched-extension.py"),
                        str(SOURCE), str(extension)], check=True)
        subprocess.run(["glib-compile-schemas", "--strict", str(extension / "schemas")],
                       check=True)
        stage = temporary / "stage"
        destination = stage / "usr/share/gnome-shell/extensions" / UUID
        shutil.copytree(extension, destination)
        control_command = stage / "usr/bin/keykey-gnome-panel"
        control_command.parent.mkdir(parents=True)
        shutil.copy2(HERE / "panel-control.sh", control_command)
        control = stage / "DEBIAN/control"
        put_text(control, f"""Package: {PACKAGE}
Version: {args.version}
Section: gnome
Priority: optional
Architecture: all
Maintainer: Chui-Ping Cheng <polobread@yahoo.com.tw>
Depends: gnome-shell (>= 46~), gnome-shell (<< 47~), fcitx5
Description: Input Method Panel with candidate placement fixes for GNOME Shell 46
 This separately licensed GNOME extension displays Fcitx 5 candidates through
 the Kimpanel protocol and corrects placement after a cross-monitor move.
""")
        license_dir = stage / "usr/share/doc" / PACKAGE
        license_dir.mkdir(parents=True)
        put_text(license_dir / "copyright", """Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Input Method Panel
Source: https://github.com/wengxt/gnome-shell-extension-kimpanel

Files: *
Copyright: 2026 Chui-Ping Cheng
 Input Method Panel contributors
License: GPL-2
 The complete license is available on Debian and Ubuntu systems at
 /usr/share/common-licenses/GPL-2. The corresponding source tree also
 includes it at Source/Loaders/Linux-IME/gnome-panel/COPYING.
""")
        put_text(license_dir / "source", """Input Method Panel version 83
https://extensions.gnome.org/extension/261/kimpanel/
version_tag=57768
Original archive SHA-256: b8d83c1bc6e903a280dc0492b9b4e3be4b2713ab96c669d1ae90e625eacf675f
Original source and the applied patch are in the corresponding KeyKey source tree:
Source/Loaders/Linux-IME/gnome-panel/upstream-v83
Source/Loaders/Linux-IME/gnome-panel/kimpanel-v83.patch
The package build also emits a version-matched source.tar.gz alongside the .deb.
License: GPL-2.0
""")
        changelog = f"""{PACKAGE} ({args.version}) noble; urgency=medium

  * Package Input Method Panel version 83 with cross-monitor placement fixes.

 -- Chui-Ping Cheng <polobread@yahoo.com.tw>  Sun, 20 Sep 2026 00:00:00 +0000
"""
        with (license_dir / "changelog.Debian.gz").open("wb") as output_file:
            with gzip.GzipFile(filename="", mode="wb", fileobj=output_file,
                               mtime=source_epoch) as compressed:
                compressed.write(changelog.encode())
        manual = r""".TH KEYKEY-GNOME-PANEL 1 "20 September 2026" "KeyKey" "User Commands"
.SH NAME
keykey-gnome-panel \- enable or disable the packaged GNOME input panel
.SH SYNOPSIS
.B keykey-gnome-panel
.RI { enable | disable | status }
.SH DESCRIPTION
Manage the Kimpanel GNOME Shell extension for the current user.
The package supports GNOME Shell 46. Log out and in after installation or upgrade.
If a user-local extension has the same UUID, move it aside before enabling the
system package.
"""
        manual_path = stage / "usr/share/man/man1/keykey-gnome-panel.1.gz"
        manual_path.parent.mkdir(parents=True)
        with manual_path.open("wb") as output_file:
            with gzip.GzipFile(filename="", mode="wb", fileobj=output_file,
                               mtime=source_epoch) as compressed:
                compressed.write(manual.encode())
        for path in stage.rglob("*"):
            if path.is_file():
                os.chmod(path, 0o644)
            elif path.is_dir():
                os.chmod(path, 0o755)
        os.chmod(control_command, 0o755)
        for path in (stage, *stage.rglob("*")):
            os.utime(path, (source_epoch, source_epoch))
        environment = dict(os.environ, SOURCE_DATE_EPOCH=str(source_epoch))
        subprocess.run(["dpkg-deb", "--build", "--root-owner-group", str(stage),
                        str(package_path)], check=True, env=environment)
    print(package_path)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)

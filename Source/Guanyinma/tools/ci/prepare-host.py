#!/usr/bin/env python3
"""Prepare disposable Linux CI hosts only; never run on the user's desktop."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("platform", choices=("linux", "android"))
args = parser.parse_args()
if args.platform == "linux":
    subprocess.run(["sudo", "apt-get", "update"], check=True)
    subprocess.run(["sudo", "apt-get", "install", "--yes", "--no-install-recommends",
                    "build-essential", "libsqlite3-dev", "pkg-config"], check=True)
else:
    if not Path("/dev/kvm").exists():
        raise SystemExit("Headless Android execution requires KVM on the CI runner")
    subprocess.run(["sudo", "tee", "/etc/udev/rules.d/99-guanyinma-kvm.rules"],
                   input='KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"\n',
                   text=True, check=True)
    subprocess.run(["sudo", "udevadm", "control", "--reload-rules"], check=True)
    subprocess.run(["sudo", "udevadm", "trigger", "--name-match=kvm"], check=True)

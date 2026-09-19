#!/usr/bin/env python3
"""Exercise native Wayland test hosts through QEMU keyboard injection."""

import json
import shlex
import socket
import subprocess
import sys
import time
from pathlib import Path


LINUX_ROOT = Path(__file__).resolve().parents[1]
VM_DIR = LINUX_ROOT / "out/gnome-vm"
SSH = [
    "ssh", "-i", str(VM_DIR / "id_ed25519"), "-p", "2222",
    "-o", f"UserKnownHostsFile={VM_DIR / 'known_hosts'}",
    "-o", "StrictHostKeyChecking=accept-new", "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=5", "keykey@127.0.0.1",
]
MODES = {
    "gtk3": ("keykey_linux_gtk3_e2e_host", "GDK_BACKEND=wayland", False),
    "gtk4": ("keykey_linux_gtk4_e2e_host", "GDK_BACKEND=wayland", False),
    "qt6": ("keykey_linux_qt6_e2e_host", "QT_QPA_PLATFORM=wayland", False),
    "gtk3-bridge": ("keykey_linux_gtk3_e2e_host", "GDK_BACKEND=wayland", True),
    "gtk4-bridge": ("keykey_linux_gtk4_e2e_host", "GDK_BACKEND=wayland", True),
}
HOST_DIR = "/home/keykey/.local/libexec/keykey-e2e"


def guest(command):
    result = subprocess.run(
        SSH + ["bash", "-lc", shlex.quote(command)],
        text=True, capture_output=True, check=False,
    )
    if result.returncode:
        raise RuntimeError(f"Guest command failed: {command}\n{result.stderr}")
    return result.stdout.strip()


class Qmp:
    def __enter__(self):
        self.connection = socket.socket(socket.AF_UNIX)
        self.connection.connect(str(VM_DIR / "qmp.sock"))
        self.stream = self.connection.makefile("rwb", buffering=0)
        self.stream.readline()
        self.call("qmp_capabilities")
        return self

    def __exit__(self, *_):
        self.stream.close()
        self.connection.close()

    def call(self, name, arguments=None):
        request = {"execute": name}
        if arguments is not None:
            request["arguments"] = arguments
        self.stream.write((json.dumps(request) + "\n").encode())
        response = json.loads(self.stream.readline())
        if "error" in response:
            raise RuntimeError(response)
        return response["return"]

    def keys(self, keys):
        for key in keys:
            self.call("human-monitor-command", {"command-line": f"sendkey {key}"})
            time.sleep(0.15)


def check_guest():
    result = guest("""
set -e
pgrep -u keykey -x gnome-shell >/dev/null
loginctl list-sessions --no-legend | while read -r session rest; do
    if [ "$(loginctl show-session "$session" -p Type --value)" = wayland ] &&
       [ "$(loginctl show-session "$session" -p State --value)" = active ]; then
        echo wayland-active
    fi
done
pid=$(pgrep -u keykey -x fcitx5)
grep -q /fcitx5/chichi77-keykey.so /proc/$pid/maps
grep -q /fcitx5/libwayland.so /proc/$pid/maps
grep -q /fcitx5/libibusfrontend.so /proc/$pid/maps
dpkg-query -W -f='${Version}' fcitx5-chichi77-keykey
""")
    if "wayland-active" not in result:
        raise RuntimeError("No active GNOME Wayland session")
    for host, _, _ in MODES.values():
        guest(f"test -x {HOST_DIR}/{host}")
    print("Guest: active Wayland session, installed KeyKey addon and Fcitx frontends")


def run_case(qmp, mode):
    host, backend, unset_gtk_module = MODES[mode]
    case_dir = f"/tmp/keykey-wayland-smoke-{mode}"
    unit = f"keykey-wayland-smoke-{mode}-{int(time.time())}"
    guest(f"mkdir -p {case_dir} && rm -f {case_dir}/{{positive-ready,final.txt,host-events.log,events.jsonl}}")
    command = [
        "systemd-run", "--user", f"--unit={unit}", "--collect",
        "--property=Type=exec", f"--setenv={backend}",
        *(["--setenv=GTK_IM_MODULE=fcitx"] if not unset_gtk_module and mode != "qt6" else []),
        f"--setenv=KEYKEY_E2E_CASE_DIR={case_dir}",
        "--setenv=KEYKEY_E2E_EXPECTED_COMMIT=中",
        "--setenv=KEYKEY_E2E_EXPECTED_LITERAL=5j/ 1",
        "--setenv=KEYKEY_E2E_REQUIRED_PREEDITS=ㄓ,ㄓㄨ,ㄓㄨㄥ",
        *(["/usr/bin/env", "-u", "GTK_IM_MODULE"] if unset_gtk_module else []),
        f"{HOST_DIR}/{host}",
    ]
    guest("export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
          + shlex.join(command))
    time.sleep(1.5)
    selected = guest("export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
                     "fcitx5-remote -o; fcitx5-remote -s chichi77-keykey-bopomofo; "
                     "fcitx5-remote -n")
    if selected.splitlines()[-1] != "chichi77-keykey-bopomofo":
        raise RuntimeError(f"Wrong active engine for {mode}: {selected}")
    qmp.keys(["5", "j", "slash", "spc", "1"])
    guest(f"for i in $(seq 1 30); do test -f {case_dir}/positive-ready && exit 0; "
          f"sleep 0.1; done; cat {case_dir}/host-events.log; exit 1")
    guest("export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
          "fcitx5-remote -s keyboard-us; "
          "test \"$(fcitx5-remote -n)\" = keyboard-us")
    qmp.keys(["ctrl-a", "backspace", "5", "j", "slash", "spc", "1"])
    result = guest(f"for i in $(seq 1 30); do "
                   f"test -f {case_dir}/final.txt && break; sleep 0.1; done; "
                   f"cat {case_dir}/final.txt; echo; cat {case_dir}/host-events.log")
    if "result=passed" not in result or "text=5j/ 1" not in result:
        raise RuntimeError(f"{mode} did not pass: {result}")
    print(f"{mode}: 中 with preedit, then keyboard-us literal 5j/ 1")


def main():
    check_guest()
    with Qmp() as qmp:
        for mode in MODES:
            run_case(qmp, mode)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)

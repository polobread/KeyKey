#!/usr/bin/env python3
"""Exercise installed KeyKey through GNOME Wayland and XWayland VM clients."""

import argparse
import base64
import datetime
import json
import shlex
import socket
import struct
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


LINUX_ROOT = Path(__file__).resolve().parents[1]
VM_DIR = LINUX_ROOT / "out/gnome-vm"
HOST_DIR = "/home/keykey/.local/libexec/keykey-e2e"
CONFIG = "/home/keykey/.config/fcitx5/conf/chichi77-keykey.conf"
SSH = [
    "ssh", "-i", str(VM_DIR / "id_ed25519"), "-p", "2222",
    "-o", f"UserKnownHostsFile={VM_DIR / 'known_hosts'}",
    "-o", "StrictHostKeyChecking=accept-new", "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=5", "keykey@127.0.0.1",
]


@dataclass(frozen=True)
class Mode:
    host: str
    backend: str
    gtk_module: str = ""


@dataclass(frozen=True)
class Case:
    commit: str
    literal: str
    preedits: str
    keys: tuple[str, ...]
    layout: str = "Standard"
    collections: str = ""
    style: str = "Vertical"
    simplified: bool = False
    mouse_row: int = 0
    negative_keys: tuple[str, ...] = ()


MODES = {
    "gtk3-wayland": Mode("gtk3", "GDK_BACKEND=wayland", "fcitx"),
    "gtk4-wayland": Mode("gtk4", "GDK_BACKEND=wayland", "fcitx"),
    "qt6-wayland": Mode("qt6", "QT_QPA_PLATFORM=wayland"),
    "gtk3-bridge": Mode("gtk3", "GDK_BACKEND=wayland", "unset"),
    "gtk4-bridge": Mode("gtk4", "GDK_BACKEND=wayland", "unset"),
    "gtk3-xwayland": Mode("gtk3", "GDK_BACKEND=x11", "fcitx"),
    "gtk4-xwayland": Mode("gtk4", "GDK_BACKEND=x11", "fcitx"),
    "qt6-xwayland": Mode("qt6", "QT_QPA_PLATFORM=xcb"),
}
CASES = {
    "T01-standard": Case(
        "中", "5j/ 1", "ㄓ,ㄓㄨ,ㄓㄨㄥ",
        ("5", "j", "slash", "spc", "1"),
    ),
    "T01-continuous": Case(
        "中文", "5j/ jp61", "ㄓ,ㄓㄨ,ㄓㄨㄥ,ㄨ,ㄨㄣ,ㄨㄣˊ",
        ("5", "j", "slash", "spc", "j", "p", "6", "1"),
    ),
    "T01-invalid": Case(
        "中", "5=j/ 1", "ㄓ,ㄓㄨ,ㄓㄨㄥ",
        ("5", "equal", "ctrl-c", "j", "slash", "spc", "1"),
    ),
    "T06-navigation": Case(
        "妐", "5j/ ", "ㄓ,ㄓㄨ,ㄓㄨㄥ",
        ("5", "j", "slash", "spc", "end", "home", "pgdn", "down", "ret"),
    ),
    "T06-mouse": Case(
        "鐘", "5j/ ", "ㄓ,ㄓㄨ,ㄓㄨㄥ",
        ("5", "j", "slash", "spc"), mouse_row=2,
    ),
    "T02-standard": Case(
        "麻馬罵嘛", r"a8\61a831a841a871", "ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙",
        ("a", "8", "backslash", "ctrl-c", "6", "1", "a", "8", "3", "1",
         "a", "8", "4", "1", "a", "8", "7", "1"),
    ),
    "T02-eten": Case(
        "麻馬罵嘛", r"ma\21ma31ma41ma11", "ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙",
        ("m", "a", "backslash", "ctrl-c", "2", "1", "m", "a", "3", "1",
         "m", "a", "4", "1", "m", "a", "1", "1"), "ETen",
    ),
    "T02-eten26": Case(
        "麻馬罵嘛", r"ma\f1maj1mak1mad1", "ㄢ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙",
        ("m", "a", "backslash", "ctrl-c", "f", "1", "m", "a", "j", "1",
         "m", "a", "k", "1", "m", "a", "d", "1"), "ETen26",
    ),
    "T02-hsu": Case(
        "麻馬罵嘛", r"my\d1myf1myj1mys1", "ㄢ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙",
        ("m", "y", "backslash", "ctrl-c", "d", "1", "m", "y", "f", "1",
         "m", "y", "j", "1", "m", "y", "s", "1"), "Hsu",
    ),
    "T02-hanyu-pinyin": Case(
        "麻馬罵嘛", r"ma\21ma31ma41ma51", "z,zh,m,ma,ma2,ma3,ma4,ma5",
        ("z", "h", "backspace", "backspace", "m", "a", "backslash",
         "ctrl-c", "2", "1", "m", "a", "3", "1", "m", "a", "4", "1",
         "m", "a", "5", "1"), "HanyuPinyin",
    ),
    "T03-edit-cancel": Case(
        "中文麻", "5j// 1jpjp61a86a861",
        "ㄓ,ㄓㄨ,ㄓㄨㄥ,ㄓㄨ,ㄓㄨㄥ,ㄨ,ㄨㄣ,ㄨ,ㄨㄣ,ㄨㄣˊ,"
        "ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇ,ㄇㄚ,ㄇㄚˊ",
        ("equal", "backspace", "esc", "5", "j", "slash", "spc",
         "backspace", "slash", "spc", "1", "j", "p", "esc", "j", "p",
         "6", "1", "a", "8", "6", "esc", "a", "8", "6", "1"),
    ),
    "T07-associated": Case(
        "今天", "rup 1!", "ㄐ,ㄐㄧ,ㄐㄧㄣ",
        ("r", "u", "p", "spc", "1", "shift-1"),
        collections="McBopomofo",
    ),
    "T07-history": Case(
        "臺灣史", "w962!", "ㄊ,ㄊㄞ,ㄊㄞˊ",
        ("w", "9", "6", "2", "shift-1"),
        collections="history",
    ),
    "T07-disabled": Case(
        "臺!", "w962!", "ㄊ,ㄊㄞ,ㄊㄞˊ",
        ("w", "9", "6", "2", "shift-1"),
    ),
    "T06-horizontal": Case(
        "妐", " 5j/ ", "ㄓ,ㄓㄨ,ㄓㄨㄥ",
        ("5", "j", "slash", "spc", "end", "home", "pgdn", "pgup",
         "right", "left", "spc", "down", "ret"),
        style="Horizontal",
    ),
    "T08-full-width": Case(
        "Ａ！～　", " A!~ ", "",
        ("shift-spc", "shift-a", "shift-1", "shift-grave_accent", "spc"),
    ),
    "T08-simplified": Case(
        "台湾", "w962j0 1", "ㄊ,ㄊㄞ,ㄊㄞˊ,ㄨ,ㄨㄢ",
        ("w", "9", "6", "2", "j", "0", "spc", "1"),
        simplified=True,
    ),
    "T08-control-backslash": Case(
        "a中", "a5j/ 1", "ㄓ,ㄓㄨ,ㄓㄨㄥ",
        ("ctrl-backslash", "a", "ctrl-backslash", "5", "j", "slash",
         "spc", "1"),
    ),
    "T09-shortcut-passthrough": Case(
        "中", "5j/ 1", "ㄓ,ㄓㄨ,ㄓㄨㄥ",
        ("5", "ctrl-c", "j", "slash", "spc", "1"),
    ),
    "T12-symbol-list": Case(
        "，", "1", "，", ("ctrl-0", "1"),
    ),
    "T12-symbol-mouse": Case(
        "，", "!", "，", ("ctrl-0",), mouse_row=1,
        negative_keys=("ctrl-0", "shift-1"),
    ),
}


def guest(command):
    result = subprocess.run(
        SSH + ["bash", "-lc", shlex.quote(command)],
        text=True, capture_output=True, check=False,
    )
    if result.returncode:
        raise RuntimeError(f"Guest command failed: {command}\n{result.stderr}\n{result.stdout}")
    return result.stdout.strip()


def session_command(command):
    return guest("export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
                 + command)


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
        while True:
            line = self.stream.readline()
            if not line:
                raise RuntimeError("QMP disconnected while waiting for a response")
            response = json.loads(line)
            if "event" in response:
                continue
            if "error" in response:
                raise RuntimeError(response)
            return response["return"]

    def keys(self, keys):
        for key in keys:
            result = self.call("human-monitor-command",
                               {"command-line": f"sendkey {key}"})
            if result:
                raise RuntimeError(f"QEMU rejected key {key}: {result.strip()}")
            time.sleep(0.15)

    def screenshot(self, path):
        self.call("human-monitor-command",
                  {"command-line": f"screendump {path}"})

    def move_pointer(self, x, y, width, height):
        self.call("input-send-event", {"events": [
            {"type": "abs", "data": {"axis": "x", "value": x * 32767 // (width - 1)}},
            {"type": "abs", "data": {"axis": "y", "value": y * 32767 // (height - 1)}},
        ]})


def receive_exact(connection, length):
    result = bytearray()
    while len(result) < length:
        chunk = connection.recv(length - len(result))
        if not chunk:
            raise RuntimeError("VNC connection closed")
        result.extend(chunk)
    return bytes(result)


class VncPointer:
    def __enter__(self):
        self.connection = socket.create_connection(("127.0.0.1", 5902), 5)
        version = receive_exact(self.connection, 12)
        if version != b"RFB 003.008\n":
            raise RuntimeError(f"Unexpected VNC protocol: {version!r}")
        self.connection.sendall(version)
        count = receive_exact(self.connection, 1)[0]
        choices = receive_exact(self.connection, count)
        if 1 not in choices:
            raise RuntimeError("VM VNC server does not offer no-auth localhost access")
        self.connection.sendall(b"\x01")
        if receive_exact(self.connection, 4) != b"\x00\x00\x00\x00":
            raise RuntimeError("VM VNC authentication failed")
        self.connection.sendall(b"\x01")
        header = receive_exact(self.connection, 24)
        self.width, self.height = struct.unpack(">HH", header[:4])
        receive_exact(self.connection, struct.unpack(">I", header[20:24])[0])
        return self

    def __exit__(self, *_):
        self.connection.close()

    def click(self, x, y):
        if not (0 <= x < self.width and 0 <= y < self.height):
            raise RuntimeError(f"Candidate click outside VNC screen: {x},{y}")
        self.connection.sendall(struct.pack(">BBHH", 5, 0, x, y))
        time.sleep(0.15)
        self.connection.sendall(struct.pack(">BBHH", 5, 1, x, y))
        time.sleep(0.1)
        self.connection.sendall(struct.pack(">BBHH", 5, 0, x, y))

    def drag(self, qmp, start, end):
        for x, y in (start, end):
            if not (0 <= x < self.width and 0 <= y < self.height):
                raise RuntimeError(f"Selection drag outside VNC screen: {x},{y}")
        qmp.move_pointer(*start, self.width, self.height)
        time.sleep(0.15)
        self.connection.sendall(struct.pack(">BBHH", 5, 1, *start))
        time.sleep(0.15)
        for step in range(1, 7):
            x = start[0] + (end[0] - start[0]) * step // 6
            y = start[1] + (end[1] - start[1]) * step // 6
            qmp.move_pointer(x, y, self.width, self.height)
            self.connection.sendall(struct.pack(">BBHH", 5, 1, x, y))
            time.sleep(0.08)
        self.connection.sendall(struct.pack(">BBHH", 5, 0, *end))
        time.sleep(0.15)


def read_ppm(path):
    with path.open("rb") as image:
        if image.readline() != b"P6\n":
            raise RuntimeError(f"Unexpected screenshot format: {path}")
        width, height = map(int, image.readline().split())
        if image.readline() != b"255\n":
            raise RuntimeError(f"Unexpected screenshot color depth: {path}")
        pixels = image.read()
    if len(pixels) != width * height * 3:
        raise RuntimeError(f"Incomplete screenshot: {path}")
    return width, height, pixels


def find_candidate_popup(before, after):
    width, height, old_pixels = read_ppm(before)
    new_width, new_height, pixels = read_ppm(after)
    if (width, height) != (new_width, new_height):
        raise RuntimeError("VM display resolution changed during candidate capture")
    rows = []
    for y in range(30, height - 30):
        changed = []
        for x in range(50, width - 50):
            offset = (y * width + x) * 3
            delta = sum(abs(old_pixels[offset + channel] - pixels[offset + channel])
                        for channel in range(3))
            if delta > 60:
                changed.append(x)
        if len(changed) >= 2:
            rows.append((y, min(changed), max(changed)))
    groups = []
    for row in rows:
        if not groups or row[0] > groups[-1][-1][0] + 1:
            groups.append([row])
        else:
            groups[-1].append(row)
    tall = [group for group in groups if len(group) >= 120]
    if not tall:
        raise RuntimeError(f"No tall candidate popup found in {after}")
    group = max(tall, key=len)
    column_counts = {}
    for y in range(group[0][0], group[-1][0] + 1):
        for x in range(min(row[1] for row in group),
                       max(row[2] for row in group) + 1):
            offset = (y * width + x) * 3
            delta = sum(abs(old_pixels[offset + channel] - pixels[offset + channel])
                        for channel in range(3))
            if delta > 60:
                column_counts[x] = column_counts.get(x, 0) + 1
    persistent = [x for x, count in column_counts.items()
                  if count >= len(group) * 0.45]
    if not persistent or max(persistent) - min(persistent) < 15:
        raise RuntimeError(f"Candidate popup width not established in {after}")
    return (min(persistent), group[0][0], max(persistent) + 1,
            group[-1][0] + 1), (width, height)


def candidate_list_top(screenshot, bounds):
    width, _, pixels = read_ppm(screenshot)
    left, top, right, bottom = bounds
    blue_rows = []
    for y in range(top, min(top + 50, bottom)):
        blue_pixels = 0
        for x in range(left, right):
            offset = (y * width + x) * 3
            red, green, blue = pixels[offset:offset + 3]
            if blue > red + 40 and blue > green + 15 and blue > 100:
                blue_pixels += 1
        if blue_pixels >= 5:
            blue_rows.append(y)
    if len(blue_rows) >= 10 and blue_rows[0] <= top + 5:
        return blue_rows[-1] + 2
    return top


def changed_pixels(before, after, bounds):
    width, height, old_pixels = read_ppm(before)
    new_width, new_height, pixels = read_ppm(after)
    if (width, height) != (new_width, new_height):
        raise RuntimeError("VM display resolution changed during popup clearance check")
    left, top, right, bottom = bounds
    changed = 0
    for y in range(top, bottom):
        for x in range(left, right):
            offset = (y * width + x) * 3
            delta = sum(abs(old_pixels[offset + channel] - pixels[offset + channel])
                        for channel in range(3))
            if delta > 60:
                changed += 1
    return changed


def check_guest():
    result = guest("""
set -e
pgrep -u keykey -x gnome-shell >/dev/null
pgrep -u keykey -x Xwayland >/dev/null
loginctl list-sessions --no-legend | while read -r session rest; do
    if [ "$(loginctl show-session "$session" -p Type --value)" = wayland ] &&
       [ "$(loginctl show-session "$session" -p State --value)" = active ]; then
        echo wayland-active
    fi
done
pid=$(pgrep -u keykey -x fcitx5 | tail -n 1)
grep -q /fcitx5/chichi77-keykey.so /proc/$pid/maps
grep -q /fcitx5/libwayland.so /proc/$pid/maps
grep -q /fcitx5/libibusfrontend.so /proc/$pid/maps
dpkg-query -W -f='${Version}' fcitx5-chichi77-keykey
""")
    if "wayland-active" not in result:
        raise RuntimeError("No active GNOME Wayland session")
    for host in ("gtk3", "gtk4", "qt6"):
        guest(f"test -x {HOST_DIR}/keykey_linux_{host}_e2e_host")
    return guest("""
printf 'os='; . /etc/os-release; printf '%s\\n' "$PRETTY_NAME"
gnome-shell --version
printf 'package='; dpkg-query -W -f='${Version}\\n' fcitx5-chichi77-keykey
sha256sum /usr/lib/x86_64-linux-gnu/fcitx5/chichi77-keykey.so
sha256sum /home/keykey/.local/libexec/keykey-e2e/keykey_linux_*_e2e_host
""")


def reload_config():
    session_command("gdbus call --session --dest org.fcitx.Fcitx5 "
                    "--object-path /controller "
                    "--method org.fcitx.Fcitx.Controller1.ReloadAddonConfig "
                    "chichi77-keykey >/dev/null")


def prepare_desktop():
    idle_delay = session_command("gsettings get org.gnome.desktop.session idle-delay")
    lock_enabled = session_command(
        "gsettings get org.gnome.desktop.screensaver lock-enabled")
    try:
        session_command("gsettings set org.gnome.desktop.session idle-delay 0; "
                        "gsettings set org.gnome.desktop.screensaver lock-enabled false")
        guest("loginctl list-sessions --no-legend | while read -r session rest; do "
              "if [ \"$(loginctl show-session \"$session\" -p Type --value)\" = wayland ]; "
              "then loginctl unlock-session \"$session\"; fi; done")
        if session_command("gdbus call --session --dest org.gnome.ScreenSaver "
                           "--object-path /org/gnome/ScreenSaver "
                           "--method org.gnome.ScreenSaver.GetActive") != "(false,)":
            raise RuntimeError("GNOME session is still locked")
    except Exception:
        restore_desktop((idle_delay, lock_enabled))
        raise
    return idle_delay, lock_enabled


def restore_desktop(settings):
    idle_delay, lock_enabled = settings
    session_command("gsettings set org.gnome.desktop.session idle-delay "
                    f"{shlex.quote(idle_delay)}; "
                    "gsettings set org.gnome.desktop.screensaver lock-enabled "
                    f"{shlex.quote(lock_enabled)}")


def apply_config(case):
    contents = f"BopomofoLayout={case.layout}\n" \
               f"CandidateWindowStyle={case.style}\n" \
               f"AssociatedPhraseCollections={case.collections}\n" \
               f"TraditionalToSimplified={str(case.simplified)}\n"
    encoded = base64.b64encode(contents.encode()).decode()
    guest(f"mkdir -p {shlex.quote(str(Path(CONFIG).parent))}; "
          f"printf %s {encoded} | base64 -d > {CONFIG}")
    reload_config()


def read_config():
    return guest(f"if test -f {CONFIG}; then base64 -w0 {CONFIG}; "
                 "else echo MISSING; fi")


def restore_config(prior):
    if prior == "MISSING":
        guest(f"rm -f -- {CONFIG}")
    else:
        guest(f"printf %s {prior} | base64 -d > {CONFIG}")
    reload_config()


def restore_engine(name, state):
    if name:
        session_command(f"fcitx5-remote -s {shlex.quote(name)} >/dev/null")
    if state == "1":
        session_command("fcitx5-remote -c >/dev/null")


def wait_file(case_dir, filename):
    guest(f"for i in $(seq 1 100); do test -f {case_dir}/{filename} && exit 0; "
          f"sleep 0.1; done; "
          f"if test -f {case_dir}/host-events.log; then "
          f"cat {case_dir}/host-events.log; fi; exit 1")


def run_case(qmp, case_name, mode_name):
    case = CASES[case_name]
    mode = MODES[mode_name]
    case_dir = f"/tmp/keykey-gnome-e2e/{case_name}/{mode_name}"
    unit = f"keykey-{case_name}-{mode_name}-{int(time.time())}"
    guest(f"mkdir -p {case_dir} && "
          f"rm -f {case_dir}/{{positive-ready,final.txt,host-events.log,events.jsonl}}")
    command = [
        "systemd-run", "--user", f"--unit={unit}", "--collect",
        "--property=Type=exec", f"--setenv={mode.backend}",
        *(["--setenv=GTK_IM_MODULE=fcitx"] if mode.gtk_module == "fcitx" else []),
        f"--setenv=KEYKEY_E2E_CASE_DIR={case_dir}",
        f"--setenv=KEYKEY_E2E_EXPECTED_COMMIT={case.commit}",
        f"--setenv=KEYKEY_E2E_EXPECTED_LITERAL={case.literal}",
        f"--setenv=KEYKEY_E2E_REQUIRED_PREEDITS={case.preedits}",
        *(["/usr/bin/env", "-u", "GTK_IM_MODULE"] if mode.gtk_module == "unset" else []),
        f"{HOST_DIR}/keykey_linux_{mode.host}_e2e_host",
    ]
    try:
        session_command(shlex.join(command))
        time.sleep(1.5)
        selected = session_command("fcitx5-remote -o; "
                                   "fcitx5-remote -s chichi77-keykey-bopomofo; "
                                   "fcitx5-remote -n")
        if not selected or selected.splitlines()[-1] != "chichi77-keykey-bopomofo":
            raise RuntimeError(f"Wrong active engine for {case_name}/{mode_name}: {selected}")
        width_probe = None
        popup = None
        if case_name == "T08-full-width":
            qmp.keys(case.keys[:2])
            events = [json.loads(line) for line in
                      guest(f"cat {case_dir}/events.jsonl").splitlines()]
            if any(event["type"] == "text" and event["value"] == "Ａ"
                   for event in events):
                width_probe = "full-after-first-toggle"
            elif any(event["type"] == "preedit" and event["value"] == "ㄇ"
                     for event in events):
                width_probe = "half-after-first-toggle"
                qmp.keys(("esc", "shift-spc", "shift-a"))
            else:
                raise RuntimeError(f"No full-width probe event: {events}")
            qmp.keys(case.keys[2:])
        elif case_name == "T08-control-backslash":
            qmp.keys(("shift-spc", "shift-a"))
            events = [json.loads(line) for line in
                      guest(f"cat {case_dir}/events.jsonl").splitlines()]
            if any(event["type"] == "preedit" and event["value"] == "ㄇ"
                   for event in events):
                width_probe = "half-after-first-toggle"
                qmp.keys(("esc",))
            elif any(event["type"] == "text" and event["value"] == "Ａ"
                     for event in events):
                width_probe = "full-after-first-toggle"
                qmp.keys(("ctrl-a", "backspace", "shift-spc"))
            else:
                raise RuntimeError(f"No half-width probe event: {events}")
            qmp.keys(case.keys)
        elif case.mouse_row:
            stem = f"{case_name}-{mode_name}"
            before = VM_DIR / f"{stem}-before.ppm"
            after = VM_DIR / f"{stem}-candidate.ppm"
            qmp.screenshot(before)
            qmp.keys(case.keys)
            time.sleep(0.5)
            qmp.screenshot(after)
            bounds, resolution = find_candidate_popup(before, after)
            left, top, right, bottom = bounds
            list_top = candidate_list_top(after, bounds)
            x = (left + right) // 2
            y = list_top + (2 * case.mouse_row - 1) * (bottom - list_top) // 18
            with VncPointer() as pointer:
                if (pointer.width, pointer.height) != resolution:
                    raise RuntimeError("VNC and QMP display resolutions differ")
                qmp.move_pointer(x, y, *resolution)
                time.sleep(0.15)
                pointer.click(x, y)
            wait_file(case_dir, "positive-ready")
            time.sleep(0.5)
            cleared = VM_DIR / f"{stem}-cleared.ppm"
            qmp.screenshot(cleared)
            candidate_pixels = changed_pixels(before, after, bounds)
            remaining_pixels = changed_pixels(before, cleared, bounds)
            cleared_pixels = changed_pixels(after, cleared, bounds)
            if candidate_pixels < 100 or cleared_pixels < candidate_pixels * 0.6:
                raise RuntimeError(
                    f"Candidate popup did not clear after selection: "
                    f"{cleared_pixels}/{candidate_pixels} changed pixels")
            popup = {"bounds": bounds, "list_top": list_top, "click": [x, y],
                     "candidate_screenshot": str(after),
                     "cleared_screenshot": str(cleared),
                     "candidate_pixels": candidate_pixels,
                     "remaining_pixels": remaining_pixels,
                     "cleared_pixels": cleared_pixels}
        else:
            qmp.keys(case.keys)
        wait_file(case_dir, "positive-ready")
        selected = session_command("fcitx5-remote -s keyboard-us; fcitx5-remote -n")
        if not selected or selected.splitlines()[-1] != "keyboard-us":
            raise RuntimeError(f"Negative control did not select keyboard-us: {selected}")
        qmp.keys(("ctrl-a", "backspace") +
                 (case.negative_keys or case.keys))
        wait_file(case_dir, "final.txt")
        result = guest(f"test \"$(cat {case_dir}/final.txt)\" = {shlex.quote(case.literal)}; "
                       f"grep -Fxq result=passed {case_dir}/host-events.log; "
                       f"cat {case_dir}/host-events.log")
        print(f"{case_name}/{mode_name}: {case.commit} + literal negative control", flush=True)
        return {"case": case_name, "mode": mode_name, "status": "passed",
                "guest_artifact": case_dir, "host_events": result.splitlines(),
                "width_probe": width_probe, "popup": popup}

    finally:
        session_command(f"systemctl --user stop {shlex.quote(unit)}.service || true")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=CASES, action="append")
    parser.add_argument("--mode", choices=MODES, action="append")
    args = parser.parse_args()
    cases = args.case or list(CASES)
    modes = args.mode or list(MODES)
    evidence = {"environment": check_guest(), "results": []}
    print("Guest: GNOME Wayland, XWayland and installed KeyKey addon ready", flush=True)
    original_engine = session_command("fcitx5-remote -n")
    original_state = session_command("fcitx5-remote; true")
    prior = read_config()
    desktop_settings = prepare_desktop()
    try:
        apply_config(CASES["T01-standard"])
        with Qmp() as qmp:
            current_config = ("Standard", "", "Vertical", False)
            for case_name in cases:
                case = CASES[case_name]
                wanted_config = (case.layout, case.collections, case.style,
                                 case.simplified)
                if wanted_config != current_config:
                    apply_config(case)
                    current_config = wanted_config
                for mode_name in modes:
                    evidence["results"].append(run_case(qmp, case_name, mode_name))
    except Exception as error:
        evidence["failure"] = str(error)
        raise
    finally:
        restore_errors = []
        for name, action in (
            ("config", lambda: restore_config(prior)),
            ("engine", lambda: restore_engine(original_engine, original_state)),
            ("desktop", lambda: restore_desktop(desktop_settings)),
        ):
            try:
                action()
            except Exception as error:
                restore_errors.append(f"{name}: {error}")
        if restore_errors:
            evidence["restore_errors"] = restore_errors
        evidence_path = VM_DIR / "gnome-typing-last.json"
        evidence_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
        timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        archive_path = VM_DIR / f"gnome-typing-{timestamp}.json"
        archive_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
        if restore_errors:
            raise RuntimeError("Failed to restore guest state: " + "; ".join(restore_errors))
    print(f"Passed {len(evidence['results'])} cases; {evidence_path}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)

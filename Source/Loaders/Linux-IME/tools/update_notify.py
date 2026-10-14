"""Notification-only release checks shared by Linux and FreeBSD desktops."""

import json
import math
import os
from pathlib import Path
import re
import tempfile
import time
from urllib.parse import urlsplit
from urllib.request import build_opener, HTTPRedirectHandler, Request

API = "https://api.github.com/repos/polobread/KeyKey/releases?per_page=100"
RELEASES = "https://github.com/polobread/KeyKey/releases"
INTERVAL = 24 * 60 * 60
LIMIT = 4 * 1024 * 1024
VERSION = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-beta([1-9][0-9]*))?"


def version_key(value):
    match = re.fullmatch(VERSION, value)
    if not match:
        raise ValueError("Invalid release version")
    major, minor, patch, beta = match.groups()
    return (int(major), int(minor), int(patch), beta is None, int(beta or 0))


class SameHostRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        old, new = urlsplit(req.full_url), urlsplit(newurl)
        if new.scheme != "https" or new.netloc != old.netloc:
            raise ValueError("Unexpected update server redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url):
    request = Request(url, headers={"User-Agent": "KeyKey-update-notification",
                                    "Accept": "application/vnd.github+json"})
    with build_opener(SameHostRedirect()).open(request, timeout=10) as response:
        data = response.read(LIMIT + 1)
    if len(data) > LIMIT:
        raise ValueError("Update response is too large")
    return data


def latest_release(current, system, machine, include_beta=False, get=fetch):
    """Verify the Unix product version at the tag; mobile-only tags do not count.

    FreeBSD checks upstream source availability, independently of .deb assets.
    Linux also requires downloadable data/frontend packages for its architecture.
    Links are derived from strict tags, never from response-provided URLs.
    """
    current_key = version_key(current)
    releases = json.loads(get(API))
    if not isinstance(releases, list):
        raise ValueError("Invalid release list")
    candidates = []
    for release in releases:
        if not isinstance(release, dict) or release.get("draft") is not False:
            continue
        tag = release.get("tag_name", "")
        if not isinstance(tag, str) or not tag.startswith("v"):
            continue
        try:
            key = version_key(tag[1:])
        except ValueError:
            continue
        beta = not key[3]
        if release.get("prerelease") is not beta or (beta and not include_beta):
            continue
        if key <= current_key:
            continue
        candidates.append((key, tag, release))
    for key, tag, release in sorted(candidates, key=lambda item: item[0], reverse=True):
        base = ".".join(str(part) for part in key[:3])
        if system == "Linux":
            arch = {"x86_64": "amd64", "amd64": "amd64",
                    "aarch64": "arm64", "arm64": "arm64"}.get(machine)
            names = {asset.get("name") for asset in release.get("assets", [])
                     if isinstance(asset, dict) and asset.get("state") == "uploaded"
                     and isinstance(asset.get("size"), int) and asset["size"] > 0}
            data = f"chichi77-keykey-data_{base}-1+ubuntu24.04_all.deb"
            frontend = f"fcitx5-chichi77-keykey_{base}-1+ubuntu24.04_{arch}.deb"
            if arch is None or not {data, frontend}.issubset(names):
                continue
        elif system != "FreeBSD":
            raise ValueError("Unsupported notification platform")
        source = get(f"https://raw.githubusercontent.com/polobread/KeyKey/{tag}/"
                     "Source/Loaders/Linux-IME/CMakeLists.txt").decode("utf-8")
        match = re.search(r"^project\(KeyKeyLinux VERSION ([0-9]+\.[0-9]+\.[0-9]+) ",
                          source, re.MULTILINE)
        if match and match[1] == base:
            return {"version": tag[1:], "url": f"{RELEASES}/tag/{tag}"}
    return None


def config_home():
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


def state_home():
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")


def load_json(path):
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
        return result if isinstance(result, dict) else {}
    except (OSError, ValueError):
        return {}


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Atomic replacement prevents a terminated desktop session losing consent.
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                     delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(value, stream, ensure_ascii=False)
        stream.write("\n")
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def due(state, now=None):
    now = time.time() if now is None else now
    previous = state.get("last_attempt", 0)
    if (not isinstance(previous, (int, float)) or not math.isfinite(previous)
            or previous < 0 or previous > now):
        return True
    return now - previous >= INTERVAL


def set_preferences(enabled, include_beta, executable):
    path = config_home() / "chichi77-keykey/update-notification.json"
    autostart = config_home() / "autostart/org.chichi77.KeyKey.UpdateNotification.desktop"
    # XDG autostart works on both Linux and FreeBSD, without a system service.
    # Quote the installed path using the Desktop Entry Exec grammar.
    escaped = str(executable).replace("\\", "\\\\").replace('"', '\\"')
    escaped = escaped.replace("`", "\\`").replace("$", "\\$").replace("%", "%%")
    if enabled:
        autostart.parent.mkdir(parents=True, exist_ok=True)
        autostart.write_text("[Desktop Entry]\nType=Application\n"
                             "Name=琦琦輸入法更新通知\n"
                             f'Exec="{escaped}" --background\n'
                             "Terminal=false\n", encoding="utf-8")
    else:
        autostart.unlink(missing_ok=True)
    save_json(path, {"enabled": bool(enabled), "include_beta": bool(include_beta)})


def preferences():
    value = load_json(config_home() / "chichi77-keykey/update-notification.json")
    # Invalid/corrupt values never imply consent to network activity.
    return {"enabled": value.get("enabled") is True,
            "include_beta": value.get("include_beta") is True}

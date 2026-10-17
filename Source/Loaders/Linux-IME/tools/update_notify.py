"""Notification-only release checks shared by Linux and FreeBSD desktops."""

import json
import math
import os
from pathlib import Path
import re
import tempfile
import time
import xml.etree.ElementTree as ET
from urllib.parse import urlsplit
from urllib.request import build_opener, HTTPRedirectHandler, Request

FEEDS = {channel: f"https://download.aws.polobread.com/keykey/update/{channel}/unix-fcitx5.xml"
         for channel in ("stable", "beta")}
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
UNIX = "urn:chichi77:keykey:update:1"
RELEASES = "https://github.com/polobread/KeyKey/releases"
INTERVAL = 7 * 24 * 60 * 60
CHECK_TIMEOUT = 10
LIMIT = 1024 * 1024
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


def fetch(url, timeout=CHECK_TIMEOUT):
    deadline = time.monotonic() + timeout
    request = Request(url, headers={"User-Agent": "KeyKey-update-notification",
                                    "Accept": "application/rss+xml, application/xml;q=0.9"})
    with build_opener(SameHostRedirect()).open(request, timeout=timeout) as response:
        data = bytearray()
        # read1 returns after a single network read. A peer sending a trickle
        # must not keep response.read(LIMIT) alive indefinitely.
        while len(data) <= LIMIT:
            if time.monotonic() >= deadline:
                raise TimeoutError("Update response timed out")
            chunk = response.read1(min(64 * 1024, LIMIT + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
    if len(data) > LIMIT:
        raise ValueError("Update response is too large")
    return bytes(data)


def parse_feed(data, channel):
    """Validate the same notification-only XML on clients and before CDN sync."""
    if channel not in FEEDS or not 0 < len(data) <= LIMIT:
        raise ValueError("Invalid Unix feed channel or size")
    text = data.decode("utf-8-sig")
    if "\x00" in text or re.search(r"<!\s*(DOCTYPE|ENTITY)\b", text, re.IGNORECASE):
        raise ValueError("DTD/entities are not allowed in Unix feeds")
    root = ET.fromstring(data)
    if root.tag != "rss" or root.get("version") != "2.0" or len(root.findall("channel")) != 1:
        raise ValueError("Expected Unix RSS 2.0 with one channel")
    document = root.find("channel")
    if not document.findtext("title") or len(document.findall(f"{{{UNIX}}}schemaVersion")) != 1 \
            or document.findtext(f"{{{UNIX}}}schemaVersion") != "1":
        raise ValueError("Unsupported Unix notification feed schema")
    entries, seen = [], set()
    for item in document.findall("item"):
        def single(name):
            elements = item.findall(name)
            if len(elements) != 1 or not elements[0].text:
                raise ValueError("Unix feed item requires one version/link field")
            return elements[0].text
        version = single(f"{{{SPARKLE}}}shortVersionString")
        key = version_key(version)
        native = ".".join(str(part) for part in key[:3]) + ("" if key[3] else f"b{key[4]}")
        if single(f"{{{SPARKLE}}}version") != native or ("stable" if key[3] else "beta") != channel:
            raise ValueError("Unix feed version/channel mismatch")
        url = f"{RELEASES}/tag/v{version}"
        if single("link") != url or item.find("enclosure") is not None:
            raise ValueError("Unix feed must link to its official release without an installer enclosure")
        architectures = [element.text for element in item.findall(f"{{{UNIX}}}linuxArchitecture")]
        if not architectures or len(set(architectures)) != len(architectures) or any(
                arch not in ("amd64", "arm64") for arch in architectures):
            raise ValueError("Unix feed requires verified Linux package architectures")
        if version in seen:
            raise ValueError("Duplicate Unix feed version")
        seen.add(version)
        entries.append({"version": version, "url": url, "linux_architectures": architectures})
    return entries


def latest_release(current, system, machine, include_beta=False, get=fetch,
                   timeout=CHECK_TIMEOUT, cancelled=None):
    """Read reviewed CDN notifications; FreeBSD availability is an upstream notice.

    Publishing validates the Unix product version and Linux packages before the
    feed PR. Clients never query GitHub APIs, tag sources or package repositories.
    """
    current_key = version_key(current)
    if system not in ("Linux", "FreeBSD"):
        raise ValueError("Unsupported notification platform")
    deadline = time.monotonic() + timeout

    def download(url):
        remaining = deadline - time.monotonic()
        if remaining <= 0 or (cancelled is not None and cancelled.is_set()):
            raise TimeoutError("Update check timed out")
        data = fetch(url, timeout=remaining) if get is fetch else get(url)
        if time.monotonic() >= deadline or (cancelled is not None and cancelled.is_set()):
            raise TimeoutError("Update check timed out")
        return data

    entries = []
    for channel in (("stable", "beta") if include_beta else ("stable",)):
        entries.extend(parse_feed(download(FEEDS[channel]), channel))
    arch = {"x86_64": "amd64", "amd64": "amd64",
            "aarch64": "arm64", "arm64": "arm64"}.get(machine)
    for entry in sorted(entries, key=lambda entry: version_key(entry["version"]), reverse=True):
        if version_key(entry["version"]) > current_key and (
                system == "FreeBSD" or arch in entry["linux_architectures"]):
            return {"version": entry["version"], "url": entry["url"]}
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
    previous = state.get("last_attempt")
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
    path = config_home() / "chichi77-keykey/update-notification.json"
    if not path.exists():
        return {"enabled": True, "include_beta": False}
    value = load_json(path)
    # Preserve saved opt-outs; malformed existing settings stay offline.
    return {"enabled": value.get("enabled") is True,
            "include_beta": value.get("include_beta") is True}

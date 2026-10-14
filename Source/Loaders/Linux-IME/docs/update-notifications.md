# Linux and FreeBSD update notifications

Open **更新通知與下載…** in the KeyKey Fcitx configuration, or launch
`keykey-update-notify` from the applications menu/terminal. Opening this window
does not check the network. **檢查新版** explicitly checks official GitHub
release metadata and the Unix product version at the release tag. The download
button opens the official release page in the default browser.

**每日檢查新版並通知** is off by default. Enabling it creates a per-user XDG
autostart entry and keeps one Gio application running during the desktop session.
It attempts a check at most once every 24 hours, including after failed checks;
restarting the desktop does not reset the interval. Each newer version is notified
once. There is no systemd or privileged service, so FreeBSD XDG desktops can use
the same tool. Closing the window retains explicitly enabled checks; disabling
the option removes its autostart entry, stops the timer and suppresses notification
from an already running request. An existing request can finish within its timeout.
The notification daemon must support freedesktop/Gio desktop notifications.

Stable releases are the default. **也通知 beta 測試版** explicitly includes beta
releases. Comparison is numeric, with `beta10 > beta9` and stable following beta
for the same base version. For beta builds pass
`-DKEYKEY_UPDATE_VERSION=1.3.2-betaN`; CMake rejects a different base product version.
The Debian build script derives this from an exact matching checkout tag, or
accepts an explicit `KEYKEY_UPDATE_VERSION` for source archives. This metadata
does not change existing Debian artifact naming/version conventions.

Mobile and Unix product versions are independent: a newer mobile-only tag whose
`Source/Loaders/Linux-IME/CMakeLists.txt` still has an older Unix version is not
reported. Linux additionally requires the published Ubuntu 24.04 data and frontend
packages for the current amd64/arm64 architecture. The FreeBSD notification is an
**upstream source release** notice and does not require `.deb` assets. It clearly
asks the user to update through ports/pkg; the port and binary repository may lag
the upstream release. It does not claim a package is already available in pkg.

This tool does not download or run packages, modify the installed input method,
query privileged package managers, or create an APT/pkg repository. Release URLs
are constructed from strict version tags, never taken from untrusted metadata.
Network access uses HTTPS, a bounded response size and a ten-second socket timeout;
cross-host and non-HTTPS redirects are rejected. No typing text is sent.

Preferences: `$XDG_CONFIG_HOME/chichi77-keykey/update-notification.json`.
Attempt time and last notified version:
`$XDG_STATE_HOME/chichi77-keykey/update-notification.json`.
The defaults are `~/.config` and `~/.local/state` respectively. Invalid consent
values are treated as disabled. User state remains after package removal; the
autostart command points to the installed executable and cannot check after that
executable has been removed. Disable the option before uninstalling to remove
the entry, or remove the user autostart file manually.

## FreeBSD ports integration

The existing port is
[chinese/fcitx5-keykey](https://www.freshports.org/chinese/fcitx5-keykey/).
At implementation time it packages `v1.3.1` with `PORTREVISION=1` and uses
`python:build`. Python must now also be a runtime dependency, with GTK 3 and the
matching Python-flavored PyGObject binding. See the supplied
[`update-notification.patch`](../packaging/freebsd/update-notification.patch),
which adds those dependencies and all four new installed files. It also fixes
the chosen interpreter with `-DPython3_EXECUTABLE=${PYTHON_CMD}`. GNUInstallDirs
uses the selected prefix; `/usr/local/bin`, `/usr/local/share` and the selected
Python interpreter are baked into the launcher, with no `/usr/bin/python3` or
systemd assumption. GTK opens the browser through Gio's default URI handler.

The patch is for the ports maintainer **after selecting a new immutable upstream
release tag containing this feature**. It deliberately does not change
DISTVERSION/distinfo to the existing beta1 tag: that tag predates this code.
Update DISTVERSION, reset PORTREVISION when appropriate, regenerate distinfo,
then apply the dependency/plist changes. The source change does not itself
publish a FreeBSD port update. Do not execute network checks during package
installation or enable periodic checks for every user.

Native FreeBSD acceptance before port publication:

```sh
make stage check-plist
${PYTHON_CMD} ${WRKSRC}/tests/test_update_notify.py
${PYTHON_CMD} -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk, Gio'
```

After installing in a FreeBSD XDG desktop session, open the Fcitx configuration
button, manually check, open the upstream page, enable/disable periodic checks,
log out/in and verify the notification action. Confirm no Linux package is
installed and a ports/pkg revision suffix does not affect the upstream comparison:
the compiled product version, not `1.3.1_1`, is the notification's current version.

## Local regression commands

```sh
python3 tests/test_update_notify.py
dbus-run-session -- xvfb-run -a python3 tests/test_update_notify_gui.py
# After installing only in an isolated test container/session:
dbus-run-session -- xvfb-run -a python3 tests/test_update_notify_install.py
ctest --test-dir out/build/notify -R 'update_notification|mode_keys' --output-on-failure
```

The core tests cover both platforms. The GTK tests exercise the real widgets and
Gio action with isolated responses, including duplicate checks, failures/retry,
default-off, disabling an in-flight check and notification deduplication. They do
not replace native FreeBSD desktop or GNOME Wayland acceptance.

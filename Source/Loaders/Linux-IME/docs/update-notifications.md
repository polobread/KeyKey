# Linux and FreeBSD update notifications

Open **更新通知與下載…** in the KeyKey Fcitx configuration, or launch
`keykey-update-notify` from the applications menu/terminal. Opening this window
does not check the network. **檢查新版** reads the reviewed shared notification RSS:

- Stable: `https://download.aws.polobread.com/keykey/update/stable/unix-fcitx5.xml`
- Beta opt-in additionally reads: `https://download.aws.polobread.com/keykey/update/beta/unix-fcitx5.xml`

The download button opens the exact official GitHub Release page in the default
browser, where both CDN and GitHub downloads can be listed. Clients do not query
the GitHub Releases API, raw tag sources, ports or pkg. Existing installed
clients need a new build containing this reader; publishing XML alone does not
redirect an older client. Deploy the empty initial feeds before shipping it.
See [shared feed publishing](https://github.com/polobread/KeyKey/blob/master/update/README.md#linuxfreebsd-共用-cdn-feed)
for the format and reviewed release process.

All desktop platforms use notification-only checks: installer packages are not
prefetched. Updating starts only after the user chooses it. On Linux/FreeBSD,
the user opens the release page, downloads the package and installs it through
the platform package manager.

**每週檢查新版並通知** is on by default for a user without saved settings.
The package installs an XDG desktop autostart entry under
`${CMAKE_INSTALL_FULL_SYSCONFDIR}/xdg/autostart` (`/etc/xdg/autostart` for Debian packages,
`/usr/local/etc/xdg/autostart` for the FreeBSD port). It starts one Gio application
after desktop login, without running a network request during package installation.
Existing saved choices are preserved; a saved opt-out exits before GTK startup
or any request. Enabling the option also creates a per-user XDG autostart entry,
compatible with older installations.
It attempts a check at most once every 7 days, including after failed checks;
restarting the desktop does not reset the interval. Each newer version is notified
once. There is no systemd or privileged service, so FreeBSD XDG desktops can use
the same tool. Closing the window retains enabled checks; disabling
the option removes its autostart entry, stops the timer and suppresses notification
from an already running request. An existing request can finish within its timeout.
The notification daemon must support freedesktop/Gio desktop notifications.

Stable releases are the default. **也通知 beta 測試版** explicitly includes beta
releases. Comparison uses the numeric prerelease suffix, with stable following
all beta versions for the same base version. For beta builds pass
`-DKEYKEY_UPDATE_VERSION=X.Y.Z-betaN`, replacing X.Y.Z with the product version
and N with a positive integer without leading zeros; CMake rejects a different base product version.
The Debian build script derives this from an exact matching checkout tag, or
accepts an explicit `KEYKEY_UPDATE_VERSION` for source archives. This metadata
does not change existing Debian artifact naming/version conventions.

Only verified Unix releases are added through feed PRs. Mobile-only releases
are excluded during publication by checking the tag's Unix product version.
Each item declares the verified Linux package architectures (`amd64`/`arm64`);
Linux filters on the current architecture. FreeBSD reads the same item as an
**upstream source release** notice and asks the user to update through ports/pkg.
Both platforms are announced together, without an extra FreeBSD delay or a
package-availability query. The port and binary repository may lag the upstream
release; the notice does not claim a pkg package is already available.

This tool does not download or run packages, modify the installed input method,
query privileged package managers, or create an APT/pkg repository. Release URLs
are constructed from strict version tags, never taken from untrusted metadata.
Network access uses HTTPS and a bounded response size. A background check has a
ten-second total UI deadline, shared across the stable and optional beta feed requests;
individual requests use the remaining time as their socket timeout. Timeout
restores the check button without retrying automatically. Manual retry ignores
late results from the expired worker, and closing a manual check cancels further
requests. The existing weekly schedule still waits 7 days after any attempt;
cross-host and non-HTTPS redirects are rejected. XML must be bounded UTF-8 RSS with the reviewed schema, version/channel, architecture and canonical Release link; DTD/entities and installer enclosures are rejected. No typing text is sent.

Preferences: `$XDG_CONFIG_HOME/chichi77-keykey/update-notification.json`.
Attempt time and last notified version:
`$XDG_STATE_HOME/chichi77-keykey/update-notification.json`.
The defaults are `~/.config` and `~/.local/state` respectively. Invalid consent
values are treated as disabled. Only an absent preferences file uses the new
default; an existing malformed file stays offline. User state remains after
package removal. The system entry uses `TryExec`, and any remaining autostart
command cannot check after the executable is removed. Disable the option before uninstalling to remove
the entry, or remove the user autostart file manually.

## FreeBSD ports integration

The existing port is
[chinese/fcitx5-keykey](https://www.freshports.org/chinese/fcitx5-keykey/).
At implementation time it packages `v1.3.1` with `PORTREVISION=1` and uses
`python:build`. Python must now also be a runtime dependency, with GTK 3 and the
matching Python-flavored PyGObject binding. See the supplied
[`update-notification.patch`](../packaging/freebsd/update-notification.patch),
which adds those dependencies and the notification and About launchers, desktop
entries, shared Python modules, motivation text, and icon. It also fixes
the chosen interpreter with `-DPython3_EXECUTABLE=${PYTHON_CMD}`. GNUInstallDirs
uses the selected prefix; `/usr/local/bin`, `/usr/local/share` and the selected
Python interpreter are baked into the launcher, with no `/usr/bin/python3` or
systemd assumption. GTK opens the browser through Gio's default URI handler.

Use the complete upstream source or the standalone source archive, which includes
`Source/Branding/ProjectMotivation.txt` and `Source/Branding/chichi77.png`. The port
installs these through CMake into `${PREFIX}/share/chichi77-keykey`, matching the
About module and plist. A partial source tree missing either resource is rejected
at CMake configuration time; do not patch only the temporary staging directory.

The patch is for the ports maintainer **after selecting a new immutable upstream
release tag containing this feature**. Select that release when updating
DISTVERSION/distinfo; do not select a tag that predates the notification tool.
Update DISTVERSION, reset PORTREVISION when appropriate, regenerate distinfo,
then apply the dependency/plist changes. The source change does not itself
publish a FreeBSD port update. Do not execute network checks during package installation. The packaged XDG
entry starts the default weekly check only after desktop login and honors saved
opt-outs. Prefixes outside the desktop's `XDG_CONFIG_DIRS` require adding their
`etc/xdg` directory to the session configuration or enabling the option once in
the UI to create a per-user entry.

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
Also open **關於琦琦輸入法…** from Fcitx settings and the applications menu;
confirm the installed version, full scrollable motivation text, icon, and both
official links are available.

## Local regression commands

```sh
python3 tests/test_update_notify.py
python3 tests/test_update_notify_lifecycle.py
dbus-run-session -- xvfb-run -a python3 tests/test_update_notify_gui.py
# After installing only in an isolated test container/session:
dbus-run-session -- xvfb-run -a python3 tests/test_update_notify_install.py
ctest --test-dir out/build/notify -R 'update_notification|mode_keys' --output-on-failure
```

The core tests cover both platforms. The GTK tests exercise the real widgets and
Gio action with isolated responses, including duplicate checks, failures/retry,
default-on, saved opt-outs, disabling an in-flight check and notification deduplication. They do
not replace native FreeBSD desktop or GNOME Wayland acceptance.

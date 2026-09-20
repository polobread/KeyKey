# Linux 1.2.8: Ubuntu Desktop 24.04 LTS

This is the first supported Linux release of chichi77 KeyKey. The supported
configuration is **Ubuntu Desktop 24.04 LTS, GNOME Shell 46, Fcitx 5, amd64**.
GNOME Wayland, GNOME X11, and XWayland input paths are covered. The release is
published separately as `linux-v1.2.8` because the existing cross-platform
`v1.2.8` release predates this Linux package set and contains a Linux preview.

## Install

Download these three `.deb` files, the panel source archive, and `SHA256SUMS` from the
[Linux 1.2.8 release](https://github.com/polobread/KeyKey/releases/tag/linux-v1.2.8)
into one directory:

- `chichi77-keykey-data_1.2.8-1+ubuntu24.04_all.deb`
- `fcitx5-chichi77-keykey_1.2.8-1+ubuntu24.04_amd64.deb`
- `gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_all.deb`
- `gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_source.tar.gz`

From that directory:

```sh
sha256sum -c SHA256SUMS
sudo apt install ./chichi77-keykey-data_1.2.8-1+ubuntu24.04_all.deb \
  ./fcitx5-chichi77-keykey_1.2.8-1+ubuntu24.04_amd64.deb \
  ./gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_all.deb \
  fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt6
```

Log out and back in. Add `chichi77 KeyKey Bopomofo` in Fcitx 5 Configuration,
then run `keykey-gnome-panel enable` for the GNOME candidate panel. Use
`keykey-gnome-panel status` to check it or `keykey-gnome-panel disable` to
turn it off for the current user. If a manually installed
`~/.local/share/gnome-shell/extensions/kimpanel@kde.org` exists, move it aside
and log in again so GNOME loads the packaged system extension. Existing Fcitx
configuration is preserved by package upgrades and removal.

The panel package contains separately licensed GPL-2.0 code based on Input
Method Panel v83. Its corresponding patched source archive is attached to the
release. The input engine and its data retain the licenses described in
[`LICENSING.md`](../../../../LICENSING.md).

## Included and verified

The Fcitx 5 addon provides five Traditional Bopomofo keyboard layouts
(Standard, ETen, ETen26, Hsu, Hanyu Pinyin), candidate selection, punctuation
and symbols, 30 associated-phrase collections and their settings, Chinese and
English modes, full-width input, and the native Fcitx settings pane. Cangjie
and Simplex are included as additional input methods.

The packaged addon passed the Ubuntu 24.04 X11 package install, upgrade,
removal, and reinstall gate, including 83 installed-package typing cases.
An Ubuntu 24.04.5 GNOME Shell 46 Wayland VM passed 168/168 GTK3, GTK4, and Qt6
typing and pointer cases across native Wayland and XWayland paths with the
packaged panel. The same panel passed 32/32 single-screen corner cases and
16/16 virtual dual-display cases with 100%/200% scaling, real second-row mouse
selection, and candidate clearing. Firefox Snap and Epiphany DOM fields passed
15/15 tested paths. GNOME X11 passed 76/76 desktop-safe cases. These are VM
and isolated desktop results; physical dual-monitor hardware was not tested.

## Known limits

- GNOME Text Editor 46 can lack an active input context under its default GTK
  Wayland route. Launch it with the packaged `keykey-fcitx-app gnome-text-editor`
  helper or the `Text Editor (琦琦注音)` launcher to use the tested direct Fcitx
  route. Other apps may need the same helper.
- GNOME's default GTK Wayland bridge can share one input context between apps,
  so Chinese/English and full-width mode may follow the shared context. Direct
  Fcitx routes passed the two-app mode isolation checks.
- On focus change with an unfinished reading, direct Fcitx and the GTK
  Wayland bridge handle the preedit differently. Commit or cancel the reading
  before switching fields when the destination text matters.
- Physical display hotplug, every monitor arrangement, alternate GNOME themes,
  all applications and sandbox variants, and every horizontal-panel appearance
  are not covered by this release validation.
- IBus, ARM64, Ubuntu versions other than 24.04, other desktop environments,
  Debian, Fedora, and other distributions are outside this release's support
  claim. Ubuntu 22.04 has development build and package checks only.

The remaining compatibility work is tracked in
[`LINUX_DEVELOPMENT_PLAN.md`](../../../../LINUX_DEVELOPMENT_PLAN.md) and
[`LINUX_TEST_PLAN.md`](../../../../LINUX_TEST_PLAN.md).

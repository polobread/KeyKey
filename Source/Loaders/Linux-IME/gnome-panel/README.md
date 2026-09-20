# GNOME Input Method Panel integration patch

This GPL-2.0 directory contains a patch and packaging tools for the upstream GNOME Shell
[Input Method Panel](https://github.com/wengxt/gnome-shell-extension-kimpanel)
extension, `kimpanel@kde.org` version 83. Its source and copyright remain
upstream's; see [COPYING](COPYING). The patch is kept separately from the
KeyKey engine and Fcitx addon.

The two changes address candidate placement when a focused client moves
between monitors:

- For a relative Wayland cursor rectangle, use the focused window's current
  monitor geometry scale divided by the rectangle's reported source scale.
  A 100% rectangle held across a move to a 200% monitor then follows the
  window until the frontend sends its next rectangle.
- For an absolute XWayland rectangle, remember the focused window and its
  frame origin when the rectangle arrives. While that same window remains
  focused, translate the cached rectangle by subsequent frame movement.
  A later fresh frontend rectangle resets the reference origin.

`upstream-v83/` contains the inspected JavaScript, stylesheet, metadata and
schema sources extracted from the official v83 archive (version tag 57768,
archive SHA-256 `b8d83c1bc6e903a280dc0492b9b4e3be4b2713ab96c669d1ae90e625eacf675f`).
Translations and generated files are omitted. `build-patched-extension.py`
checks the original `extension.js` and `panel.js` hashes before applying the
patch. `build-deb.py` checks every bundled source file, compiles the schema and
normalizes package timestamps (using `SOURCE_DATE_EPOCH` when supplied), and
produces an architecture-independent, separately licensed Ubuntu 24.04 package.
Two clean builds with the same source and epoch have identical SHA-256 hashes:

```sh
python3 build-patched-extension.py /path/to/official/kimpanel@kde.org \
  /tmp/kimpanel-keykey-v83
python3 build-deb.py ../out/gnome-panel
```

`ci/build-debian-packages.sh ubuntu-24.04 release-candidate` additionally
places a version-matched `*_source.tar.gz` beside the `.deb`, containing the
inspected upstream sources, patch, builder and GPL-2.0 license. Both files
appear in the output `SHA256SUMS` and hosted package artifact.

The package owns `/usr/share/gnome-shell/extensions/kimpanel@kde.org`, while
the Fcitx addon and data remain in their existing packages. On Ubuntu 24.04
GNOME Shell 46, install or upgrade the downloaded package with:

```sh
sudo apt install ./gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_all.deb
```

Use the newer `.deb` path for an upgrade; the package version must increase.
A user-local copy of the same UUID under
`~/.local/share/gnome-shell/extensions/kimpanel@kde.org` takes precedence;
move that copy aside and log out and in before enabling the system package.
Then run `keykey-gnome-panel enable`; use `keykey-gnome-panel status` to check
it and `keykey-gnome-panel disable` to turn it off for the current user.
Upgrading the `.deb` replaces only package-owned files; log out and in after
an upgrade so GNOME Shell loads the new code. Removal leaves user settings in
place. The package is restricted to GNOME Shell 46 and is not a dependency of
the Fcitx addon. Ubuntu 22.04 GNOME 42 needs its own compatible extension
build and validation. The complete decision and remaining gates are in
[GNOME candidate panel](../docs/gnome-candidate-panel.md).

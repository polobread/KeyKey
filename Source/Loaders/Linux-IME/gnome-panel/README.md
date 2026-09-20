# GNOME Input Method Panel integration patch

This directory contains a GPL-2.0 patch for the upstream GNOME Shell
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

`build-patched-extension.py` accepts only the inspected official v83 files
(`extension.js` and `panel.js` hashes are pinned in the script), copies the
source tree to a new directory, and applies the patch there. It does not
modify the installed extension:

```sh
python3 build-patched-extension.py /path/to/official/kimpanel@kde.org \
  /tmp/kimpanel-keykey-v83
```

The test guest uses GNOME Shell 46. After copying the two patched `.js` files
from the output over the guest's user-local official extension and restarting
GDM, `gnome-vm-multimonitor-smoke.py --panel kimpanel --mouse` checks both
100% and 200% second displays across eight toolkit/frontend paths. The clean
patched tree passed 16/16 of these second-display pointer cases and 32/32
single-display four-corner cases in GNOME Shell 46. This is a development
integration, not an installed KeyKey package dependency yet.
Ubuntu 22.04 GNOME 42 needs its own compatible extension build and validation
before this can be packaged as a supported release component. The complete
decision and remaining gates are in
[GNOME candidate panel](../docs/gnome-candidate-panel.md).

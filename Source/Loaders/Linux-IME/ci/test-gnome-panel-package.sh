#!/usr/bin/env bash
# Inspect the separate GNOME Shell 46 package without requiring a desktop.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo 'Usage: test-gnome-panel-package.sh RELEASE_DEB [PREVIEW_DEB]' >&2
  exit 2
fi
release=$1
preview=${2:-}
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
panel_dir=$script_dir/../gnome-panel
package=gnome-shell-extension-keykey-kimpanel
uuid=kimpanel@kde.org

test "$(dpkg-deb --field "$release" Package)" = "$package"
test "$(dpkg-deb --field "$release" Architecture)" = all
test "$(dpkg-deb --field "$release" Version)" = 83+keykey1-1+ubuntu24.04
dependencies=$(dpkg-deb --field "$release" Depends)
[[ $dependencies == *'gnome-shell (>= 46~)'* ]]
[[ $dependencies == *'gnome-shell (<< 47~)'* ]]
if [[ -n $preview ]]; then
  test "$(dpkg-deb --field "$preview" Package)" = "$package"
  preview_version=$(dpkg-deb --field "$preview" Version)
  release_version=$(dpkg-deb --field "$release" Version)
  dpkg --compare-versions "$preview_version" lt "$release_version"
fi

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
python3 "$panel_dir/build-patched-extension.py" \
  "$panel_dir/upstream-v83" "$scratch/expected"
glib-compile-schemas --strict "$scratch/expected/schemas"
dpkg-deb --extract "$release" "$scratch/installed"
installed="$scratch/installed/usr/share/gnome-shell/extensions/$uuid"
for file in extension.js indicator.js lib.js menu.js metadata.json \
            panel.js prefs.js stylesheet.css \
            schemas/org.gnome.shell.extensions.kimpanel.gschema.xml \
            schemas/gschemas.compiled; do
  cmp "$scratch/expected/$file" "$installed/$file"
done
test -x "$scratch/installed/usr/bin/keykey-gnome-panel"
bash -n "$scratch/installed/usr/bin/keykey-gnome-panel"
test -f "$scratch/installed/usr/share/doc/$package/copyright"
test -f "$scratch/installed/usr/share/doc/$package/source"
if find "$scratch/installed/usr" -type f | grep -Eq '/fcitx5/|/chichi77-keykey/data/'; then
  echo 'GNOME panel package contains a KeyKey engine or data file.' >&2
  exit 1
fi
echo "Verified $package payload and upgrade ordering."

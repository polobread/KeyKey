#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 ubuntu-22.04|ubuntu-24.04 [release-candidate|upgrade-fixture]" >&2
  exit 2
fi

target=$1
variant=${2:-release-candidate}
case "$target" in
  ubuntu-22.04)
    distribution=jammy
    version_suffix=ubuntu22.04
    lintian_context_open=
    lintian_context_close=
    ;;
  ubuntu-24.04)
    distribution=noble
    version_suffix=ubuntu24.04
    lintian_context_open='['
    lintian_context_close=']'
    ;;
  *)
    echo "Unsupported Debian package target: $target" >&2
    exit 2
    ;;
esac
case "$variant" in
  release-candidate|upgrade-fixture) ;;
  *)
    echo "Unsupported package variant: $variant" >&2
    exit 2
    ;;
esac

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
linux_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
repository_root=$(CDPATH='' cd -- "$linux_dir/../../.." && pwd)
architecture=$(dpkg --print-architecture)
product_version=$(sed -n \
  's/^project(KeyKeyLinux VERSION \([^ ]*\) LANGUAGES.*$/\1/p' \
  "$linux_dir/CMakeLists.txt")
if [[ ! "$product_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Could not read a valid product version from CMakeLists.txt." >&2
  exit 1
fi

case "$variant" in
  release-candidate)
    debian_version="${product_version}-1+${version_suffix}"
    ;;
  upgrade-fixture)
    debian_version="${product_version}~preview1-1+${version_suffix}"
    ;;
esac
if [[ -n "${KEYKEY_DEBIAN_VERSION:-}" ]]; then
  debian_version=$KEYKEY_DEBIAN_VERSION
fi
if [[ ! "$debian_version" =~ ^[0-9A-Za-z.+:~_-]+$ ]]; then
  echo "KEYKEY_DEBIAN_VERSION contains unsupported characters." >&2
  exit 2
fi

work_dir="$linux_dir/out/package-build/$target-$architecture-$variant"
source_root="$work_dir/chichi77-keykey-$product_version"
output_dir="$linux_dir/out/packages/$target-$architecture/$variant"
case "$work_dir" in "$linux_dir"/out/package-build/*) ;; *) exit 2 ;; esac
case "$output_dir" in "$linux_dir"/out/packages/*) ;; *) exit 2 ;; esac

cmake -E remove_directory "$work_dir"
cmake -E remove_directory "$output_dir"
mkdir -p \
  "$source_root/Source/Loaders" \
  "$source_root/Source/DataTables" \
  "$source_root/DataSource/McBopomofo" \
  "$source_root/LICENSES" \
  "$output_dir"

mkdir -p "$source_root/Source/Loaders/Linux-IME"
cp -a \
  "$linux_dir/CMakeLists.txt" \
  "$linux_dir/CMakePresets.json" \
  "$linux_dir/LICENSE.txt" \
  "$linux_dir/README.md" \
  "$source_root/Source/Loaders/Linux-IME/"
cp -a \
  "$linux_dir/adapters" \
  "$linux_dir/ci" \
  "$linux_dir/cmake" \
  "$linux_dir/data" \
  "$linux_dir/docs" \
  "$linux_dir/engine" \
  "$linux_dir/gnome-panel" \
  "$linux_dir/tests" \
  "$linux_dir/tools" \
  "$source_root/Source/Loaders/Linux-IME/"
cp -a "$linux_dir/packaging/debian" "$source_root/debian"
cp -a \
  "$repository_root/Source/DataTables/bpmf-ext.cin" \
  "$repository_root/Source/DataTables/cj-ext.cin" \
  "$repository_root/Source/DataTables/simplex-ext.cin" \
  "$repository_root/Source/DataTables/bpmf-punctuations.cin" \
  "$source_root/Source/DataTables/"
cp -a \
  "$repository_root/DataSource/AssociatedPhraseCollectionNames.tsv" \
  "$source_root/DataSource/"
cp -a \
  "$repository_root/DataSource/McBopomofo/phrase.occ" \
  "$repository_root/DataSource/McBopomofo/LICENSE.txt" \
  "$repository_root/DataSource/McBopomofo/README.md" \
  "$source_root/DataSource/McBopomofo/"
cp -a "$repository_root/DataSource/chichi77Collection" \
  "$source_root/DataSource/"
cp -a "$repository_root/LICENSE.txt" "$source_root/LICENSE.txt"
cp -a "$repository_root/LICENSES/MIT.txt" "$source_root/LICENSES/MIT.txt"

sed \
  -e "s/@DEBIAN_VERSION@/$debian_version/g" \
  -e "s/@DEBIAN_DISTRIBUTION@/$distribution/g" \
  "$source_root/debian/changelog.in" >"$source_root/debian/changelog"
sed \
  -e "s/@LINTIAN_CONTEXT_OPEN@/$lintian_context_open/g" \
  -e "s/@LINTIAN_CONTEXT_CLOSE@/$lintian_context_close/g" \
  "$source_root/debian/chichi77-keykey-data.lintian-overrides.in" \
  >"$source_root/debian/chichi77-keykey-data.lintian-overrides"
cmake -E remove -f "$source_root/debian/changelog.in"
cmake -E remove -f "$source_root/debian/chichi77-keykey-data.lintian-overrides.in"
chmod 0755 "$source_root/debian/rules"

(
  cd "$source_root"
  dpkg-buildpackage --build=binary --no-sign
)

find "$work_dir" -maxdepth 1 -type f \
  \( -name '*.deb' -o -name '*.changes' -o -name '*.buildinfo' \) \
  -exec cp -a {} "$output_dir/" \;

data_package="$output_dir/chichi77-keykey-data_${debian_version}_all.deb"
fcitx_package="$output_dir/fcitx5-chichi77-keykey_${debian_version}_${architecture}.deb"
test -f "$data_package"
test -f "$fcitx_package"

if [[ "$target" == ubuntu-24.04 ]]; then
  case "$variant" in
    release-candidate) panel_version=83+keykey1-1+ubuntu24.04 ;;
    upgrade-fixture) panel_version=83+keykey1~preview1-1+ubuntu24.04 ;;
  esac
  python3 "$source_root/Source/Loaders/Linux-IME/gnome-panel/build-deb.py" \
    "$output_dir" --version "$panel_version"
  panel_package="$output_dir/gnome-shell-extension-keykey-kimpanel_${panel_version}_all.deb"
  test -f "$panel_package"
  panel_source="$output_dir/gnome-shell-extension-keykey-kimpanel_${panel_version}_source.tar.gz"
  tar --sort=name --mtime='@1789862400' --owner=0 --group=0 --numeric-owner \
    --exclude='__pycache__' --exclude='*.pyc' \
    -C "$source_root/Source/Loaders/Linux-IME" -cf - gnome-panel | \
    gzip -n >"$panel_source"
  tar -tzf "$panel_source" >"$work_dir/panel-source-files.txt"
  grep -Fxq 'gnome-panel/COPYING' "$work_dir/panel-source-files.txt"
  grep -Fxq 'gnome-panel/kimpanel-v83.patch' "$work_dir/panel-source-files.txt"
  grep -Fxq 'gnome-panel/upstream-v83/extension.js' \
    "$work_dir/panel-source-files.txt"
  lintian --fail-on error "$panel_package"
  if [[ "$variant" == release-candidate ]]; then
    preview_panel="$linux_dir/out/packages/$target-$architecture/upgrade-fixture/gnome-shell-extension-keykey-kimpanel_83+keykey1~preview1-1+ubuntu24.04_all.deb"
    if [[ -f "$preview_panel" ]]; then
      "$linux_dir/ci/test-gnome-panel-package.sh" "$panel_package" "$preview_panel"
    else
      "$linux_dir/ci/test-gnome-panel-package.sh" "$panel_package"
    fi
  fi
fi

lintian --fail-on error "$output_dir"/*.changes
(
  cd "$output_dir"
  checksums=(./*.deb)
  if [[ "$target" == ubuntu-24.04 ]]; then
    checksums+=(./gnome-shell-extension-keykey-kimpanel_*_source.tar.gz)
  fi
  sha256sum "${checksums[@]}" >SHA256SUMS
)

printf '%s\n' \
  "Built Debian packages:" \
  "  $data_package" \
  "  $fcitx_package"
if [[ "$target" == ubuntu-24.04 ]]; then
  printf '  %s\n  %s\n' "$panel_package" "$panel_source"
fi

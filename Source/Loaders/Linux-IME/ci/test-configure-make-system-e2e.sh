#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "This test performs a temporary /usr/local install and must run as root." >&2
  exit 2
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
linux_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
build_root="$linux_dir/out/build/configure-make-system-e2e"
inner_build="$build_root/.keykey-configure-build"
artifact_dir=out/e2e/configure-make-system-e2e
installed=false

layout_value() {
  local variable_name=$1
  sed -n "s/^${variable_name}=//p" \
    "$inner_build/keykey-install-layout.txt"
}

cleanup() {
  local exit_code=$?
  if [[ "$installed" == true && -f "$build_root/Makefile" ]]; then
    make -C "$build_root" uninstall >/dev/null || exit_code=1
  fi
  if [[ -f "$build_root/Makefile" ]]; then
    make -C "$build_root" distclean >/dev/null || exit_code=1
  fi
  cmake -E remove_directory "$build_root"
  trap - EXIT
  exit "$exit_code"
}
trap cleanup EXIT

cmake -E remove_directory "$build_root"
mkdir -p "$build_root"
(
  cd "$build_root"
  "$linux_dir/configure" --enable-x11-e2e-host
  make -j2
  make check
)

prefix=$(layout_value prefix)
libdir=$(layout_value libdir)
datadir=$(layout_value datadir)
test "$prefix" = /usr/local

expected_files=(
  "$prefix/$libdir/fcitx5/chichi77-keykey.so"
  "$prefix/$datadir/fcitx5/addon/chichi77-keykey.conf"
  "$prefix/$datadir/fcitx5/inputmethod/chichi77-keykey-bopomofo.conf"
  "$prefix/$datadir/fcitx5/inputmethod/chichi77-keykey-cangjie.conf"
  "$prefix/$datadir/fcitx5/inputmethod/chichi77-keykey-simplex.conf"
  "$prefix/$datadir/chichi77-keykey/data/bpmf-ext.cin"
)
for expected_file in "${expected_files[@]}"; do
  if [[ -e "$expected_file" || -L "$expected_file" ]]; then
    echo "Refusing to overwrite an existing system file: $expected_file" >&2
    exit 1
  fi
done

make -C "$build_root" install
installed=true

system_fcitx_libdir=$(pkg-config --variable=libdir Fcitx5Core)
if [[ -z "$system_fcitx_libdir" ]]; then
  echo "Fcitx5Core did not report its system library directory." >&2
  exit 1
fi
addon_dirs="$prefix/$libdir/fcitx5:$system_fcitx_libdir/fcitx5"
if [[ -n "${FCITX_ADDON_DIRS:-}" ]]; then
  addon_dirs+=":$FCITX_ADDON_DIRS"
fi
data_dirs="$prefix/$datadir:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

KEYKEY_BUILD_DIR="out/build/configure-make-system-e2e/.keykey-configure-build" \
KEYKEY_E2E_INSTALL_SOURCE=system \
KEYKEY_E2E_ARTIFACT_DIR="$artifact_dir" \
KEYKEY_E2E_CASES=T01-X11-GTK3-BOPOMOFO-STANDARD \
KEYKEY_E2E_CONFIG_UI=OFF \
FCITX_ADDON_DIRS="$addon_dirs" \
XDG_DATA_DIRS="$data_dirs" \
  "$script_dir/run-x11-e2e.sh"

manifest="$inner_build/install_manifest.txt"
test -s "$manifest"
make -C "$build_root" uninstall
installed=false

while IFS= read -r installed_file; do
  if [[ -e "$installed_file" || -L "$installed_file" ]]; then
    echo "System uninstall left a manifest file behind: $installed_file" >&2
    exit 1
  fi
done <"$manifest"

make -C "$build_root" distclean
test ! -e "$build_root/Makefile"
test ! -e "$inner_build"

printf 'Default /usr/local source install and Fcitx X11 typing passed.\n'

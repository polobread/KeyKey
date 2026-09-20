#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "This test temporarily installs source-built files and must run as root." >&2
  exit 2
fi

mode=${1:---smoke}
case "$mode" in
  --smoke|--extended|--remaining) ;;
  *) echo "Usage: ci/test-configure-make-system-e2e.sh [--smoke|--extended|--remaining]" >&2; exit 2 ;;
esac

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
linux_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
system_fcitx_libdir=$(pkg-config --variable=libdir Fcitx5Core)
if [[ -z "$system_fcitx_libdir" ]]; then
  echo "Fcitx5Core did not report its system library directory." >&2
  exit 1
fi

build_root=
inner_build=
installed=false
sentinel=

layout_value() {
  local variable_name=$1
  sed -n "s/^${variable_name}=//p" \
    "$inner_build/keykey-install-layout.txt"
}

assert_manifest_removed() {
  local manifest=$1 installed_file
  test -s "$manifest"
  while IFS= read -r installed_file; do
    if [[ -e "$installed_file" || -L "$installed_file" ]]; then
      echo "Source uninstall left a manifest file behind: $installed_file" >&2
      return 1
    fi
  done <"$manifest"
}

cleanup() {
  local exit_code=$?
  if [[ "$installed" == true && -f "$build_root/Makefile" ]]; then
    make -C "$build_root" uninstall >/dev/null || exit_code=1
  fi
  if [[ -n "$sentinel" ]]; then
    rm -f -- "$sentinel"
  fi
  if [[ -n "$build_root" && -f "$build_root/Makefile" ]]; then
    make -C "$build_root" distclean >/dev/null || exit_code=1
  fi
  if [[ -n "$build_root" ]]; then
    cmake -E remove_directory "$build_root"
  fi
  if [[ -n "${KEYKEY_HOST_UID:-}" && -n "${KEYKEY_HOST_GID:-}" && \
      -d "$linux_dir/out/e2e/configure-make-system-e2e" ]]; then
    chown -R "$KEYKEY_HOST_UID:$KEYKEY_HOST_GID" \
      "$linux_dir/out/e2e/configure-make-system-e2e" || exit_code=1
  fi
  trap - EXIT
  exit "$exit_code"
}
trap cleanup EXIT

run_typing() {
  local profile=$1 run_name=$2 cases=$3 prefix=$4 libdir=$5 datadir=$6
  local addon_dirs="$prefix/$libdir/fcitx5:$system_fcitx_libdir/fcitx5"
  local data_dirs="$prefix/$datadir:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  if [[ -n "${FCITX_ADDON_DIRS:-}" ]]; then
    addon_dirs+=":$FCITX_ADDON_DIRS"
  fi

  KEYKEY_BUILD_DIR="out/build/configure-make-system-e2e-$profile/.keykey-configure-build" \
  KEYKEY_E2E_INSTALL_SOURCE=system \
  KEYKEY_E2E_ARTIFACT_DIR="out/e2e/configure-make-system-e2e/$profile/$run_name" \
  KEYKEY_E2E_CASES="$cases" \
  KEYKEY_E2E_CONFIG_UI=OFF \
  KEYKEY_E2E_EXPECTED_ADDON_PATH="$prefix/$libdir/fcitx5/chichi77-keykey.so" \
  FCITX_ADDON_DIRS="$addon_dirs" \
  XDG_DATA_DIRS="$data_dirs" \
    "$script_dir/run-x11-e2e.sh"
}

run_profile() {
  local profile=$1 expected_prefix=$2 expected_libdir=$3 expected_datadir=$4
  local cases=$5
  local prefix libdir datadir manifest target
  local args=(--enable-x11-e2e-host "--prefix=$expected_prefix")
  if [[ -n "$expected_libdir" ]]; then args+=("--libdir=$expected_libdir"); fi
  if [[ -n "$expected_datadir" ]]; then args+=("--datadir=$expected_datadir"); fi

  local next_build_root="$linux_dir/out/build/configure-make-system-e2e-$profile"
  if [[ -e "$next_build_root" ]]; then
    echo "Refusing to discard an existing source build: $next_build_root" >&2
    return 1
  fi
  build_root=$next_build_root
  inner_build="$build_root/.keykey-configure-build"
  installed=false
  sentinel=
  mkdir -p "$build_root"
  (
    cd "$build_root"
    "$linux_dir/configure" "${args[@]}"
    make -j2
    make check
  )

  prefix=$(layout_value prefix)
  libdir=$(layout_value libdir)
  datadir=$(layout_value datadir)
  test "$prefix" = "$expected_prefix"
  test -n "$libdir"
  test -n "$datadir"
  if [[ -n "$expected_libdir" ]]; then test "$libdir" = "$expected_libdir"; fi
  if [[ -n "$expected_datadir" ]]; then test "$datadir" = "$expected_datadir"; fi

  # Check every project-owned destination before a real system install. Shared
  # Fcitx and doc parent directories may already belong to the distribution.
  # CMake uninstall leaves empty directories, which are safe to reuse.
  for target in \
      "$prefix/$libdir/fcitx5/chichi77-keykey.so" \
      "$prefix/$datadir/fcitx5/addon/chichi77-keykey.conf" \
      "$prefix/$datadir/fcitx5/inputmethod/chichi77-keykey-bopomofo.conf" \
      "$prefix/$datadir/fcitx5/inputmethod/chichi77-keykey-cangjie.conf" \
      "$prefix/$datadir/fcitx5/inputmethod/chichi77-keykey-simplex.conf" \
      "$prefix/$datadir/chichi77-keykey" \
      "$prefix/$datadir/doc/chichi77-keykey"; do
    if [[ -d "$target" && ! -L "$target" && \
        ( "$target" == "$prefix/$datadir/chichi77-keykey" || \
        "$target" == "$prefix/$datadir/doc/chichi77-keykey" ) ]]; then
      if [[ -n $(find "$target" -mindepth 1 ! -type d -print -quit) ]]; then
        echo "Refusing to overwrite an existing system path: $target" >&2
        return 1
      fi
      continue
    fi
    if [[ -e "$target" || -L "$target" ]]; then
      echo "Refusing to overwrite an existing system path: $target" >&2
      return 1
    fi
  done

  make -C "$build_root" install
  installed=true
  manifest="$inner_build/install_manifest.txt"
  test -s "$manifest"
  run_typing "$profile" initial "$cases" "$prefix" "$libdir" "$datadir"

  if [[ "$mode" != --smoke && "$profile" == custom ]]; then
    sentinel="$prefix/$datadir/chichi77-keykey/data/preserve-user-file"
    touch "$sentinel"
  fi

  make -C "$build_root" uninstall
  installed=false
  assert_manifest_removed "$manifest"
  if [[ -n "$sentinel" ]]; then
    test -f "$sentinel"
    make -C "$build_root" install
    installed=true
    run_typing "$profile" reinstall \
      T01-X11-GTK3-BOPOMOFO-STANDARD,T01-X11-GTK4-BOPOMOFO-STANDARD,T01-X11-QT6-BOPOMOFO-STANDARD \
      "$prefix" "$libdir" "$datadir"
    make -C "$build_root" uninstall
    installed=false
    assert_manifest_removed "$manifest"
    test -f "$sentinel"
  fi

  printf '%s source install, typing, and manifest uninstall passed.\n' "$profile"
  if [[ -n "$sentinel" ]]; then
    rm -f -- "$sentinel"
    sentinel=
  fi
  make -C "$build_root" distclean
  test ! -e "$build_root/Makefile"
  test ! -e "$inner_build"
  cmake -E remove_directory "$build_root"
  build_root=
  inner_build=
}

if [[ "$mode" == --smoke ]]; then
  run_profile local /usr/local '' '' T01-X11-GTK3-BOPOMOFO-STANDARD
else
  if [[ "$mode" == --extended ]]; then
    run_profile local /usr/local '' '' all
  fi
  run_profile usr /usr '' '' all
  run_profile custom '/opt/chichi77 keykey source e2e' lib-custom share-custom all
fi

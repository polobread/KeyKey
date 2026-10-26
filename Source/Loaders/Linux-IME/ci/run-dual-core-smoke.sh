#!/usr/bin/env bash
# Isolated staged-addon smoke: no system install or user's Fcitx is touched.
set -euo pipefail
if [[ $# != 2 ]]; then
  echo "Usage: $0 BUILD_DIR STAGE_DIR" >&2
  exit 2
fi
build_dir=$(realpath "$1")
stage_dir=$(realpath "$2")
addon=$(find "$stage_dir/usr/lib" -type f -name chichi77-keykey.so -print -quit)
test -n "$addon"
export FCITX_ADDON_DIRS="$(dirname "$addon"):$(pkg-config --variable=libdir Fcitx5Core)/fcitx5"
export XDG_DATA_DIRS="$stage_dir/usr/share:/usr/local/share:/usr/share"
export CHICHI77_KEYKEY_DATA_DIR="$stage_dir/usr/share/chichi77-keykey/data"
export KEYKEY_E2E_EXPECTED_ADDON_PATH="$addon"
export KEYKEY_E2E_HOST="$build_dir/keykey_linux_gtk3_e2e_host"
export KEYKEY_E2E_GTK4_HOST="$build_dir/keykey_linux_gtk4_e2e_host"
export KEYKEY_E2E_QT6_HOST="$build_dir/keykey_linux_qt6_e2e_host"
export KEYKEY_E2E_CONFIG_UI=OFF
export KEYKEY_E2E_SESSION_MODE=managed
export GIO_USE_VFS=local
export GTK_USE_PORTAL=0
export KEYKEY_E2E_CASES="${KEYKEY_DUAL_CORE_SMOKE_CASES:-T01-X11-GTK3-BOPOMOFO-STANDARD,T01-X11-GTK3-BOPOMOFO-SMART,T01-X11-GTK4-BOPOMOFO-STANDARD,T01-X11-QT6-BOPOMOFO-STANDARD,T04-X11-GTK3-CANGJIE,T05-X11-GTK3-SIMPLEX}"
# Inherit no personal DB overrides even when called from a developer shell.
unset CHICHI77_KEYKEY_USER_DB CHICHI77_KEYKEY_GUANYINMA_USER_DB
unset FCITX_CONFIG_HOME FCITX_DATA_HOME FCITX_CONFIG_DIRS FCITX_DATA_DIRS
for core in Legacy Guanyinma; do
  export KEYKEY_E2E_INPUT_CORE="$core"
  runtime=$(mktemp -d /tmp/keykey-dual-core-smoke.XXXXXX)
  export KEYKEY_E2E_RUNTIME_ROOT="$runtime"
  export XDG_CACHE_HOME="$runtime/cache"
  export KEYKEY_E2E_ARTIFACT_DIR="$build_dir/dual-core-smoke/$core"
  mkdir -p "$KEYKEY_E2E_ARTIFACT_DIR"
  # Portal services can leave FUSE mountpoints alive briefly after the private
  # bus exits. Cleanup cannot turn passed typing assertions into a failure.
  trap 'cmake -E remove_directory "$runtime" 2>/dev/null || true' EXIT
  dbus-run-session -- bash ci/run-x11-e2e-session.sh
  if [[ "$core" == Guanyinma ]]; then
    if ! grep -Fq 'KeyKey active core: Guanyinma' "$KEYKEY_E2E_ARTIFACT_DIR/fcitx5.log"; then
      echo "Rust smoke did not activate Guanyinma; fallback cannot count as passing." >&2
      exit 1
    fi
    if grep -Fq 'Guanyinma 無法啟用' "$KEYKEY_E2E_ARTIFACT_DIR/fcitx5.log"; then
      echo "Rust initialization failed during the smoke." >&2
      exit 1
    fi
  elif grep -Fq 'KeyKey active core: Guanyinma' "$KEYKEY_E2E_ARTIFACT_DIR/fcitx5.log"; then
    echo "The Legacy smoke unexpectedly activated Rust." >&2
    exit 1
  fi
  for _ in {1..10}; do
    cmake -E remove_directory "$runtime" 2>/dev/null || true
    [[ ! -e "$runtime" ]] && break
    sleep 0.1
  done
  trap - EXIT
done

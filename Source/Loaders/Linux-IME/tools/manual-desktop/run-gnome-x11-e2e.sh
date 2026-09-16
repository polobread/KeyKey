#!/usr/bin/env bash
# Run the installed-addon typing matrix inside the isolated GNOME X11 desktop.
set -euo pipefail

tool_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
linux_root=$(cd -- "$tool_dir/../.." && pwd)
session_root=${KEYKEY_MANUAL_DESKTOP_DIR:-$linux_root/out/manual-vnc}
build_dir=${KEYKEY_BUILD_DIR:-out/build/ubuntu-24.04-package-amd64}
artifact_dir=${KEYKEY_E2E_ARTIFACT_DIR:-out/e2e/ubuntu-24.04-gnome-x11-amd64}

if [[ ${1:-} == --help ]]; then
  printf '%s\n' \
    'Run the installed Fcitx 5 addon matrix in the active manual GNOME X11 desktop.' \
    'Start that desktop first as documented in docs/manual-desktop.md.' \
    'Defaults to the desktop-safe cases, which never restart the desktop Fcitx process.' \
    'Overrides: KEYKEY_BUILD_DIR, KEYKEY_E2E_ARTIFACT_DIR, KEYKEY_E2E_CASES.'
  exit 0
fi
if [[ $# -ne 0 ]]; then
  printf 'Unknown argument; use --help.\n' >&2
  exit 2
fi
case "$build_dir" in
  out/build/*) ;;
  *) printf 'KEYKEY_BUILD_DIR must be a child of out/build.\n' >&2; exit 2 ;;
esac
case "$artifact_dir" in
  out/e2e/*) ;;
  *) printf 'KEYKEY_E2E_ARTIFACT_DIR must be a child of out/e2e.\n' >&2; exit 2 ;;
esac

gtk3_host="$linux_root/$build_dir/keykey_linux_gtk3_e2e_host"
gtk4_host="$linux_root/$build_dir/keykey_linux_gtk4_e2e_host"
qt6_host="$linux_root/$build_dir/keykey_linux_qt6_e2e_host"
for host in "$gtk3_host" "$gtk4_host" "$qt6_host"; do
  if [[ ! -x $host ]]; then
    printf 'Missing desktop test host: %s\n' "$host" >&2
    printf 'Build the current Ubuntu 24.04 package candidate before running this gate.\n' >&2
    exit 1
  fi
  missing_libraries=$(ldd "$host" 2>/dev/null |
    sed -n 's/^[[:space:]]*\([^[:space:]]*\) => not found$/\1/p')
  if [[ -n $missing_libraries ]]; then
    printf 'Missing runtime libraries for %s:\n%s\n' "$host" "$missing_libraries" >&2
    printf 'Install the desktop runtime packages listed in docs/manual-desktop.md.\n' >&2
    exit 1
  fi
done
if [[ ! -r $session_root/runtime/bus-address ]]; then
  printf 'No manual desktop session at %s.\n' "$session_root" >&2
  printf 'Start it with the command in docs/manual-desktop.md.\n' >&2
  exit 1
fi

cd "$linux_root"
cmake -E remove_directory "$artifact_dir"
mkdir -p "$artifact_dir"

export KEYKEY_E2E_HOST="$gtk3_host"
export KEYKEY_E2E_GTK4_HOST="$gtk4_host"
export KEYKEY_E2E_QT6_HOST="$qt6_host"
export KEYKEY_E2E_ARTIFACT_DIR="$linux_root/$artifact_dir"
export KEYKEY_E2E_RUNTIME_ROOT="$session_root"
export KEYKEY_E2E_SESSION_MODE=existing-gnome
export KEYKEY_E2E_CASES=${KEYKEY_E2E_CASES:-desktop-safe}
export KEYKEY_E2E_CONFIG_UI=OFF

exec "$tool_dir/session-command.sh" "$linux_root/ci/run-x11-e2e-session.sh"

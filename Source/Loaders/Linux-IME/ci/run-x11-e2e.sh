#!/usr/bin/env bash
set -euo pipefail

build_dir=${KEYKEY_BUILD_DIR:-out/build/ubuntu-24.04-x11-amd64}
stage_dir=${KEYKEY_STAGE_DIR:-out/stage/ubuntu-24.04-x11-amd64}
artifact_dir=${KEYKEY_E2E_ARTIFACT_DIR:-out/e2e/ubuntu-24.04-x11-amd64}
install_source=${KEYKEY_E2E_INSTALL_SOURCE:-stage}
host_uid=${KEYKEY_HOST_UID:-${SUDO_UID:-0}}
host_gid=${KEYKEY_HOST_GID:-${SUDO_GID:-0}}

case "$build_dir" in
  out/build/*) ;;
  *) echo "KEYKEY_BUILD_DIR must be a child of out/build." >&2; exit 2 ;;
esac
case "$install_source" in
  stage)
    case "$stage_dir" in
      out/stage/*) ;;
      *) echo "KEYKEY_STAGE_DIR must be a child of out/stage." >&2; exit 2 ;;
    esac
    ;;
  system) ;;
  *) echo "KEYKEY_E2E_INSTALL_SOURCE must be stage or system." >&2; exit 2 ;;
esac
case "$artifact_dir" in
  out/e2e/*) ;;
  *) echo "KEYKEY_E2E_ARTIFACT_DIR must be a child of out/e2e." >&2; exit 2 ;;
esac
if [[ ! "$host_uid" =~ ^[0-9]+$ || ! "$host_gid" =~ ^[0-9]+$ ]]; then
  echo "KEYKEY_HOST_UID and KEYKEY_HOST_GID must be numeric." >&2
  exit 2
fi

absolute_artifact_dir="$PWD/$artifact_dir"
cleanup_owner() {
  chown -R "$host_uid:$host_gid" "$absolute_artifact_dir" 2>/dev/null || true
}
trap cleanup_owner EXIT

cmake -E remove_directory "$artifact_dir"
mkdir -p "$artifact_dir"
if [[ "$install_source" == stage ]]; then
  cp -a "$stage_dir/usr/." /usr/
fi

e2e_host="$PWD/$build_dir/keykey_linux_gtk3_e2e_host"
test -x "$e2e_host"
export KEYKEY_E2E_HOST="$e2e_host"
export KEYKEY_E2E_ARTIFACT_DIR="$absolute_artifact_dir"

unset AT_SPI_BUS_ADDRESS DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR
dbus-run-session -- ci/run-x11-e2e-session.sh

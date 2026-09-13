#!/usr/bin/env bash
# shellcheck disable=SC2154
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=dev-container-common.sh
# shellcheck disable=SC1091
source "$script_dir/dev-container-common.sh"

usage() {
  cat <<'EOF'
Usage: ci/dev.sh COMMAND [ARGUMENT]

Commands:
  build              Incrementally configure and build.
  test               Incrementally build and run CTest.
  source             Test the configure and GNU Make source-build interface.
  e2e [CASE|all]     Stage the current build and run selected X11 typing cases.
  verify [CASE|all]  Run build, CTest, staged checks, and X11 typing.
  package            Build the Ubuntu 24.04 development .deb files once.
  shell              Open a shell in the persistent development container.
  status             Show development container state.
  up                 Start or reuse the development container.
  down               Remove the container but keep compilation caches.
EOF
}

ensure_container() {
  "$script_dir/dev-container.sh" ensure
}

run_as_developer() {
  docker exec \
    --user "$host_uid:$host_gid" \
    --env "HOME=$container_home" \
    --env "KEYKEY_BUILD_DIR=$build_dir" \
    --env "KEYKEY_STAGE_DIR=$stage_dir" \
    --workdir "$container_workdir" \
    "$container_name" "$@"
}

run_source_build() {
  docker exec \
    --env "HOME=$container_home" \
    --workdir "$container_workdir" \
    "$container_name" ci/dev-session-action.sh source
}

run_installed_e2e() {
  local cases=$1
  local key_delay=${KEYKEY_E2E_KEY_DELAY_MS:-25}
  docker exec \
    --env "KEYKEY_BUILD_DIR=$build_dir" \
    --env "KEYKEY_STAGE_DIR=$stage_dir" \
    --env "KEYKEY_E2E_ARTIFACT_DIR=$artifact_dir" \
    --env "KEYKEY_E2E_CASES=$cases" \
    --env "KEYKEY_E2E_KEY_DELAY_MS=$key_delay" \
    --env "KEYKEY_HOST_UID=$host_uid" \
    --env "KEYKEY_HOST_GID=$host_gid" \
    --workdir "$container_workdir" \
    "$container_name" ci/run-x11-e2e.sh
}

run_e2e() {
  local cases=$1
  run_as_developer ci/dev-session-action.sh stage
  run_installed_e2e "$cases"
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

command_name=$1
argument=${2:-}
case "$command_name" in
  up|down|status|shell)
    if [[ -n "$argument" ]]; then usage >&2; exit 2; fi
    exec "$script_dir/dev-container.sh" "$command_name"
    ;;
  build|test|package)
    if [[ -n "$argument" ]]; then usage >&2; exit 2; fi
    ensure_container
    run_as_developer ci/dev-session-action.sh "$command_name"
    ;;
  source)
    if [[ -n "$argument" ]]; then usage >&2; exit 2; fi
    ensure_container
    run_source_build
    ;;
  e2e)
    ensure_container
    run_e2e "${argument:-all}"
    ;;
  verify)
    ensure_container
    run_as_developer ci/dev-session-action.sh verify
    run_installed_e2e "${argument:-all}"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

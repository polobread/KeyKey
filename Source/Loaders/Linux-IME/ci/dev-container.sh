#!/usr/bin/env bash
# shellcheck disable=SC2154
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=dev-container-common.sh
# shellcheck disable=SC1091
source "$script_dir/dev-container-common.sh"

usage() {
  cat <<'EOF'
Usage: ci/dev-container.sh up|rebuild|status|shell|down

  up       Start or reuse the native-architecture Ubuntu 24.04 container.
  rebuild  Rebuild its dependency image, then recreate the container.
  status   Show the selected platform, image, volumes, and container state.
  shell    Open an interactive shell as the host user.
  down     Remove the container but retain incremental build volumes.
EOF
}

require_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "The Docker-compatible engine is not reachable." >&2
    echo "Start Rancher Desktop or Docker, then try again." >&2
    exit 1
  fi
}

container_exists() {
  docker container inspect "$container_name" >/dev/null 2>&1
}

container_running() {
  [[ "$(docker container inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)" == true ]]
}

container_ready() {
  local signature
  signature=$(docker container inspect \
    --format "{{.State.Running}}|{{ index .Config.Labels \"$definition_label\" }}|{{ index .Config.Labels \"$layout_label\" }}|{{ index .Config.Labels \"$repository_label\" }}" \
    "$container_name" 2>/dev/null || true)
  [[ "$signature" == "true|$definition_sha|$layout_version|$repository_root" ]]
}

image_definition_sha() {
  docker image inspect \
    --format "{{ index .Config.Labels \"$definition_label\" }}" \
    "$image" 2>/dev/null || true
}

build_image_if_needed() {
  local installed_sha
  installed_sha=$(image_definition_sha)
  if [[ "${KEYKEY_DEV_REBUILD_IMAGE:-OFF}" != ON && "$installed_sha" == "$definition_sha" ]]; then
    return
  fi

  echo "Building the Ubuntu 24.04 development image for $platform..."
  docker build \
    --platform "$platform" \
    --target package-build \
    --label "$definition_label=$definition_sha" \
    --file "$container_file" \
    --tag "$image" \
    "$container_context"
}

remove_stale_container() {
  if ! container_exists; then
    return
  fi

  local existing_layout existing_repository existing_sha
  existing_repository=$(docker container inspect \
    --format "{{ index .Config.Labels \"$repository_label\" }}" \
    "$container_name")
  if [[ "$existing_repository" != "$repository_root" ]]; then
    echo "Container name collision: $container_name belongs to another checkout." >&2
    exit 1
  fi
  existing_sha=$(docker container inspect \
    --format "{{ index .Config.Labels \"$definition_label\" }}" \
    "$container_name")
  existing_layout=$(docker container inspect \
    --format "{{ index .Config.Labels \"$layout_label\" }}" \
    "$container_name")
  if [[ "$existing_sha" != "$definition_sha" || "$existing_layout" != "$layout_version" ]]; then
    echo "Recreating the development container after a configuration change..."
    docker container rm --force "$container_name" >/dev/null
  fi
}

initialize_writable_paths() {
  docker exec "$container_name" mkdir -p \
    "$container_workdir/$build_dir" \
    "$container_workdir/$stage_dir" \
    "$container_home"
  docker exec "$container_name" chown -R "$host_uid:$host_gid" \
    "$container_workdir/$build_dir" \
    "$container_workdir/$stage_dir" \
    "$container_home"
}

up_container() {
  require_docker
  build_image_if_needed
  remove_stale_container

  if container_exists; then
    if ! container_running; then
      docker container start "$container_name" >/dev/null
    fi
    initialize_writable_paths
    echo "Development container is ready: $container_name ($platform)"
    return
  fi

  docker volume create "$build_volume" >/dev/null
  docker volume create "$stage_volume" >/dev/null
  docker run --detach \
    --name "$container_name" \
    --platform "$platform" \
    --label "$definition_label=$definition_sha" \
    --label "$repository_label=$repository_root" \
    --label "$layout_label=$layout_version" \
    --volume "$repository_root:/workspace/KeyKey" \
    --volume "$build_volume:$container_workdir/$build_dir" \
    --volume "$stage_volume:$container_workdir/out/stage" \
    --workdir "$container_workdir" \
    "$image" \
    sleep infinity >/dev/null
  initialize_writable_paths
  echo "Development container is ready: $container_name ($platform)"
}

ensure_container() {
  if container_ready; then
    return
  fi
  up_container
}

show_status() {
  require_docker
  local state=missing
  if container_exists; then
    state=$(docker container inspect --format '{{.State.Status}}' "$container_name")
  fi
  printf '%s\n' \
    "platform=$platform" \
    "image=$image" \
    "container=$container_name" \
    "state=$state" \
    "buildVolume=$build_volume" \
    "stageVolume=$stage_volume"
}

open_shell() {
  up_container
  local terminal_args=()
  if [[ -t 0 && -t 1 ]]; then
    terminal_args=(-it)
  fi
  docker exec "${terminal_args[@]}" \
    --user "$host_uid:$host_gid" \
    --env "HOME=$container_home" \
    --workdir "$container_workdir" \
    "$container_name" bash
}

down_container() {
  require_docker
  if container_exists; then
    docker container rm --force "$container_name" >/dev/null
    echo "Removed $container_name; incremental build volumes were retained."
  else
    echo "Development container is already absent: $container_name"
  fi
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

case "$1" in
  up) up_container ;;
  ensure) ensure_container ;;
  rebuild)
    KEYKEY_DEV_REBUILD_IMAGE=ON
    export KEYKEY_DEV_REBUILD_IMAGE
    if container_exists; then
      docker container rm --force "$container_name" >/dev/null
    fi
    up_container
    ;;
  status) show_status ;;
  shell) open_shell ;;
  down) down_container ;;
  *) usage >&2; exit 2 ;;
esac

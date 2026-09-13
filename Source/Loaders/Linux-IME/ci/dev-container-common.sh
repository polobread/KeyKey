#!/usr/bin/env bash
# shellcheck disable=SC2034

if [[ -n "${KEYKEY_DEV_CONTAINER_COMMON_LOADED:-}" ]]; then
  return 0
fi
KEYKEY_DEV_CONTAINER_COMMON_LOADED=1

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
linux_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
repository_root=$(CDPATH='' cd -- "$linux_dir/../../.." && pwd)

platform=${KEYKEY_DOCKER_PLATFORM:-}
if [[ -z "$platform" ]]; then
  case "$(uname -m)" in
    arm64|aarch64) platform=linux/arm64 ;;
    x86_64|amd64) platform=linux/amd64 ;;
    *)
      echo "Cannot select a native Docker platform for $(uname -m)." >&2
      echo "Set KEYKEY_DOCKER_PLATFORM to linux/amd64 or linux/arm64." >&2
      exit 2
      ;;
  esac
fi

case "$platform" in
  linux/amd64) architecture=amd64 ;;
  linux/arm64) architecture=arm64 ;;
  *)
    echo "Unsupported KEYKEY_DOCKER_PLATFORM: $platform" >&2
    exit 2
    ;;
esac

repository_key=$(printf '%s' "$repository_root" | cksum | awk '{ print $1 }')
container_name=${KEYKEY_DEV_CONTAINER_NAME:-chichi77-keykey-dev-$repository_key-$architecture}
image=${KEYKEY_DEV_IMAGE:-chichi77-keykey-linux-dev:ubuntu-24.04-session-$architecture}
volume_prefix=chichi77-keykey-dev-$repository_key-$architecture
build_volume=${KEYKEY_DEV_BUILD_VOLUME:-$volume_prefix-build}
stage_volume=${KEYKEY_DEV_STAGE_VOLUME:-$volume_prefix-stage}
container_workdir=/workspace/KeyKey/Source/Loaders/Linux-IME
build_dir=out/build/dev-container-$architecture
stage_dir=out/stage/dev-container-$architecture
artifact_dir=out/e2e/dev-container-$architecture
container_home=/tmp/chichi77-keykey-dev-$(id -u)
container_context=$script_dir/containers
container_file=$container_context/ubuntu-24.04.Dockerfile
definition_label=io.chichi77.keykey.dev-definition-sha256
repository_label=io.chichi77.keykey.repository
layout_label=io.chichi77.keykey.dev-layout-version
layout_version=2

if command -v shasum >/dev/null 2>&1; then
  definition_sha=$(shasum -a 256 "$container_file" | awk '{ print $1 }')
elif command -v sha256sum >/dev/null 2>&1; then
  definition_sha=$(sha256sum "$container_file" | awk '{ print $1 }')
else
  echo "A SHA-256 utility is required to track the development image." >&2
  exit 1
fi

host_uid=$(id -u)
host_gid=$(id -g)

#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 ubuntu-22.04|ubuntu-24.04" >&2
  exit 2
fi

target=$1
case "$target" in
  ubuntu-22.04|ubuntu-24.04)
    ;;
  *)
    echo "Unsupported container target: $target" >&2
    exit 2
    ;;
esac

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
linux_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
repository_root=$(CDPATH='' cd -- "$linux_dir/../../.." && pwd)
container_context="$linux_dir/ci/containers"
platform=${KEYKEY_DOCKER_PLATFORM:-linux/amd64}
case "$platform" in
  linux/amd64)
    architecture=amd64
    ;;
  linux/arm64)
    architecture=arm64
    ;;
  *)
    echo "Unsupported KEYKEY_DOCKER_PLATFORM: $platform" >&2
    exit 2
    ;;
esac

image="chichi77-keykey-linux-dev:$target-$architecture"
build_dir="out/build/$target-$architecture"
stage_dir="out/stage/$target-$architecture"
bind_mount_uid=$(id -u)
bind_mount_gid=$(id -g)
if docker info --format '{{json .SecurityOptions}}' |
    grep -Fq '"name=rootless"'; then
  bind_mount_uid=0
  bind_mount_gid=0
fi

docker build \
  --platform "$platform" \
  --target build \
  --file "$container_context/$target.Dockerfile" \
  --tag "$image" \
  "$container_context"

docker run --rm \
  --platform "$platform" \
  --user "$bind_mount_uid:$bind_mount_gid" \
  --env KEYKEY_BUILD_DIR="$build_dir" \
  --env KEYKEY_STAGE_DIR="$stage_dir" \
  --volume "$repository_root:/workspace/KeyKey" \
  --workdir /workspace/KeyKey/Source/Loaders/Linux-IME \
  "$image" \
  ci/build-and-test.sh

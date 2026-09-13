#!/usr/bin/env bash
set -euo pipefail

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

image="chichi77-keykey-linux-dev:ubuntu-24.04-x11-$architecture"
build_dir="out/build/ubuntu-24.04-x11-$architecture"
stage_dir="out/stage/ubuntu-24.04-x11-$architecture"
artifact_dir="out/e2e/ubuntu-24.04-x11-$architecture"

docker build \
  --platform "$platform" \
  --target x11-e2e \
  --file "$container_context/ubuntu-24.04.Dockerfile" \
  --tag "$image" \
  "$container_context"

docker run --rm \
  --platform "$platform" \
  --user "$(id -u):$(id -g)" \
  --env KEYKEY_BUILD_DIR="$build_dir" \
  --env KEYKEY_STAGE_DIR="$stage_dir" \
  --env KEYKEY_BUILD_X11_E2E_HOST=ON \
  --volume "$repository_root:/workspace/KeyKey" \
  --workdir /workspace/KeyKey/Source/Loaders/Linux-IME \
  "$image" \
  ci/build-and-test.sh

docker run --rm \
  --platform "$platform" \
  --env KEYKEY_BUILD_DIR="$build_dir" \
  --env KEYKEY_STAGE_DIR="$stage_dir" \
  --env KEYKEY_E2E_ARTIFACT_DIR="$artifact_dir" \
  --env KEYKEY_E2E_CASES="${KEYKEY_E2E_CASES:-all}" \
  --env KEYKEY_E2E_KEY_DELAY_MS="${KEYKEY_E2E_KEY_DELAY_MS:-80}" \
  --env KEYKEY_HOST_UID="$(id -u)" \
  --env KEYKEY_HOST_GID="$(id -g)" \
  --volume "$repository_root:/workspace/KeyKey" \
  --workdir /workspace/KeyKey/Source/Loaders/Linux-IME \
  "$image" \
  ci/run-x11-e2e.sh

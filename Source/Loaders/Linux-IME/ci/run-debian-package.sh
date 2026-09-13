#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 ubuntu-22.04|ubuntu-24.04" >&2
  exit 2
fi
target=$1
case "$target" in
  ubuntu-22.04|ubuntu-24.04) ;;
  *) echo "Unsupported package target: $target" >&2; exit 2 ;;
esac

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
linux_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
repository_root=$(CDPATH='' cd -- "$linux_dir/../../.." && pwd)
container_context="$linux_dir/ci/containers"
platform=${KEYKEY_DOCKER_PLATFORM:-linux/amd64}
case "$platform" in
  linux/amd64) architecture=amd64 ;;
  linux/arm64) architecture=arm64 ;;
  *) echo "Unsupported KEYKEY_DOCKER_PLATFORM: $platform" >&2; exit 2 ;;
esac

build_image="chichi77-keykey-linux-package-build:$target-$architecture"
test_image="chichi77-keykey-linux-package-test:$target-$architecture"
build_dir="out/build/$target-package-$architecture"
artifact_dir="out/e2e/$target-package-$architecture"
release_dir="out/packages/$target-$architecture/release-candidate"
fixture_dir="out/packages/$target-$architecture/upgrade-fixture"

docker build \
  --platform "$platform" \
  --target package-build \
  --file "$container_context/$target.Dockerfile" \
  --tag "$build_image" \
  "$container_context"
docker build \
  --platform "$platform" \
  --target package-test \
  --file "$container_context/$target.Dockerfile" \
  --tag "$test_image" \
  "$container_context"

if [[ "$target" == ubuntu-24.04 ]]; then
  build_x11_host=ON
else
  build_x11_host=OFF
fi
docker run --rm \
  --platform "$platform" \
  --user "$(id -u):$(id -g)" \
  --env KEYKEY_BUILD_DIR="$build_dir" \
  --env KEYKEY_STAGE_DIR="out/stage/$target-package-$architecture" \
  --env KEYKEY_BUILD_X11_E2E_HOST="$build_x11_host" \
  --volume "$repository_root:/workspace/KeyKey" \
  --workdir /workspace/KeyKey/Source/Loaders/Linux-IME \
  "$build_image" \
  ci/build-and-test.sh

if [[ "$target" == ubuntu-24.04 ]]; then
  docker run --rm \
    --platform "$platform" \
    --user "$(id -u):$(id -g)" \
    --volume "$repository_root:/workspace/KeyKey" \
    --workdir /workspace/KeyKey/Source/Loaders/Linux-IME \
    "$build_image" \
    ci/build-debian-packages.sh "$target" upgrade-fixture
fi
docker run --rm \
  --platform "$platform" \
  --user "$(id -u):$(id -g)" \
  --volume "$repository_root:/workspace/KeyKey" \
  --workdir /workspace/KeyKey/Source/Loaders/Linux-IME \
  "$build_image" \
  ci/build-debian-packages.sh "$target" release-candidate

test_args=("$release_dir")
if [[ "$target" == ubuntu-24.04 ]]; then
  test_args+=("$fixture_dir")
  run_x11_e2e=ON
else
  run_x11_e2e=OFF
fi
docker run --rm \
  --platform "$platform" \
  --env KEYKEY_BUILD_DIR="$build_dir" \
  --env KEYKEY_PACKAGE_ARTIFACT_DIR="$artifact_dir" \
  --env KEYKEY_RUN_X11_E2E="$run_x11_e2e" \
  --env KEYKEY_HOST_UID="$(id -u)" \
  --env KEYKEY_HOST_GID="$(id -g)" \
  --volume "$repository_root:/workspace/KeyKey" \
  --workdir /workspace/KeyKey/Source/Loaders/Linux-IME \
  "$test_image" \
  ci/test-debian-package-lifecycle.sh "${test_args[@]}"

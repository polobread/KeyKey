#!/usr/bin/env bash
set -euo pipefail

build_dir=${KEYKEY_BUILD_DIR:-out/build/dev-container}
stage_dir=${KEYKEY_STAGE_DIR:-out/stage/dev-container}

case "$build_dir" in out/build/*) ;; *) exit 2 ;; esac
case "$stage_dir" in out/stage/*) ;; *) exit 2 ;; esac

usage() {
  echo "Usage: ci/dev-session-action.sh build|test|stage|verify|package" >&2
}

configure() {
  cmake -S . -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DKEYKEY_BUILD_FCITX5=ON \
    -DKEYKEY_BUILD_X11_E2E_HOST=ON
}

build() {
  configure
  cmake --build "$build_dir"
}

stage() {
  build
  cmake -E remove_directory "$stage_dir"
  DESTDIR="$PWD/$stage_dir" cmake --install "$build_dir"
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

case "$1" in
  build)
    build
    ;;
  test)
    build
    ctest --test-dir "$build_dir" --output-on-failure
    ;;
  stage)
    stage
    ;;
  verify)
    KEYKEY_BUILD_DIR="$build_dir" \
    KEYKEY_STAGE_DIR="$stage_dir" \
    KEYKEY_BUILD_X11_E2E_HOST=ON \
      ci/build-and-test.sh
    ;;
  package)
    ci/build-debian-packages.sh ubuntu-24.04 release-candidate
    ;;
  *)
    usage
    exit 2
    ;;
esac

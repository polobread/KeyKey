#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
linux_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
repository_root=$(CDPATH='' cd -- "$linux_dir/../../.." && pwd)
test_root=${KEYKEY_SOURCE_ARCHIVE_TEST_ROOT:-$linux_dir/out/source-archive-test}

case "$test_root" in
  /*) ;;
  *) test_root="$linux_dir/$test_root" ;;
esac
case "$test_root" in
  "$linux_dir"/out/*) ;;
  *)
    echo "KEYKEY_SOURCE_ARCHIVE_TEST_ROOT must be a child of the Linux out directory." >&2
    exit 2
    ;;
esac

cmake -E remove_directory "$test_root"
mkdir -p "$test_root/extracted"

version=$(sed -n 's/^project(KeyKeyLinux VERSION \([^ ]*\).*/\1/p' \
  "$linux_dir/CMakeLists.txt")
source_revision=${KEYKEY_SOURCE_REVISION:-unknown}
if [[ -n "${KEYKEY_SOURCE_ARCHIVE:-}" ]]; then
  archive=$KEYKEY_SOURCE_ARCHIVE
  if [[ "$archive" != /* ]]; then
    archive="$linux_dir/$archive"
  fi
  test -f "$archive"
  test -f "$archive.sha256"
else
  archive="$test_root/chichi77-keykey-linux-$version.tar.gz"
  "$script_dir/create-source-archive.sh" "$archive"
  source_revision=$(git -c "safe.directory=$repository_root" \
    -C "$repository_root" rev-parse HEAD)
fi

(
  cd "$(dirname -- "$archive")"
  sha256sum --check "$(basename -- "$archive").sha256"
)
tar -xzf "$archive" -C "$test_root/extracted"

archive_root="$test_root/extracted/chichi77-keykey-linux-$version"
test -x "$archive_root/Source/Loaders/Linux-IME/configure"
test ! -e "$archive_root/.git"
if find "$archive_root" \
    \( -name CMakeCache.txt -o -name build.ninja -o -name .ninja_deps \) \
    -print -quit | grep -q .; then
  echo "The source archive contains generated build cache files." >&2
  exit 1
fi

KEYKEY_SOURCE_REVISION="$source_revision" \
KEYKEY_CONFIGURE_TEST_ROOT="$archive_root/Source/Loaders/Linux-IME/out/source-test" \
  "$archive_root/Source/Loaders/Linux-IME/ci/test-configure-make.sh" \
    --out-of-source-only

archive_sha256=$(sha256sum "$archive" | awk '{ print $1 }')
cat >"$test_root/result.txt" <<EOF
buildMethod=configure-make
sourceArchive=$(basename -- "$archive")
sourceArchiveSha256=$archive_sha256
sourceRevision=$source_revision
gitDirectoryPresent=false
buildCachePresent=false
result=passed
EOF

printf 'Source archive rebuild passed; report: %s\n' "$test_root/result.txt"

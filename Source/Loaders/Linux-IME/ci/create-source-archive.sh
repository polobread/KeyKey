#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
linux_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
repository_root=$(CDPATH='' cd -- "$linux_dir/../../.." && pwd)
revision=${2:-HEAD}

version=$(git -C "$repository_root" show \
  "$revision:Source/Loaders/Linux-IME/CMakeLists.txt" |
  sed -n 's/^project(KeyKeyLinux VERSION \([^ ]*\).*/\1/p')
if [[ -z "$version" ]]; then
  echo "Could not read the Linux version from revision $revision." >&2
  exit 1
fi

if [[ $# -ge 1 ]]; then
  archive=$1
else
  archive="$linux_dir/out/source/chichi77-keykey-linux-$version.tar.gz"
fi

archive_parent=$(dirname -- "$archive")
archive_name=$(basename -- "$archive")
mkdir -p "$archive_parent"
archive_parent=$(CDPATH='' cd -- "$archive_parent" && pwd)
archive="$archive_parent/$archive_name"

source_paths=(
  BUILDING.md
  LICENSING.md
  LICENSE.txt
  LICENSES/MIT.txt
  LINUX_DEVELOPMENT_PLAN.md
  LINUX_TEST_PLAN.md
  README.md
  DataSource/AssociatedPhraseCollectionNames.tsv
  DataSource/McBopomofo/LICENSE.txt
  DataSource/McBopomofo/phrase.occ
  DataSource/chichi77Collection
  Source/DataTables/bpmf-ext.cin
  Source/DataTables/bpmf-punctuations.cin
  Source/DataTables/cj-ext.cin
  Source/DataTables/simplex-ext.cin
  Source/Loaders/Linux-IME
)

git -C "$repository_root" archive \
  --format=tar.gz \
  --prefix="chichi77-keykey-linux-$version/" \
  --output="$archive" \
  "$revision" -- "${source_paths[@]}"

(
  cd "$archive_parent"
  sha256sum "$archive_name" >"$archive_name.sha256"
)

printf 'Created %s\n' "$archive"
printf 'Checksum %s.sha256\n' "$archive"

#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
linux_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
repository_root=$(CDPATH='' cd -- "$linux_dir/../../.." && pwd)
revision=${2:-HEAD}
git_command=(git -c "safe.directory=$repository_root" -C "$repository_root")

version=$("${git_command[@]}" show \
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
  DataSource/McBopomofo/BPMFMappings.txt
  DataSource/AISyntheticBigram/supplemental-lexicon.tsv
  DataSource/AISyntheticBigram/numeric-unit-lexicon.tsv
  DataSource/AISyntheticBigram/corpus-v1.txt
  DataSource/AISyntheticBigram/corpus-v2.txt
  DataSource/AISyntheticBigram/corpus-v3.txt
  DataSource/AISyntheticBigram/corpus-typing-feedback.txt
  DataSource/AISyntheticBigram/article-corpus-2300-exact-dedup.txt
  DataSource/chichi77Collection
  Source/DataTables/bpmf-ext.cin
  Source/DataTables/bpmf-punctuations.cin
  Source/DataTables/cj-ext.cin
  Source/DataTables/simplex-ext.cin
  Source/Loaders/Linux-IME
)

"${git_command[@]}" archive \
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

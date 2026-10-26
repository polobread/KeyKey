#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
linux_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
repository_root=$(CDPATH='' cd -- "$linux_dir/../../.." && pwd)
source "$script_dir/prepare-guanyinma.sh"
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

source "$script_dir/model-source-paths.sh"
source "$script_dir/about-source-paths.sh"
source "$script_dir/guanyinma-source-paths.sh"

source_paths=(
  BUILDING.md
  LICENSING.md
  LICENSE.txt
  LICENSES/MIT.txt
  docs/GUANYINMA_LINUX_ADAPTER.md
  docs/CANGJIE_PREFIX_CANDIDATES_PLAN.md
  docs/DESKTOP_CANGJIE_PREFIX_TRIAL.md
  README.md
  DataSource/AssociatedPhraseCollectionNames.tsv
  DataSource/McBopomofo/LICENSE.txt
  DataSource/McBopomofo/README.md
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
  Source/Shared
  Source/DataTables/cj-ext.cin
  Source/DataTables/simplex-ext.cin
  "${about_source_paths[@]}"
  "${model_paths[@]}"
  "${guanyinma_source_paths[@]}"
  Source/Loaders/Linux-IME
)

if [[ "${KEYKEY_SOURCE_WORKTREE:-0}" == 1 ]]; then
  # Explicit local review mode includes pending source changes without making
  # a Git commit. Official release assets continue to use the revision above.
  tar --exclude='*/out' --exclude='*/target' --exclude='*/__pycache__' \
    --exclude='*.pyc' --exclude='*/.git' \
    --transform="s,^,chichi77-keykey-linux-$version/," \
    -C "$repository_root" -czf "$archive" "${source_paths[@]}"
else
  "${git_command[@]}" archive \
    --format=tar.gz \
    --prefix="chichi77-keykey-linux-$version/" \
    --output="$archive" \
    "$revision" -- "${source_paths[@]}"
fi

# Source assets carry checksummed registry sources, so
# consumers need no network or pre-existing Cargo cache during compilation.
if [[ "${KEYKEY_SOURCE_VENDOR_GUANYINMA:-ON}" == ON ]]; then
  vendor_root=$(mktemp -d "$archive_parent/.keykey-vendor.XXXXXX")
  trap 'rm -rf "$vendor_root"' EXIT
  tar -xzf "$archive" -C "$vendor_root"
  python3 "$vendor_root/chichi77-keykey-linux-$version/Source/Guanyinma/tools/prepare-unix-vendor.py" \
    --core-dir "$vendor_root/chichi77-keykey-linux-$version/Source/Guanyinma"
  archive_epoch=$("${git_command[@]}" show -s --format=%ct "$revision")
  tar --sort=name --mtime="@$archive_epoch" --owner=0 --group=0 --numeric-owner \
    -C "$vendor_root" -cf - "chichi77-keykey-linux-$version" | gzip -n >"$archive.tmp"
  mv "$archive.tmp" "$archive"
  rm -rf "$vendor_root"
  trap - EXIT
fi

(
  cd "$archive_parent"
  sha256sum "$archive_name" >"$archive_name.sha256"
)

printf 'Created %s\n' "$archive"
printf 'Checksum %s.sha256\n' "$archive"

#!/usr/bin/env bash
set -euo pipefail

build_dir=${KEYKEY_BUILD_DIR:-out/build/native}
stage_dir=${KEYKEY_STAGE_DIR:-out/stage/native}

case "$stage_dir" in
  out/stage/*)
    ;;
  *)
    echo "KEYKEY_STAGE_DIR must be a child of out/stage." >&2
    exit 2
    ;;
esac

cmake -S . -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DKEYKEY_BUILD_FCITX5=ON \
  -DKEYKEY_BUILD_X11_E2E_HOST="${KEYKEY_BUILD_X11_E2E_HOST:-OFF}"
cmake --build "$build_dir"
ctest --test-dir "$build_dir" --output-on-failure

cmake -E remove_directory "$stage_dir"
DESTDIR="$PWD/$stage_dir" cmake --install "$build_dir"

addon=$(find "$stage_dir/usr/lib" -type f -path '*/fcitx5/chichi77-keykey.so' -print -quit)
if [[ -z "$addon" ]]; then
  echo "The staged Fcitx 5 addon was not found." >&2
  exit 1
fi

ldd "$addon"
if ldd "$addon" | grep -q 'not found'; then
  echo "The staged Fcitx 5 addon has unresolved dependencies." >&2
  exit 1
fi
if ! nm -D --defined-only "$addon" |
    awk '$3 == "fcitx_addon_factory_instance" { found = 1 } END { exit !found }'; then
  echo "The staged addon does not export the Fcitx factory symbol." >&2
  exit 1
fi

test -f "$stage_dir/usr/share/fcitx5/addon/chichi77-keykey.conf"
test -f "$stage_dir/usr/share/fcitx5/inputmethod/chichi77-keykey-bopomofo.conf"
test -f "$stage_dir/usr/share/fcitx5/inputmethod/chichi77-keykey-cangjie.conf"
test -f "$stage_dir/usr/share/fcitx5/inputmethod/chichi77-keykey-simplex.conf"
test -f "$stage_dir/usr/share/chichi77-keykey/data/bpmf-ext.cin"
test -f "$stage_dir/usr/share/chichi77-keykey/data/cj-ext.cin"
test -f "$stage_dir/usr/share/chichi77-keykey/data/simplex-ext.cin"
test -f "$stage_dir/usr/share/chichi77-keykey/data/bpmf-punctuations.cin"
test -f "$stage_dir/usr/share/chichi77-keykey/data/tc2sc.cin"
test -f "$stage_dir/usr/share/chichi77-keykey/data/associated-phrases/McBopomofo.occ"
test -f "$stage_dir/usr/share/chichi77-keykey/data/associated-phrases/display-names.tsv"
test -f "$stage_dir/usr/share/chichi77-keykey/data/associated-phrases/phrase.general.tsv"
test "$(find "$stage_dir/usr/share/chichi77-keykey/data/associated-phrases" \
  -maxdepth 1 -type f -name 'phrase.*.tsv' | wc -l)" -eq 29
test -f "$stage_dir/usr/share/doc/chichi77-keykey/LICENSE-linux-frontend.txt"
test -f "$stage_dir/usr/share/doc/chichi77-keykey/LICENSE-MIT.txt"
test -f "$stage_dir/usr/share/doc/chichi77-keykey/LICENSE-yahoo-bsd.txt"
test -f "$stage_dir/usr/share/doc/chichi77-keykey/LICENSE-McBopomofo.txt"
test -f "$stage_dir/usr/share/doc/chichi77-keykey/LICENSE-associated-phrase-collections.txt"

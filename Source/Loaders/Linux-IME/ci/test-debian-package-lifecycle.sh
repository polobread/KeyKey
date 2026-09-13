#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 RELEASE_PACKAGE_DIR [UPGRADE_FIXTURE_PACKAGE_DIR]" >&2
  exit 2
fi
if [[ $(id -u) -ne 0 ]]; then
  echo "Package lifecycle testing must run as root in an ephemeral runner or container." >&2
  exit 1
fi

release_dir=$1
fixture_dir=${2:-}
run_e2e=${KEYKEY_RUN_X11_E2E:-OFF}
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
linux_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
repository_root=$(CDPATH='' cd -- "$linux_dir/../../.." && pwd)
case "$release_dir" in out/packages/*/release-candidate) ;; *)
  echo "Release packages must be under out/packages/*/release-candidate." >&2
  exit 2
esac
if [[ -n "$fixture_dir" ]]; then
  case "$fixture_dir" in out/packages/*/upgrade-fixture) ;; *)
    echo "Upgrade fixtures must be under out/packages/*/upgrade-fixture." >&2
    exit 2
  esac
fi
case "$run_e2e" in ON|OFF) ;; *)
  echo "KEYKEY_RUN_X11_E2E must be ON or OFF." >&2
  exit 2
esac
release_dir="$PWD/$release_dir"
if [[ -n "$fixture_dir" ]]; then
  fixture_dir="$PWD/$fixture_dir"
fi

build_dir=${KEYKEY_BUILD_DIR:-out/build/ubuntu-24.04-package-amd64}
artifact_dir=${KEYKEY_PACKAGE_ARTIFACT_DIR:-out/e2e/debian-package-lifecycle}
host_uid=${KEYKEY_HOST_UID:-${SUDO_UID:-0}}
host_gid=${KEYKEY_HOST_GID:-${SUDO_GID:-0}}
case "$build_dir" in out/build/*) ;; *) exit 2 ;; esac
case "$artifact_dir" in out/e2e/*) ;; *) exit 2 ;; esac
if [[ ! "$host_uid" =~ ^[0-9]+$ || ! "$host_gid" =~ ^[0-9]+$ ]]; then
  echo "KEYKEY_HOST_UID and KEYKEY_HOST_GID must be numeric." >&2
  exit 2
fi

absolute_artifact_dir="$PWD/$artifact_dir"
test_config_root=$(mktemp -d /tmp/chichi77-keykey-package-config.XXXXXX)
cleanup() {
  exit_code=$?
  chown -R "$host_uid:$host_gid" "$absolute_artifact_dir" 2>/dev/null || true
  cmake -E remove_directory "$test_config_root"
  trap - EXIT
  exit "$exit_code"
}
trap cleanup EXIT

cmake -E remove_directory "$artifact_dir"
mkdir -p "$artifact_dir" "$test_config_root/chichi77-keykey"
printf 'preserve-on-package-removal\n' \
  >"$test_config_root/chichi77-keykey/package-test-sentinel"
export XDG_CONFIG_HOME="$test_config_root"
apt-get update

locate_packages() {
  package_dir=$1
  data_package=$(find "$package_dir" -maxdepth 1 -type f \
    -name 'chichi77-keykey-data_*_all.deb' -print -quit)
  fcitx_package=$(find "$package_dir" -maxdepth 1 -type f \
    -name "fcitx5-chichi77-keykey_*_$(dpkg --print-architecture).deb" \
    -print -quit)
  test -n "$data_package"
  test -n "$fcitx_package"
}

install_packages() {
  locate_packages "$1"
  apt-get install --yes --no-install-recommends "$data_package" "$fcitx_package"
}

verify_install() {
  expected_version=$1
  actual_data_version=$(dpkg-query -W -f='${Version}' chichi77-keykey-data)
  actual_fcitx_version=$(dpkg-query -W -f='${Version}' fcitx5-chichi77-keykey)
  test "$actual_data_version" = "$expected_version"
  test "$actual_fcitx_version" = "$expected_version"

  addon=$(dpkg-query -L fcitx5-chichi77-keykey |
    awk '/\/fcitx5\/chichi77-keykey[.]so$/ { print; exit }')
  test -n "$addon"
  test -f "$addon"
  test -f /usr/share/fcitx5/addon/chichi77-keykey.conf
  test -f /usr/share/fcitx5/inputmethod/chichi77-keykey-bopomofo.conf
  test -f /usr/share/fcitx5/inputmethod/chichi77-keykey-cangjie.conf
  test -f /usr/share/fcitx5/inputmethod/chichi77-keykey-simplex.conf
  test -f /usr/share/chichi77-keykey/data/bpmf-ext.cin
  test -f /usr/share/chichi77-keykey/data/cj-ext.cin
  test -f /usr/share/chichi77-keykey/data/simplex-ext.cin
  test -f /usr/share/chichi77-keykey/data/bpmf-punctuations.cin
  test -f /usr/share/chichi77-keykey/data/tc2sc.cin
  test -f /usr/share/chichi77-keykey/data/associated-phrases/McBopomofo.occ
  test -f /usr/share/chichi77-keykey/data/associated-phrases/display-names.tsv
  test -f /usr/share/chichi77-keykey/data/associated-phrases/phrase.general.tsv
  test "$(find /usr/share/chichi77-keykey/data/associated-phrases \
    -maxdepth 1 -type f -name 'phrase.*.tsv' | wc -l)" -eq 29
  test -f /usr/share/doc/chichi77-keykey-data/copyright
  test -f /usr/share/doc/fcitx5-chichi77-keykey/copyright
  cmp "$repository_root/Source/DataTables/bpmf-ext.cin" \
    /usr/share/chichi77-keykey/data/bpmf-ext.cin
  cmp "$repository_root/Source/DataTables/cj-ext.cin" \
    /usr/share/chichi77-keykey/data/cj-ext.cin
  cmp "$repository_root/Source/DataTables/simplex-ext.cin" \
    /usr/share/chichi77-keykey/data/simplex-ext.cin
  cmp "$repository_root/Source/DataTables/bpmf-punctuations.cin" \
    /usr/share/chichi77-keykey/data/bpmf-punctuations.cin
  cmp "$linux_dir/data/tc2sc.cin" \
    /usr/share/chichi77-keykey/data/tc2sc.cin
  cmp "$repository_root/DataSource/McBopomofo/phrase.occ" \
    /usr/share/chichi77-keykey/data/associated-phrases/McBopomofo.occ
  cmp "$repository_root/DataSource/AssociatedPhraseCollectionNames.tsv" \
    /usr/share/chichi77-keykey/data/associated-phrases/display-names.tsv
  cmp "$repository_root/DataSource/chichi77Collection/phrase.general.tsv" \
    /usr/share/chichi77-keykey/data/associated-phrases/phrase.general.tsv
  dpkg --verify chichi77-keykey-data fcitx5-chichi77-keykey
  ldd "$addon" | tee "$absolute_artifact_dir/ldd-$expected_version.txt"
  if ldd "$addon" | grep -q 'not found'; then
    echo "The packaged Fcitx addon has unresolved dependencies." >&2
    exit 1
  fi
  if strings "$addon" | grep -Fq '/workspace/KeyKey'; then
    echo "The packaged addon leaks the CI source checkout path." >&2
    exit 1
  fi
  dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' \
    chichi77-keykey-data fcitx5-chichi77-keykey \
    >"$absolute_artifact_dir/packages-$expected_version.txt"
  dpkg-query -L chichi77-keykey-data fcitx5-chichi77-keykey \
    >"$absolute_artifact_dir/files-$expected_version.txt"
}

run_installed_e2e() {
  label=$1
  local config_ui=OFF
  if [[ "$run_e2e" != ON ]]; then
    return
  fi
  if [[ "$label" == reinstalled ]]; then
    config_ui=ON
  fi
  KEYKEY_E2E_INSTALL_SOURCE=system \
  KEYKEY_E2E_ARTIFACT_DIR="$artifact_dir/$label" \
  KEYKEY_E2E_CONFIG_UI="$config_ui" \
  KEYKEY_BUILD_DIR="$build_dir" \
    ci/run-x11-e2e.sh
}

if [[ -n "$fixture_dir" ]]; then
  locate_packages "$fixture_dir"
  fixture_version=$(dpkg-deb --field "$fcitx_package" Version)
  install_packages "$fixture_dir"
  verify_install "$fixture_version"
  run_installed_e2e installed-fixture
fi

locate_packages "$release_dir"
release_version=$(dpkg-deb --field "$fcitx_package" Version)
install_packages "$release_dir"
verify_install "$release_version"
if [[ -n "$fixture_dir" ]]; then
  run_installed_e2e upgraded
else
  run_installed_e2e installed
fi
test -f "$test_config_root/chichi77-keykey/package-test-sentinel"

apt-get remove --yes fcitx5-chichi77-keykey chichi77-keykey-data
if dpkg-query -W chichi77-keykey-data fcitx5-chichi77-keykey >/dev/null 2>&1; then
  echo "One or more KeyKey packages remain installed after removal." >&2
  exit 1
fi
test ! -e /usr/share/fcitx5/addon/chichi77-keykey.conf
test ! -e /usr/share/chichi77-keykey/data/bpmf-ext.cin
test ! -e /usr/share/chichi77-keykey/data/tc2sc.cin
test ! -e /usr/share/chichi77-keykey/data/associated-phrases
test -f "$test_config_root/chichi77-keykey/package-test-sentinel"

install_packages "$release_dir"
verify_install "$release_version"
run_installed_e2e reinstalled
test -f "$test_config_root/chichi77-keykey/package-test-sentinel"

printf '%s\n' \
  "{\"test\":\"T14-DEBIAN-PACKAGE-LIFECYCLE\",\"version\":\"$release_version\",\"architecture\":\"$(dpkg --print-architecture)\",\"upgradeFixture\":\"$([[ -n "$fixture_dir" ]] && printf true || printf false)\",\"x11Typing\":\"$run_e2e\",\"status\":\"passed\"}" \
  >"$absolute_artifact_dir/result.json"

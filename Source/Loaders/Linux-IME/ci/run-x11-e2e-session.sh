#!/usr/bin/env bash
set -euo pipefail

test -n "${KEYKEY_E2E_HOST:-}"
test -n "${KEYKEY_E2E_ARTIFACT_DIR:-}"
test -n "${KEYKEY_E2E_RUNTIME_ROOT:-}"

known_cases=(
  T01-X11-GTK3-BOPOMOFO-STANDARD
  T02-X11-GTK3-BOPOMOFO-STANDARD
  T02-X11-GTK3-BOPOMOFO-ETEN
  T02-X11-GTK3-BOPOMOFO-ETEN26
  T02-X11-GTK3-BOPOMOFO-HSU
  T02-X11-GTK3-BOPOMOFO-HANYU-PINYIN
  T04-X11-GTK3-CANGJIE
  T04-X11-GTK3-CANGJIE-ENDKEY-ERROR
  T04-X11-GTK3-CANGJIE-WILDCARD
  T05-X11-GTK3-SIMPLEX
  T05-X11-GTK3-SIMPLEX-FULL-CODE
  T06-X11-GTK3-CANDIDATE-NAVIGATION
  T07-X11-GTK3-ASSOCIATED-PHRASE
  T07-X11-GTK3-ASSOCIATED-PHRASE-CATEGORY
  T07-X11-GTK3-ASSOCIATED-PHRASE-DISABLED
  T07-X11-GTK3-ASSOCIATED-PHRASE-LEGACY-CONFIG
  T07-X11-GTK3-ASSOCIATED-PHRASE-DBUS-PERSISTENCE
  T07-X11-FCITX5-CONFIG-UI-PERSISTENCE
  T08-X11-GTK3-FULL-WIDTH
  T08-X11-GTK3-TRADITIONAL-TO-SIMPLIFIED
  T12-X11-GTK3-SYMBOL-LIST
)
requested_cases=${KEYKEY_E2E_CASES:-all}
config_ui=${KEYKEY_E2E_CONFIG_UI:-ON}
key_delay_ms=${KEYKEY_E2E_KEY_DELAY_MS:-80}
case "$config_ui" in ON|OFF) ;; *)
  echo "KEYKEY_E2E_CONFIG_UI must be ON or OFF." >&2
  exit 2
esac
if [[ ! "$key_delay_ms" =~ ^[0-9]+$ ]]; then
  echo "KEYKEY_E2E_KEY_DELAY_MS must be a non-negative integer." >&2
  exit 2
fi

requested_case_list=()
if [[ "$requested_cases" == all ]]; then
  requested_case_list=("${known_cases[@]}")
else
  IFS=',' read -r -a requested_case_list <<<"$requested_cases"
fi
if [[ ${#requested_case_list[@]} -eq 0 ]]; then
  echo "KEYKEY_E2E_CASES must be all or a comma-separated case list." >&2
  exit 2
fi

for requested_case in "${requested_case_list[@]}"; do
  matched=false
  for known_case in "${known_cases[@]}"; do
    if [[ "$requested_case" == "$known_case" ]]; then
      matched=true
      break
    fi
  done
  if [[ "$matched" != true ]]; then
    echo "Unknown X11 E2E case: $requested_case" >&2
    printf 'Known cases:\n' >&2
    printf '  %s\n' "${known_cases[@]}" >&2
    exit 2
  fi
done

selected_cases=()
for known_case in "${known_cases[@]}"; do
  if [[ "$requested_cases" == all && "$config_ui" == OFF && \
      "$known_case" == T07-X11-FCITX5-CONFIG-UI-PERSISTENCE ]]; then
    continue
  fi
  for requested_case in "${requested_case_list[@]}"; do
    if [[ "$requested_case" == "$known_case" ]]; then
      selected_cases+=("$known_case")
      break
    fi
  done
done

selected_cases_json=
e2e_apps=gtk3-entry
for selected_case in "${selected_cases[@]}"; do
  if [[ -n "$selected_cases_json" ]]; then
    selected_cases_json+=,
  fi
  selected_cases_json+="\"$selected_case\""
  if [[ "$selected_case" == T07-X11-FCITX5-CONFIG-UI-PERSISTENCE ]]; then
    e2e_apps=gtk3-entry+fcitx5-config-qt
  fi
done

case_selected() {
  local target=$1 selected_case
  for selected_case in "${selected_cases[@]}"; do
    if [[ "$selected_case" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

runtime_root=$KEYKEY_E2E_RUNTIME_ROOT
export DISPLAY=:99
export GTK_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
if case_selected T07-X11-FCITX5-CONFIG-UI-PERSISTENCE; then
  export QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
fi
export XDG_CONFIG_HOME="$runtime_root/config"
export XDG_DATA_HOME="$runtime_root/data"
export XDG_RUNTIME_DIR="$runtime_root/runtime"
mkdir -p "$XDG_CONFIG_HOME/fcitx5/conf" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
dbus-update-activation-environment \
  DISPLAY XDG_CONFIG_HOME XDG_DATA_HOME XDG_RUNTIME_DIR
install -m 0644 tests/fixtures/fcitx5-profile "$XDG_CONFIG_HOME/fcitx5/profile"

xvfb_pid=
fcitx_pid=
host_pid=
test_status=failed
cleanup() {
  exit_code=$?
  if [[ "$test_status" == passed ]]; then
    failure_count=0
    failure_element=
  else
    failure_count=1
    failure_element='<failure message="Installed Fcitx 5 to GTK 3 typing flow failed"/>'
  fi
  printf '%s\n' \
    "{\"tests\":[$selected_cases_json],\"distro\":\"ubuntu-24.04\",\"arch\":\"$(uname -m)\",\"session\":\"x11-xvfb\",\"framework\":\"fcitx5\",\"app\":\"$e2e_apps\",\"status\":\"$test_status\"}" \
    >"$KEYKEY_E2E_ARTIFACT_DIR/result.json"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    "<testsuite name=\"chichi77-keykey-linux-x11-e2e\" tests=\"1\" failures=\"$failure_count\">" \
    "  <testcase classname=\"fcitx5.gtk3.x11\" name=\"installed addon layouts, input methods, candidate navigation, output filters, symbols, and native settings\">$failure_element</testcase>" \
    '</testsuite>' \
    >"$KEYKEY_E2E_ARTIFACT_DIR/junit.xml"
  if [[ -n "$host_pid" ]]; then kill "$host_pid" 2>/dev/null || true; fi
  if [[ -n "$fcitx_pid" ]]; then kill "$fcitx_pid" 2>/dev/null || true; fi
  if [[ -n "$xvfb_pid" ]]; then kill "$xvfb_pid" 2>/dev/null || true; fi
  if [[ -n "$host_pid" ]]; then wait "$host_pid" 2>/dev/null || true; fi
  if [[ -n "$fcitx_pid" ]]; then wait "$fcitx_pid" 2>/dev/null || true; fi
  if [[ -n "$xvfb_pid" ]]; then wait "$xvfb_pid" 2>/dev/null || true; fi
  trap - EXIT
  exit "$exit_code"
}
trap cleanup EXIT

Xvfb "$DISPLAY" -screen 0 1024x768x24 -nolisten tcp \
  >"$KEYKEY_E2E_ARTIFACT_DIR/xvfb.log" 2>&1 &
xvfb_pid=$!
display_ready=false
for _ in {1..100}; do
  if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    display_ready=true
    break
  fi
  sleep 0.1
done
if [[ "$display_ready" != true ]]; then
  echo "Xvfb did not become ready." >&2
  exit 1
fi

start_fcitx() {
  local fcitx_ready=false addon_ready=false
  fcitx5 >>"$KEYKEY_E2E_ARTIFACT_DIR/fcitx5.log" 2>&1 &
  fcitx_pid=$!
  for _ in {1..150}; do
    if ! kill -0 "$fcitx_pid" 2>/dev/null; then
      echo "Fcitx 5 exited before acquiring its D-Bus name." >&2
      exit 1
    fi
    if dbus-send --session --dest=org.freedesktop.DBus --type=method_call \
        --print-reply /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
        string:org.fcitx.Fcitx5 2>/dev/null | grep -Fq 'boolean true'; then
      fcitx_ready=true
      break
    fi
    sleep 0.1
  done
  if [[ "$fcitx_ready" != true ]]; then
    echo "Fcitx 5 did not become ready." >&2
    exit 1
  fi

  for _ in {1..150}; do
    if ! kill -0 "$fcitx_pid" 2>/dev/null; then
      echo "Fcitx 5 exited before loading the KeyKey addon." >&2
      exit 1
    fi
    if grep -Fq 'chichi77-keykey.so' "/proc/$fcitx_pid/maps"; then
      addon_ready=true
      break
    fi
    sleep 0.1
  done
  if [[ "$addon_ready" != true ]]; then
    echo "Fcitx 5 did not load the KeyKey addon." >&2
    exit 1
  fi
}

stop_fcitx() {
  if [[ -n "$fcitx_pid" ]]; then
    kill "$fcitx_pid"
    wait "$fcitx_pid" || true
    fcitx_pid=
  fi
}

restart_fcitx() {
  stop_fcitx
  start_fcitx
}

: >"$KEYKEY_E2E_ARTIFACT_DIR/fcitx5.log"
start_fcitx

bopomofo_layout=Standard
traditional_to_simplified=False
associated_phrase_collections=''
associated_phrase_sources=(
  McBopomofo
  agriculture-food
  ai-data-science
  anime
  biotech-pharma
  business
  chinese
  civil-engineering
  education
  electronics
  energy-environment
  finance
  general
  government
  history
  industrial-engineering
  law
  manufacturing
  materials-chemistry
  media-design
  medicine
  network-security
  people-contemporary
  people-history
  people-oldnews
  psychology-society
  science
  semiconductor
  software
  transport-logistics
)

associated_phrase_source_enabled() {
  local requested_source=$1 enabled_source
  local -a enabled_sources=()
  IFS=',' read -r -a enabled_sources <<<"$associated_phrase_collections"
  for enabled_source in "${enabled_sources[@]}"; do
    if [[ "$enabled_source" == "$requested_source" ]]; then
      return 0
    fi
  done
  return 1
}

write_keykey_config() {
  {
    printf 'BopomofoLayout=%s\nTraditionalToSimplified=%s\n' \
      "$bopomofo_layout" "$traditional_to_simplified"
    printf 'AssociatedPhraseCollections=%s\n\n' \
      "$associated_phrase_collections"
    printf '[AssociatedPhrases]\n'
    for source in "${associated_phrase_sources[@]}"; do
      enabled=False
      if associated_phrase_source_enabled "$source"; then
        enabled=True
      fi
      printf '%s=%s\n' "$source" "$enabled"
    done
  } >"$XDG_CONFIG_HOME/fcitx5/conf/chichi77-keykey.conf"
}

write_legacy_keykey_config() {
  printf 'BopomofoLayout=%s\nTraditionalToSimplified=%s\nAssociatedPhraseCollections=%s\n' \
    "$bopomofo_layout" "$traditional_to_simplified" \
    "$associated_phrase_collections" \
    >"$XDG_CONFIG_HOME/fcitx5/conf/chichi77-keykey.conf"
}

reload_keykey_config() {
  gdbus call --session --dest org.fcitx.Fcitx5 \
    --object-path /controller \
    --method org.fcitx.Fcitx.Controller1.ReloadAddonConfig \
    chichi77-keykey >/dev/null
}

set_bopomofo_layout() {
  bopomofo_layout=$1
  write_keykey_config
  reload_keykey_config
}

set_traditional_to_simplified() {
  traditional_to_simplified=$1
  write_keykey_config
  reload_keykey_config
}

set_associated_phrase_collections() {
  associated_phrase_collections=$1
  write_keykey_config
  reload_keykey_config
}

associated_phrase_config_variant() {
  local source enabled entries=
  for source in "${associated_phrase_sources[@]}"; do
    enabled=False
    if associated_phrase_source_enabled "$source"; then
      enabled=True
    fi
    if [[ -n "$entries" ]]; then
      entries+=', '
    fi
    entries+="'$source': <'$enabled'>"
  done
  printf "<{'BopomofoLayout': <'%s'>, 'TraditionalToSimplified': <'%s'>, 'AssociatedPhrases': <{%s}>}>" \
    "$bopomofo_layout" "$traditional_to_simplified" "$entries"
}

set_keykey_config_via_dbus() {
  local result_file=$1 config_variant
  config_variant=$(associated_phrase_config_variant)
  gdbus call --session --dest org.fcitx.Fcitx5 \
    --object-path /controller \
    --method org.fcitx.Fcitx.Controller1.SetConfig \
    fcitx://config/inputmethod/chichi77-keykey-bopomofo \
    "$config_variant" >"$result_file"
}

get_keykey_config_via_dbus() {
  local result_file=$1
  gdbus call --session --dest org.fcitx.Fcitx5 \
    --object-path /controller \
    --method org.fcitx.Fcitx.Controller1.GetConfig \
    fcitx://config/inputmethod/chichi77-keykey-bopomofo \
    >"$result_file"
}

verify_bopomofo_config_schema() {
  gdbus call --session --dest org.fcitx.Fcitx5 \
    --object-path /controller \
    --method org.fcitx.Fcitx.Controller1.GetConfig \
    fcitx://config/inputmethod/chichi77-keykey-bopomofo \
    >"$KEYKEY_E2E_ARTIFACT_DIR/fcitx-config-schema.txt"
  grep -Fq BopomofoLayout "$KEYKEY_E2E_ARTIFACT_DIR/fcitx-config-schema.txt"
  grep -Fq TraditionalToSimplified \
    "$KEYKEY_E2E_ARTIFACT_DIR/fcitx-config-schema.txt"
  grep -Fq AssociatedPhrases \
    "$KEYKEY_E2E_ARTIFACT_DIR/fcitx-config-schema.txt"
  for source in "${associated_phrase_sources[@]}"; do
    grep -Fq "$source" \
      "$KEYKEY_E2E_ARTIFACT_DIR/fcitx-config-schema.txt"
  done
  for layout_name in Standard ETen ETen26 Hsu HanyuPinyin; do
    grep -Fq "$layout_name" \
      "$KEYKEY_E2E_ARTIFACT_DIR/fcitx-config-schema.txt"
  done
}

run_case() {
  case_id=$1
  engine_name=$2
  expected_commit=$3
  expected_literal=$4
  required_preedits=$5
  shift 5

  case_dir="$KEYKEY_E2E_ARTIFACT_DIR/$case_id"
  mkdir -p "$case_dir"
  export KEYKEY_E2E_CASE_DIR="$case_dir"
  export KEYKEY_E2E_EXPECTED_COMMIT="$expected_commit"
  export KEYKEY_E2E_EXPECTED_LITERAL="$expected_literal"
  export KEYKEY_E2E_REQUIRED_PREEDITS="$required_preedits"

  "$KEYKEY_E2E_HOST" >"$case_dir/host.stdout.log" \
    2>"$case_dir/host.stderr.log" &
  host_pid=$!

  window_id=
  window_focused=false
  for _ in {1..100}; do
    window_id=$(xdotool search --onlyvisible \
      --name '^chichi77-keykey-gtk3-e2e$' 2>/dev/null | head -n 1 || true)
    if [[ -n "$window_id" ]] && \
        xdotool windowfocus --sync "$window_id" 2>/dev/null; then
      window_focused=true
      break
    fi
    if ! kill -0 "$host_pid" 2>/dev/null; then
      wait "$host_pid" || true
      host_pid=
      echo "GTK 3 E2E host exited before its window was ready for $case_id." >&2
      exit 1
    fi
    sleep 0.1
  done
  if [[ "$window_focused" != true ]]; then
    echo "GTK 3 E2E host window could not be focused for $case_id." >&2
    exit 1
  fi

  fcitx5-remote -o
  engine_ready=false
  for _ in {1..100}; do
    fcitx5-remote -s "$engine_name" || true
    if [[ "$(fcitx5-remote -n)" == "$engine_name" ]]; then
      engine_ready=true
      break
    fi
    sleep 0.1
  done
  if [[ "$engine_ready" != true ]]; then
    echo "The $engine_name Fcitx engine is not active." >&2
    exit 1
  fi

  xdotool key --delay "$key_delay_ms" "$@"
  positive_ready=false
  for _ in {1..100}; do
    if [[ -f "$case_dir/positive-ready" ]]; then
      positive_ready=true
      break
    fi
    sleep 0.1
  done
  if [[ "$positive_ready" != true ]]; then
    echo "$case_id did not commit $expected_commit with the required preedit." >&2
    exit 1
  fi
  if ! grep -Fq 'chichi77-keykey.so' "/proc/$fcitx_pid/maps"; then
    echo "The running Fcitx process did not load the staged KeyKey addon." >&2
    exit 1
  fi

  fcitx5-remote -s keyboard-us
  keyboard_ready=false
  for _ in {1..50}; do
    if [[ "$(fcitx5-remote -n)" == "keyboard-us" ]]; then
      keyboard_ready=true
      break
    fi
    sleep 0.1
  done
  if [[ "$keyboard_ready" != true ]]; then
    echo "The negative-control keyboard engine is not active." >&2
    exit 1
  fi
  xdotool key --delay "$key_delay_ms" ctrl+a BackSpace
  xdotool key --delay "$key_delay_ms" "$@"

  wait "$host_pid"
  host_pid=
  grep -Fxq "$expected_literal" "$case_dir/final.txt"
  printf '%s\n' \
    "{\"test\":\"$case_id\",\"engine\":\"$engine_name\",\"expected\":\"$expected_commit\",\"negative\":\"$expected_literal\",\"status\":\"passed\"}" \
    >"$case_dir/result.json"
}

if case_selected T07-X11-FCITX5-CONFIG-UI-PERSISTENCE; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections McBopomofo
  ui_case_dir="$KEYKEY_E2E_ARTIFACT_DIR/"
  ui_case_dir+=T07-X11-FCITX5-CONFIG-UI-PERSISTENCE
  mkdir -p "$ui_case_dir"
  gdbus call --session --dest org.fcitx.Fcitx5 \
    --object-path /controller \
    --method org.fcitx.Fcitx.Controller1.ConfigureIM \
    chichi77-keykey-bopomofo >"$ui_case_dir/configure-im-result.txt"
  python3 tests/fcitx5_config_ui_driver.py "$ui_case_dir"
  cp "$XDG_CONFIG_HOME/fcitx5/conf/chichi77-keykey.conf" \
    "$ui_case_dir/saved-config.ini"
  grep -Fxq 'AssociatedPhraseCollections=agriculture-food' \
    "$ui_case_dir/saved-config.ini"
  grep -Fxq 'McBopomofo=False' "$ui_case_dir/saved-config.ini"
  grep -Fxq 'agriculture-food=True' "$ui_case_dir/saved-config.ini"
  restart_fcitx
  get_keykey_config_via_dbus "$ui_case_dir/config-after-restart.txt"
  grep -Fq "'McBopomofo': <'False'>" \
    "$ui_case_dir/config-after-restart.txt"
  grep -Fq "'agriculture-food': <'True'>" \
    "$ui_case_dir/config-after-restart.txt"
  run_case T07-X11-FCITX5-CONFIG-UI-PERSISTENCE \
    chichi77-keykey-bopomofo \
    作物育種 'yji4 2!' 'ㄗ,ㄗㄨ,ㄗㄨㄛ,ㄗㄨㄛˋ' \
    y j i 4 space 2 shift+1
  set_associated_phrase_collections ''
fi
if case_selected T01-X11-GTK3-BOPOMOFO-STANDARD; then
  set_bopomofo_layout Standard
  run_case T01-X11-GTK3-BOPOMOFO-STANDARD chichi77-keykey-bopomofo \
    中 '5j/ 1' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space 1
  verify_bopomofo_config_schema
fi
if case_selected T02-X11-GTK3-BOPOMOFO-STANDARD; then
  set_bopomofo_layout Standard
  run_case T02-X11-GTK3-BOPOMOFO-STANDARD chichi77-keykey-bopomofo \
    麻馬罵嘛 'a86 1a83 1a84 1a87 1' \
    'ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    a 8 6 space 1 a 8 3 space 1 a 8 4 space 1 a 8 7 space 1
fi
if case_selected T02-X11-GTK3-BOPOMOFO-ETEN; then
  set_bopomofo_layout ETen
  run_case T02-X11-GTK3-BOPOMOFO-ETEN chichi77-keykey-bopomofo \
    麻馬罵嘛 'ma2 1ma3 1ma4 1ma1 1' \
    'ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m a 2 space 1 m a 3 space 1 m a 4 space 1 m a 1 space 1
fi
if case_selected T02-X11-GTK3-BOPOMOFO-ETEN26; then
  set_bopomofo_layout ETen26
  run_case T02-X11-GTK3-BOPOMOFO-ETEN26 chichi77-keykey-bopomofo \
    麻馬罵嘛 'maf 1maj 1mak 1mad 1' \
    'ㄢ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m a f space 1 m a j space 1 m a k space 1 m a d space 1
fi
if case_selected T02-X11-GTK3-BOPOMOFO-HSU; then
  set_bopomofo_layout Hsu
  run_case T02-X11-GTK3-BOPOMOFO-HSU chichi77-keykey-bopomofo \
    麻馬罵嘛 'myd 1myf 1myj 1mys 1' \
    'ㄢ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m y d space 1 m y f space 1 m y j space 1 m y s space 1
fi
if case_selected T02-X11-GTK3-BOPOMOFO-HANYU-PINYIN; then
  set_bopomofo_layout HanyuPinyin
  run_case T02-X11-GTK3-BOPOMOFO-HANYU-PINYIN chichi77-keykey-bopomofo \
    麻馬罵嘛 'ma2 1ma3 1ma4 1ma5 1' \
    'z,zh,m,ma,ma2,ma3,ma4,ma5' \
    z h BackSpace BackSpace \
    m a 2 space 1 m a 3 space 1 m a 4 space 1 m a 5 space 1
fi
if case_selected T04-X11-GTK3-CANGJIE; then
  run_case T04-X11-GTK3-CANGJIE chichi77-keykey-cangjie \
    日 'a 1' 日 a space 1
fi
if case_selected T04-X11-GTK3-CANGJIE-ENDKEY-ERROR; then
  run_case T04-X11-GTK3-CANGJIE-ENDKEY-ERROR \
    chichi77-keykey-cangjie \
    '，用' ',zzzzz bq ' \
    '重,重重,重重重,重重重重,重重重重重,月,月手' \
    comma z z z z z space b q space
fi
if case_selected T04-X11-GTK3-CANGJIE-WILDCARD; then
  run_case T04-X11-GTK3-CANGJIE-WILDCARD \
    chichi77-keykey-cangjie \
    '昌日' 'a? 1a* 1' \
    '日,日？,日,日＊' \
    a question space 1 a asterisk space 1
fi
if case_selected T05-X11-GTK3-SIMPLEX; then
  run_case T05-X11-GTK3-SIMPLEX chichi77-keykey-simplex \
    曰 'a 2' 日 a space 2
fi
if case_selected T05-X11-GTK3-SIMPLEX-FULL-CODE; then
  run_case T05-X11-GTK3-SIMPLEX-FULL-CODE \
    chichi77-keykey-simplex \
    '明銖䍤、' 'abcd1wx,2' \
    '日,日月,金,金木,田,，' \
    a b c d 1 w x comma 2
fi
if case_selected T06-X11-GTK3-CANDIDATE-NAVIGATION; then
  set_bopomofo_layout Standard
  run_case T06-X11-GTK3-CANDIDATE-NAVIGATION chichi77-keykey-bopomofo \
    妐 '5j/ ' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space Page_Down Down Return
fi
if case_selected T07-X11-GTK3-ASSOCIATED-PHRASE; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections McBopomofo
  run_case T07-X11-GTK3-ASSOCIATED-PHRASE chichi77-keykey-bopomofo \
    今天 'rup 1!' 'ㄐ,ㄐㄧ,ㄐㄧㄣ' r u p space 1 shift+1
fi
if case_selected T07-X11-GTK3-ASSOCIATED-PHRASE-CATEGORY; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections history
  run_case T07-X11-GTK3-ASSOCIATED-PHRASE-CATEGORY \
    chichi77-keykey-bopomofo \
    臺灣史 'w96 2!' 'ㄊ,ㄊㄞ,ㄊㄞˊ' w 9 6 space 2 shift+1
fi
if case_selected T07-X11-GTK3-ASSOCIATED-PHRASE-DISABLED; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_case T07-X11-GTK3-ASSOCIATED-PHRASE-DISABLED \
    chichi77-keykey-bopomofo \
    '臺!' 'w96 2!' 'ㄊ,ㄊㄞ,ㄊㄞˊ' w 9 6 space 2 shift+1
  set_associated_phrase_collections ''
fi
if case_selected T07-X11-GTK3-ASSOCIATED-PHRASE-LEGACY-CONFIG; then
  set_bopomofo_layout Standard
  associated_phrase_collections=government
  write_legacy_keykey_config
  reload_keykey_config
  run_case T07-X11-GTK3-ASSOCIATED-PHRASE-LEGACY-CONFIG \
    chichi77-keykey-bopomofo \
    中程計畫 '5j/ 1!' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space 1 shift+1
  set_associated_phrase_collections ''
fi
if case_selected T07-X11-GTK3-ASSOCIATED-PHRASE-DBUS-PERSISTENCE; then
  set_bopomofo_layout Standard
  associated_phrase_collections=government
  persistence_case_dir="$KEYKEY_E2E_ARTIFACT_DIR/"
  persistence_case_dir+=T07-X11-GTK3-ASSOCIATED-PHRASE-DBUS-PERSISTENCE
  mkdir -p "$persistence_case_dir"
  set_keykey_config_via_dbus "$persistence_case_dir/set-config-result.txt"
  cp "$XDG_CONFIG_HOME/fcitx5/conf/chichi77-keykey.conf" \
    "$persistence_case_dir/saved-config.ini"
  grep -Fxq 'AssociatedPhraseCollections=government' \
    "$persistence_case_dir/saved-config.ini"
  grep -Fxq 'McBopomofo=False' "$persistence_case_dir/saved-config.ini"
  grep -Fxq 'government=True' "$persistence_case_dir/saved-config.ini"
  restart_fcitx
  get_keykey_config_via_dbus "$persistence_case_dir/config-after-restart.txt"
  grep -Fq "'McBopomofo': <'False'>" \
    "$persistence_case_dir/config-after-restart.txt"
  grep -Fq "'government': <'True'>" \
    "$persistence_case_dir/config-after-restart.txt"
  run_case T07-X11-GTK3-ASSOCIATED-PHRASE-DBUS-PERSISTENCE \
    chichi77-keykey-bopomofo \
    中程計畫 '5j/ 1!' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space 1 shift+1
  set_associated_phrase_collections ''
fi
if case_selected T08-X11-GTK3-FULL-WIDTH; then
  set_bopomofo_layout Standard
  run_case T08-X11-GTK3-FULL-WIDTH chichi77-keykey-bopomofo \
    'Ａ！～　' ' A!~ ' '' shift+space shift+a shift+1 shift+grave space
fi
if case_selected T08-X11-GTK3-TRADITIONAL-TO-SIMPLIFIED; then
  set_bopomofo_layout Standard
  set_traditional_to_simplified True
  run_case T08-X11-GTK3-TRADITIONAL-TO-SIMPLIFIED chichi77-keykey-bopomofo \
    台湾 'w96 2j0 1' 'ㄊ,ㄊㄞ,ㄊㄞˊ,ㄨ,ㄨㄢ' \
    w 9 6 space 2 j 0 space 1
  set_traditional_to_simplified False
fi
if case_selected T12-X11-GTK3-SYMBOL-LIST; then
  set_bopomofo_layout Standard
  run_case T12-X11-GTK3-SYMBOL-LIST chichi77-keykey-bopomofo \
    ， '1' ， ctrl+0 1
fi
test_status=passed

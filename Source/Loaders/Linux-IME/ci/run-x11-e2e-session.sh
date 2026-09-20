#!/usr/bin/env bash
set -euo pipefail

test -n "${KEYKEY_E2E_HOST:-}"
test -n "${KEYKEY_E2E_GTK4_HOST:-}"
test -n "${KEYKEY_E2E_QT6_HOST:-}"
test -n "${KEYKEY_E2E_ARTIFACT_DIR:-}"
test -n "${KEYKEY_E2E_RUNTIME_ROOT:-}"

session_mode=${KEYKEY_E2E_SESSION_MODE:-managed}
case "$session_mode" in
  managed|existing-gnome) ;;
  *)
    echo "KEYKEY_E2E_SESSION_MODE must be managed or existing-gnome." >&2
    exit 2
    ;;
esac

known_cases=(
  T01-X11-GTK3-BOPOMOFO-STANDARD
  T01-X11-GTK4-BOPOMOFO-STANDARD
  T01-X11-QT6-BOPOMOFO-STANDARD
  T01-X11-GTK3-BOPOMOFO-BIG5-FILTER
  T01-X11-GTK3-BOPOMOFO-CONTINUOUS
  T01-X11-GTK3-BOPOMOFO-INVALID-INPUT
  T02-X11-GTK3-BOPOMOFO-STANDARD
  T02-X11-GTK3-BOPOMOFO-ETEN
  T02-X11-GTK3-BOPOMOFO-ETEN26
  T02-X11-GTK3-BOPOMOFO-HSU
  T02-X11-GTK3-BOPOMOFO-HANYU-PINYIN
  T02-X11-GTK4-BOPOMOFO-STANDARD
  T02-X11-GTK4-BOPOMOFO-ETEN
  T02-X11-GTK4-BOPOMOFO-ETEN26
  T02-X11-GTK4-BOPOMOFO-HSU
  T02-X11-GTK4-BOPOMOFO-HANYU-PINYIN
  T02-X11-QT6-BOPOMOFO-STANDARD
  T02-X11-QT6-BOPOMOFO-ETEN
  T02-X11-QT6-BOPOMOFO-ETEN26
  T02-X11-QT6-BOPOMOFO-HSU
  T02-X11-QT6-BOPOMOFO-HANYU-PINYIN
  T03-X11-GTK3-BOPOMOFO-EDIT-CANCEL
  T03-X11-GTK4-BOPOMOFO-EDIT-CANCEL
  T03-X11-QT6-BOPOMOFO-EDIT-CANCEL
  T04-X11-GTK3-CANGJIE
  T04-X11-GTK3-CANGJIE-ENDKEY-ERROR
  T04-X11-GTK3-CANGJIE-WILDCARD
  T05-X11-GTK3-SIMPLEX
  T05-X11-GTK3-SIMPLEX-FULL-CODE
  T06-X11-GTK3-CANDIDATE-NAVIGATION
  T06-X11-GTK3-CANDIDATE-MOUSE
  T06-X11-GTK4-CANDIDATE-NAVIGATION
  T06-X11-GTK4-CANDIDATE-MOUSE
  T06-X11-GTK4-CANDIDATE-HORIZONTAL
  T06-X11-QT6-CANDIDATE-NAVIGATION
  T06-X11-QT6-CANDIDATE-MOUSE
  T06-X11-QT6-CANDIDATE-HORIZONTAL
  T07-X11-GTK3-ASSOCIATED-PHRASE
  T07-X11-GTK3-ASSOCIATED-PHRASE-CATEGORY
  T07-X11-GTK3-ASSOCIATED-PHRASE-DISABLED
  T07-X11-GTK3-ASSOCIATED-PHRASE-LEGACY-CONFIG
  T07-X11-GTK3-ASSOCIATED-PHRASE-DBUS-PERSISTENCE
  T07-X11-GTK4-ASSOCIATED-PHRASE
  T07-X11-GTK4-ASSOCIATED-PHRASE-CATEGORY
  T07-X11-GTK4-ASSOCIATED-PHRASE-DISABLED
  T07-X11-GTK4-ASSOCIATED-PHRASE-LEGACY-CONFIG
  T07-X11-GTK4-ASSOCIATED-PHRASE-DBUS-PERSISTENCE
  T07-X11-QT6-ASSOCIATED-PHRASE
  T07-X11-QT6-ASSOCIATED-PHRASE-CATEGORY
  T07-X11-QT6-ASSOCIATED-PHRASE-DISABLED
  T07-X11-QT6-ASSOCIATED-PHRASE-LEGACY-CONFIG
  T07-X11-QT6-ASSOCIATED-PHRASE-DBUS-PERSISTENCE
  T07-X11-FCITX5-CONFIG-UI-PERSISTENCE
  T08-X11-GTK3-CHINESE-ENGLISH-MODE
  T08-X11-GTK3-CONTROL-BACKSLASH-DISABLED
  T08-X11-GTK3-FULL-WIDTH
  T08-X11-GTK3-TRADITIONAL-TO-SIMPLIFIED
  T08-X11-GTK4-CHINESE-ENGLISH-MODE
  T08-X11-GTK4-CONTROL-BACKSLASH-DISABLED
  T08-X11-GTK4-FULL-WIDTH
  T08-X11-GTK4-TRADITIONAL-TO-SIMPLIFIED
  T08-X11-QT6-CHINESE-ENGLISH-MODE
  T08-X11-QT6-CONTROL-BACKSLASH-DISABLED
  T08-X11-QT6-FULL-WIDTH
  T08-X11-QT6-TRADITIONAL-TO-SIMPLIFIED
  T09-X11-GTK3-MODIFIER-PASSTHROUGH
  T09-X11-GTK4-MODIFIER-PASSTHROUGH
  T09-X11-QT6-MODIFIER-PASSTHROUGH
  T10-X11-GTK3-INPUT-CONTEXT-ISOLATION
  T10-X11-GTK3-MULTI-APP-ISOLATION
  T10-X11-GTK4-INPUT-CONTEXT-ISOLATION
  T10-X11-GTK4-MULTI-APP-ISOLATION
  T10-X11-QT6-INPUT-CONTEXT-ISOLATION
  T10-X11-QT6-MULTI-APP-ISOLATION
  T11-X11-GTK3-EDITING-SENSITIVE-READONLY
  T11-X11-GTK4-EDITING-SENSITIVE-READONLY
  T11-X11-QT6-EDITING-SENSITIVE-READONLY
  T12-X11-GTK3-SYMBOL-LIST
  T12-X11-GTK3-SYMBOL-LIST-MOUSE
  T12-X11-GTK4-SYMBOL-LIST
  T12-X11-GTK4-SYMBOL-LIST-MOUSE
  T12-X11-QT6-SYMBOL-LIST
  T12-X11-QT6-SYMBOL-LIST-MOUSE
)
requested_cases=${KEYKEY_E2E_CASES:-all}
config_ui=${KEYKEY_E2E_CONFIG_UI:-ON}
key_delay_ms=${KEYKEY_E2E_KEY_DELAY_MS:-80}
gtk3_e2e_host=$KEYKEY_E2E_HOST
e2e_host_window_title=chichi77-keykey-gtk3-e2e
e2e_host_label='GTK 3'
case "$config_ui" in ON|OFF) ;; *)
  echo "KEYKEY_E2E_CONFIG_UI must be ON or OFF." >&2
  exit 2
esac
if [[ ! "$key_delay_ms" =~ ^[0-9]+$ ]]; then
  echo "KEYKEY_E2E_KEY_DELAY_MS must be a non-negative integer." >&2
  exit 2
fi

requested_case_list=()
if [[ "$requested_cases" == all || "$requested_cases" == desktop-safe ]]; then
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
  if [[ "$requested_cases" == desktop-safe ]]; then
    case "$known_case" in
      T07-X11-*-ASSOCIATED-PHRASE-DBUS-PERSISTENCE|\
      T07-X11-FCITX5-CONFIG-UI-PERSISTENCE|\
      T10-X11-*-INPUT-CONTEXT-ISOLATION)
        continue
        ;;
    esac
  fi
  for requested_case in "${requested_case_list[@]}"; do
    if [[ "$requested_case" == "$known_case" ]]; then
      selected_cases+=("$known_case")
      break
    fi
  done
done

if [[ "$session_mode" == existing-gnome ]]; then
  for selected_case in "${selected_cases[@]}"; do
    case "$selected_case" in
      T07-X11-*-ASSOCIATED-PHRASE-DBUS-PERSISTENCE|\
      T07-X11-FCITX5-CONFIG-UI-PERSISTENCE|\
      T10-X11-*-INPUT-CONTEXT-ISOLATION)
        echo "$selected_case restarts Fcitx and cannot run inside an existing desktop session." >&2
        echo "Use KEYKEY_E2E_CASES=desktop-safe or the managed Xvfb runner." >&2
        exit 2
        ;;
    esac
  done
fi

selected_cases_json=
uses_gtk3=false
uses_gtk4=false
uses_qt6=false
uses_config_ui=false
for selected_case in "${selected_cases[@]}"; do
  if [[ -n "$selected_cases_json" ]]; then
    selected_cases_json+=,
  fi
  selected_cases_json+="\"$selected_case\""
  case "$selected_case" in
    *-GTK3-*) uses_gtk3=true ;;
    *-GTK4-*) uses_gtk4=true ;;
    *-QT6-*) uses_qt6=true ;;
    T07-X11-FCITX5-CONFIG-UI-PERSISTENCE)
      uses_gtk3=true
      uses_config_ui=true
      ;;
  esac
done
e2e_apps=
if [[ "$uses_gtk3" == true ]]; then e2e_apps=gtk3-entry; fi
if [[ "$uses_gtk4" == true ]]; then
  if [[ -n "$e2e_apps" ]]; then e2e_apps+=+; fi
  e2e_apps+=gtk4-text
fi
if [[ "$uses_qt6" == true ]]; then
  if [[ -n "$e2e_apps" ]]; then e2e_apps+=+; fi
  e2e_apps+=qt6-line-edit
fi
if [[ "$uses_config_ui" == true ]]; then
  if [[ -n "$e2e_apps" ]]; then e2e_apps+=+; fi
  e2e_apps+=fcitx5-config-qt
fi

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
if [[ "$session_mode" == managed ]]; then
  export DISPLAY=:99
else
  test -n "${DISPLAY:-}"
  test -n "${DBUS_SESSION_BUS_ADDRESS:-}"
  test -n "${XDG_CONFIG_HOME:-}"
  test -n "${XDG_DATA_HOME:-}"
  test -n "${XDG_RUNTIME_DIR:-}"
fi
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
if case_selected T07-X11-FCITX5-CONFIG-UI-PERSISTENCE; then
  export QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
fi
if [[ "$session_mode" == managed ]]; then
  export XDG_CONFIG_HOME="$runtime_root/config"
  export XDG_DATA_HOME="$runtime_root/data"
  export XDG_RUNTIME_DIR="$runtime_root/runtime"
  mkdir -p "$XDG_CONFIG_HOME/fcitx5/conf" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
fi
if case_selected T07-X11-FCITX5-CONFIG-UI-PERSISTENCE; then
  dbus-update-activation-environment \
    DISPLAY XDG_CONFIG_HOME XDG_DATA_HOME XDG_RUNTIME_DIR \
    QT_LINUX_ACCESSIBILITY_ALWAYS_ON
else
  dbus-update-activation-environment \
    DISPLAY XDG_CONFIG_HOME XDG_DATA_HOME XDG_RUNTIME_DIR
fi
if [[ "$session_mode" == managed ]]; then
  install -m 0644 tests/fixtures/fcitx5-profile "$XDG_CONFIG_HOME/fcitx5/profile"
fi

xvfb_pid=
fcitx_pid=
owns_fcitx=false
host_pid=
secondary_host_pid=
session_label=x11-xvfb
desktop_label=none
original_engine=
keykey_config_path="$XDG_CONFIG_HOME/fcitx5/conf/chichi77-keykey.conf"
keykey_config_backup="$KEYKEY_E2E_ARTIFACT_DIR/.original-keykey-config"
keykey_config_existed=false
keykey_config_saved=false
test_status=failed
cleanup() {
  exit_code=$?
  if [[ "$test_status" == passed ]]; then
    failure_count=0
    failure_element=
  else
    failure_count=1
    failure_element='<failure message="Installed Fcitx 5 toolkit typing flow failed"/>'
  fi
  printf '%s\n' \
    "{\"tests\":[$selected_cases_json],\"distro\":\"ubuntu-24.04\",\"arch\":\"$(uname -m)\",\"desktop\":\"$desktop_label\",\"session\":\"$session_label\",\"framework\":\"fcitx5\",\"app\":\"$e2e_apps\",\"status\":\"$test_status\"}" \
    >"$KEYKEY_E2E_ARTIFACT_DIR/result.json"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    "<testsuite name=\"chichi77-keykey-linux-x11-e2e\" tests=\"1\" failures=\"$failure_count\">" \
    "  <testcase classname=\"fcitx5.toolkit.x11\" name=\"installed addon layouts, input methods, candidate navigation, output filters, symbols, and native settings\">$failure_element</testcase>" \
    '</testsuite>' \
    >"$KEYKEY_E2E_ARTIFACT_DIR/junit.xml"
  if [[ -n "$host_pid" ]]; then kill "$host_pid" 2>/dev/null || true; fi
  if [[ -n "$secondary_host_pid" ]]; then
    kill "$secondary_host_pid" 2>/dev/null || true
  fi
  if [[ "$owns_fcitx" == true && -n "$fcitx_pid" ]]; then
    kill "$fcitx_pid" 2>/dev/null || true
  fi
  if [[ -n "$xvfb_pid" ]]; then kill "$xvfb_pid" 2>/dev/null || true; fi
  if [[ -n "$host_pid" ]]; then wait "$host_pid" 2>/dev/null || true; fi
  if [[ -n "$secondary_host_pid" ]]; then
    wait "$secondary_host_pid" 2>/dev/null || true
  fi
  if [[ "$owns_fcitx" == true && -n "$fcitx_pid" ]]; then
    wait "$fcitx_pid" 2>/dev/null || true
  fi
  if [[ -n "$xvfb_pid" ]]; then wait "$xvfb_pid" 2>/dev/null || true; fi
  if [[ "$session_mode" == existing-gnome && "$keykey_config_saved" == true ]]; then
    if [[ "$keykey_config_existed" == true && -f "$keykey_config_backup" ]]; then
      cp "$keykey_config_backup" "$keykey_config_path"
    else
      cmake -E rm -f "$keykey_config_path"
    fi
    cmake -E rm -f "$keykey_config_backup"
    gdbus call --session --dest org.fcitx.Fcitx5 \
      --object-path /controller \
      --method org.fcitx.Fcitx.Controller1.ReloadAddonConfig \
      chichi77-keykey >/dev/null 2>&1 || true
    if [[ -n "$original_engine" ]]; then
      fcitx5-remote -s "$original_engine" >/dev/null 2>&1 || true
    fi
  fi
  trap - EXIT
  exit "$exit_code"
}
trap cleanup EXIT

if [[ "$session_mode" == managed ]]; then
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
else
  if [[ "${XDG_SESSION_TYPE:-}" != x11 || "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]]; then
    echo "The existing-session runner requires a GNOME X11 session." >&2
    exit 1
  fi
  if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    echo "The existing GNOME X11 display is not reachable." >&2
    exit 1
  fi
  if ! xdotool getactivewindow >/dev/null 2>&1; then
    echo "GNOME has no active window; restart the isolated desktop before running the gate." >&2
    exit 1
  fi
  wm_window=$(xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null |
    sed -n 's/.*window id # \(0x[0-9a-fA-F]*\).*/\1/p')
  if [[ -z "$wm_window" ]] ||
      ! xprop -id "$wm_window" _NET_WM_NAME 2>/dev/null | grep -Fq 'GNOME Shell'; then
    echo "The existing X11 display is not managed by GNOME Shell." >&2
    exit 1
  fi
  session_label=gnome-x11
  desktop_label=GNOME
fi

start_fcitx() {
  local fcitx_ready=false addon_ready=false
  fcitx5 >>"$KEYKEY_E2E_ARTIFACT_DIR/fcitx5.log" 2>&1 &
  fcitx_pid=$!
  owns_fcitx=true
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
  if [[ "$owns_fcitx" != true ]]; then
    echo "Fcitx restart is not permitted inside an existing desktop session." >&2
    exit 1
  fi
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
if [[ "$session_mode" == managed ]]; then
  start_fcitx
else
  fcitx_pid=$(gdbus call --session --dest org.freedesktop.DBus \
    --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.GetConnectionUnixProcessID \
    org.fcitx.Fcitx5 2>/dev/null |
    sed -n 's/.*uint32 \([0-9][0-9]*\).*/\1/p')
  if [[ -z "$fcitx_pid" || ! -r "/proc/$fcitx_pid/maps" ]]; then
    echo "The existing desktop Fcitx process could not be identified." >&2
    exit 1
  fi
  if ! grep -Fq 'chichi77-keykey.so' "/proc/$fcitx_pid/maps"; then
    echo "The existing desktop Fcitx process did not load the KeyKey addon." >&2
    exit 1
  fi
  if ! grep -Fq 'classicui.so' "/proc/$fcitx_pid/maps"; then
    echo "The existing desktop Fcitx process did not load the Classic UI panel." >&2
    exit 1
  fi
  mkdir -p "$(dirname "$keykey_config_path")"
  if [[ -f "$keykey_config_path" ]]; then
    cp "$keykey_config_path" "$keykey_config_backup"
    keykey_config_existed=true
  fi
  keykey_config_saved=true
  original_engine=$(fcitx5-remote -n 2>/dev/null || true)
  addon_path=$(awk '$NF ~ /\/chichi77-keykey\.so$/ {print $NF; exit}' \
    "/proc/$fcitx_pid/maps")
  panel_path=$(awk '$NF ~ /\/(lib)?classicui\.so$/ {print $NF; exit}' \
    "/proc/$fcitx_pid/maps")
  addon_sha256=$(sha256sum "$addon_path" | awk '{print $1}')
  if ! package_identity=$(dpkg-query -W \
      -f='${Package}=${Version}' fcitx5-chichi77-keykey 2>/dev/null); then
    echo "The installed KeyKey Fcitx package could not be identified." >&2
    exit 1
  fi
  if ! dpkg-query -S "$addon_path" 2>/dev/null |
      grep -Fq 'fcitx5-chichi77-keykey:'; then
    echo "The loaded KeyKey addon is not owned by the installed package." >&2
    exit 1
  fi
  {
    printf 'desktop=GNOME\nsession=x11\ndisplay=%s\n' "$DISPLAY"
    printf 'window-manager=GNOME Shell\nframework=fcitx5\n'
    printf 'fcitx-pid=%s\naddon=%s\npanel=%s\n' \
      "$fcitx_pid" "$addon_path" "$panel_path"
    printf 'addon-sha256=%s\npackage=%s\n' \
      "$addon_sha256" "$package_identity"
    printf 'gtk-backend=%s\nqt-platform=xcb\n' "${GDK_BACKEND:-x11}"
    printf 'gtk3-host-sha256=%s\n' \
      "$(sha256sum "$KEYKEY_E2E_HOST" | awk '{print $1}')"
    printf 'gtk4-host-sha256=%s\n' \
      "$(sha256sum "$KEYKEY_E2E_GTK4_HOST" | awk '{print $1}')"
    printf 'qt6-host-sha256=%s\n' \
      "$(sha256sum "$KEYKEY_E2E_QT6_HOST" | awk '{print $1}')"
    fcitx5 --version 2>&1 | head -n 1
    gnome-shell --version 2>&1 | head -n 1
  } >"$KEYKEY_E2E_ARTIFACT_DIR/environment.txt"
fi

if [[ -n "${KEYKEY_E2E_EXPECTED_ADDON_PATH:-}" ]]; then
  if ! grep -Fq -- "$KEYKEY_E2E_EXPECTED_ADDON_PATH" "/proc/$fcitx_pid/maps"; then
    echo "Fcitx loaded an addon from a different install prefix." >&2
    exit 1
  fi
  printf '%s\n' "$KEYKEY_E2E_EXPECTED_ADDON_PATH" \
    >"$KEYKEY_E2E_ARTIFACT_DIR/loaded-addon-path.txt"
fi

bopomofo_layout=Standard
candidate_window_style=Vertical
traditional_to_simplified=False
use_all_unicode_characters=True
play_sound_on_typing_error=True
toggle_with_control_backslash=True
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
    printf 'CandidateWindowStyle=%s\n' "$candidate_window_style"
    printf 'UseAllUnicodeCharacters=%s\n' \
      "$use_all_unicode_characters"
    printf 'PlaySoundOnTypingError=%s\n' \
      "$play_sound_on_typing_error"
    printf 'ToggleInputMethodWithControlBackslash=%s\n' \
      "$toggle_with_control_backslash"
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

set_candidate_window_style() {
  candidate_window_style=$1
  write_keykey_config
  reload_keykey_config
}

set_traditional_to_simplified() {
  traditional_to_simplified=$1
  write_keykey_config
  reload_keykey_config
}

set_use_all_unicode_characters() {
  use_all_unicode_characters=$1
  write_keykey_config
  reload_keykey_config
}

set_associated_phrase_collections() {
  associated_phrase_collections=$1
  write_keykey_config
  reload_keykey_config
}

set_toggle_with_control_backslash() {
  toggle_with_control_backslash=$1
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
  printf "<{'BopomofoLayout': <'%s'>, 'CandidateWindowStyle': <'%s'>, 'TraditionalToSimplified': <'%s'>, 'UseAllUnicodeCharacters': <'%s'>, 'PlaySoundOnTypingError': <'%s'>, 'ToggleInputMethodWithControlBackslash': <'%s'>, 'AssociatedPhrases': <{%s}>}>" \
    "$bopomofo_layout" "$candidate_window_style" \
    "$traditional_to_simplified" \
    "$use_all_unicode_characters" "$play_sound_on_typing_error" \
    "$toggle_with_control_backslash" "$entries"
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
  grep -Fq CandidateWindowStyle \
    "$KEYKEY_E2E_ARTIFACT_DIR/fcitx-config-schema.txt"
  grep -Fq TraditionalToSimplified \
    "$KEYKEY_E2E_ARTIFACT_DIR/fcitx-config-schema.txt"
  grep -Fq UseAllUnicodeCharacters \
    "$KEYKEY_E2E_ARTIFACT_DIR/fcitx-config-schema.txt"
  grep -Fq PlaySoundOnTypingError \
    "$KEYKEY_E2E_ARTIFACT_DIR/fcitx-config-schema.txt"
  grep -Fq ToggleInputMethodWithControlBackslash \
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
  for style_name in Vertical Horizontal; do
    grep -Fq "$style_name" \
      "$KEYKEY_E2E_ARTIFACT_DIR/fcitx-config-schema.txt"
  done
}

send_key_sequence() {
  local special_sequence=false key_name center_file='' center_ready=false
  local entry_x='' entry_y='' focus_ready=false
  local selection_start_file='' selection_end_file='' selection_ready=false
  local selection_start_x='' selection_start_y='' selection_end_x=''
  local selection_end_y=''
  local candidate_window_id='' candidate_geometry='' candidate_width=''
  local candidate_height='' candidate_row='' click_x='' click_y=''
  local popup_ready=false
  for key_name in "$@"; do
    case "$key_name" in
    shift-down|shift-up|ctrl-down|ctrl-up|backslash-down|backslash-up|activate-bopomofo|expect-keyboard-us|click-second-entry|drag-first-second-character|click-candidate-[1-9]|wait-500ms|wait-1000ms)
      special_sequence=true
      break
      ;;
    esac
  done
  if [[ "$special_sequence" != true ]]; then
    xdotool key --delay "$key_delay_ms" "$@"
    return
  fi

  for key_name in "$@"; do
    case "$key_name" in
      shift-down) xdotool keydown Shift ;;
      shift-up) xdotool keyup Shift ;;
      ctrl-down) xdotool keydown Control ;;
      ctrl-up) xdotool keyup Control ;;
      backslash-down) xdotool keydown backslash ;;
      backslash-up) xdotool keyup backslash ;;
      activate-bopomofo)
        fcitx5-remote -s chichi77-keykey-bopomofo
        for _ in {1..50}; do
          if [[ "$(fcitx5-remote -n)" == \
              chichi77-keykey-bopomofo ]]; then
            break
          fi
          sleep 0.1
        done
        if [[ "$(fcitx5-remote -n)" != chichi77-keykey-bopomofo ]]; then
          echo "The Bopomofo engine did not activate after a focus change." >&2
          exit 1
        fi
        ;;
      expect-keyboard-us)
        for _ in {1..50}; do
          if [[ "$(fcitx5-remote -n)" == keyboard-us ]]; then
            break
          fi
          sleep 0.1
        done
        if [[ "$(fcitx5-remote -n)" != keyboard-us ]]; then
          echo "The client capability did not disable the custom input method." >&2
          exit 1
        fi
        ;;
      click-second-entry)
        center_file="$KEYKEY_E2E_CASE_DIR/second-center.txt"
        center_ready=false
        for _ in {1..50}; do
          if [[ -s "$center_file" ]]; then
            center_ready=true
            break
          fi
          sleep 0.1
        done
        if [[ "$center_ready" != true ]]; then
          echo "The GTK host did not publish its second-entry geometry." >&2
          exit 1
        fi
        read -r entry_x entry_y <"$center_file"
        xdotool mousemove --window "$window_id" "$entry_x" "$entry_y" click 1
        focus_ready=false
        for _ in {1..50}; do
          if grep -Fq '"type":"second-focus","value":"in"' \
              "$KEYKEY_E2E_CASE_DIR/events.jsonl"; then
            focus_ready=true
            break
          fi
          sleep 0.1
        done
        if [[ "$focus_ready" != true ]]; then
          echo "The pointer click did not focus the GTK host's second entry." >&2
          exit 1
        fi
        ;;
      drag-first-second-character)
        selection_start_file="$KEYKEY_E2E_CASE_DIR/first-selection-start.txt"
        selection_end_file="$KEYKEY_E2E_CASE_DIR/first-selection-end.txt"
        selection_ready=false
        for _ in {1..50}; do
          if [[ -s "$selection_start_file" && -s "$selection_end_file" ]]; then
            selection_ready=true
            break
          fi
          sleep 0.1
        done
        if [[ "$selection_ready" != true ]]; then
          echo "The GTK host did not publish its text-selection geometry." >&2
          exit 1
        fi
        read -r selection_start_x selection_start_y <"$selection_start_file"
        read -r selection_end_x selection_end_y <"$selection_end_file"
        center_file="$KEYKEY_E2E_CASE_DIR/first-center.txt"
        read -r entry_x entry_y <"$center_file"
        xdotool mousemove --window "$window_id" "$entry_x" "$entry_y" click 1
        selection_ready=false
        for _ in {1..50}; do
          if grep -Fxq 'cursor:3' \
              "$KEYKEY_E2E_CASE_DIR/first-selection-state.txt"; then
            selection_ready=true
            break
          fi
          sleep 0.1
        done
        if [[ "$selection_ready" != true ]]; then
          echo "The pointer click did not clear the GTK host's initial selection." >&2
          exit 1
        fi
        xdotool mousemove --window "$window_id" \
          "$selection_start_x" "$selection_start_y" mousedown 1
        sleep 0.1
        xdotool mousemove --sync --window "$window_id" \
          "$selection_end_x" "$selection_end_y" mouseup 1
        selection_ready=false
        for _ in {1..50}; do
          if grep -Fq '"type":"first-selection","value":"1:2"' \
              "$KEYKEY_E2E_CASE_DIR/events.jsonl"; then
            selection_ready=true
            break
          fi
          sleep 0.1
        done
        if [[ "$selection_ready" != true ]]; then
          echo "The pointer drag did not select the GTK host's second character." >&2
          exit 1
        fi
        ;;
      click-candidate-[1-9])
        if [[ "${negative_phase:-false}" == true ]]; then
          continue
        fi
        candidate_row=${key_name##*-}
        popup_ready=false
        for _ in {1..100}; do
          candidate_window_id=$(xdotool search --onlyvisible \
            --name '^Fcitx5 Input Window$' 2>/dev/null | head -n 1 || true)
          if [[ -n "$candidate_window_id" ]]; then
            candidate_geometry=$(xdotool getwindowgeometry --shell \
              "$candidate_window_id" 2>/dev/null || true)
            candidate_width=$(printf '%s\n' "$candidate_geometry" |
              sed -n 's/^WIDTH=//p')
            candidate_height=$(printf '%s\n' "$candidate_geometry" |
              sed -n 's/^HEIGHT=//p')
            if [[ "$candidate_width" =~ ^[0-9]+$ &&
                  "$candidate_height" =~ ^[0-9]+$ &&
                  "$candidate_width" -gt 10 &&
                  "$candidate_height" -gt 100 ]]; then
              popup_ready=true
              break
            fi
          fi
          sleep 0.05
        done
        if [[ "$popup_ready" != true ]]; then
          echo "The expanded Fcitx candidate window did not become visible." >&2
          exit 1
        fi
        # Classic UI lays out the nine vertical candidates as equal-height rows.
        # Click the requested row's center after the popup has expanded past the
        # transient 1x1 and preedit-only window geometries.
        click_x=$((candidate_width / 2))
        click_y=$((candidate_height * (2 * candidate_row - 1) / 18))
        printf 'window=%s width=%s height=%s row=%s x=%s y=%s\n' \
          "$candidate_window_id" "$candidate_width" "$candidate_height" \
          "$candidate_row" "$click_x" "$click_y" \
          >"$KEYKEY_E2E_CASE_DIR/candidate-click.txt"
        xdotool mousemove --window "$candidate_window_id" \
          "$click_x" "$click_y" click 1
        ;;
      wait-500ms) sleep 0.5 ;;
      wait-1000ms) sleep 1 ;;
      *) xdotool key --delay "$key_delay_ms" "$key_name" ;;
    esac
  done
}

activate_existing_gnome_window() {
  local window_id=$1
  for _ in {1..20}; do
    if [[ $(xdotool getactivewindow 2>/dev/null || true) == "$window_id" ]]; then
      return 0
    fi
    xdotool windowactivate "$window_id" 2>/dev/null || true
    sleep 0.05
  done
  return 1
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
  unset KEYKEY_E2E_SCENARIO KEYKEY_E2E_EXPECTED_FIRST \
    KEYKEY_E2E_EXPECTED_SECOND KEYKEY_E2E_EXPECTED_THIRD \
    KEYKEY_E2E_REQUIRED_EVENTS

  "$KEYKEY_E2E_HOST" >"$case_dir/host.stdout.log" \
    2>"$case_dir/host.stderr.log" &
  host_pid=$!

  window_id=
  window_focused=false
  for _ in {1..100}; do
    window_id=$(xdotool search --onlyvisible --all --pid "$host_pid" \
      --name "^${e2e_host_window_title}$" 2>/dev/null | head -n 1 || true)
    if [[ -n "$window_id" ]]; then
      if [[ "$session_mode" == existing-gnome ]]; then
        if activate_existing_gnome_window "$window_id"; then
          xdotool mousemove --window "$window_id" 240 15 click 1
          window_focused=true
          break
        fi
      elif xdotool windowfocus --sync "$window_id" 2>/dev/null; then
        window_focused=true
        break
      fi
    fi
    if ! kill -0 "$host_pid" 2>/dev/null; then
      wait "$host_pid" || true
      host_pid=
      echo "$e2e_host_label E2E host exited before its window was ready for $case_id." >&2
      exit 1
    fi
    sleep 0.1
  done
  if [[ "$window_focused" != true ]]; then
    echo "$e2e_host_label E2E host window could not be focused for $case_id." >&2
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

  negative_phase=false
  send_key_sequence "$@"
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
  negative_phase=true
  send_key_sequence "$@"
  negative_phase=false

  wait "$host_pid"
  host_pid=
  grep -Fxq "$expected_literal" "$case_dir/final.txt"
  printf '%s\n' \
    "{\"test\":\"$case_id\",\"engine\":\"$engine_name\",\"expected\":\"$expected_commit\",\"negative\":\"$expected_literal\",\"status\":\"passed\"}" \
    >"$case_dir/result.json"
}

run_gtk4_case() {
  KEYKEY_E2E_HOST=$KEYKEY_E2E_GTK4_HOST
  e2e_host_window_title=chichi77-keykey-gtk4-e2e
  e2e_host_label='GTK 4'
  run_case "$@"
  KEYKEY_E2E_HOST=$gtk3_e2e_host
  e2e_host_window_title=chichi77-keykey-gtk3-e2e
  e2e_host_label='GTK 3'
}

run_gtk4_focus_case() {
  KEYKEY_E2E_HOST=$KEYKEY_E2E_GTK4_HOST
  e2e_host_window_title=chichi77-keykey-gtk4-e2e
  e2e_host_label='GTK 4'
  run_focus_case "$@"
  KEYKEY_E2E_HOST=$gtk3_e2e_host
  e2e_host_window_title=chichi77-keykey-gtk3-e2e
  e2e_host_label='GTK 3'
}

run_gtk4_multi_app_case() {
  KEYKEY_E2E_HOST=$KEYKEY_E2E_GTK4_HOST
  e2e_host_window_title=chichi77-keykey-gtk4-e2e
  e2e_host_label='GTK 4'
  run_multi_app_case "$@"
  KEYKEY_E2E_HOST=$gtk3_e2e_host
  e2e_host_window_title=chichi77-keykey-gtk3-e2e
  e2e_host_label='GTK 3'
}

run_gtk4_editing_case() {
  KEYKEY_E2E_HOST=$KEYKEY_E2E_GTK4_HOST
  e2e_host_window_title=chichi77-keykey-gtk4-e2e
  e2e_host_label='GTK 4'
  run_editing_case "$@"
  KEYKEY_E2E_HOST=$gtk3_e2e_host
  e2e_host_window_title=chichi77-keykey-gtk3-e2e
  e2e_host_label='GTK 3'
}

run_qt6_case() {
  KEYKEY_E2E_HOST=$KEYKEY_E2E_QT6_HOST
  e2e_host_window_title=chichi77-keykey-qt6-e2e
  e2e_host_label='Qt 6'
  run_case "$@"
  KEYKEY_E2E_HOST=$gtk3_e2e_host
  e2e_host_window_title=chichi77-keykey-gtk3-e2e
  e2e_host_label='GTK 3'
}

run_qt6_focus_case() {
  KEYKEY_E2E_HOST=$KEYKEY_E2E_QT6_HOST
  e2e_host_window_title=chichi77-keykey-qt6-e2e
  e2e_host_label='Qt 6'
  run_focus_case "$@"
  KEYKEY_E2E_HOST=$gtk3_e2e_host
  e2e_host_window_title=chichi77-keykey-gtk3-e2e
  e2e_host_label='GTK 3'
}

run_qt6_multi_app_case() {
  KEYKEY_E2E_HOST=$KEYKEY_E2E_QT6_HOST
  e2e_host_window_title=chichi77-keykey-qt6-e2e
  e2e_host_label='Qt 6'
  run_multi_app_case "$@"
  KEYKEY_E2E_HOST=$gtk3_e2e_host
  e2e_host_window_title=chichi77-keykey-gtk3-e2e
  e2e_host_label='GTK 3'
}

run_qt6_editing_case() {
  KEYKEY_E2E_HOST=$KEYKEY_E2E_QT6_HOST
  e2e_host_window_title=chichi77-keykey-qt6-e2e
  e2e_host_label='Qt 6'
  run_editing_case "$@"
  KEYKEY_E2E_HOST=$gtk3_e2e_host
  e2e_host_window_title=chichi77-keykey-gtk3-e2e
  e2e_host_label='GTK 3'
}

wait_for_named_window() {
  local title=$1 process_id=$2 label=$3
  local candidate_window_id=''
  for _ in {1..100}; do
    candidate_window_id=$(xdotool search --onlyvisible --all --pid "$process_id" \
      --name "^${title}$" 2>/dev/null | head -n 1 || true)
    if [[ -n "$candidate_window_id" ]]; then
      printf '%s\n' "$candidate_window_id"
      return 0
    fi
    if ! kill -0 "$process_id" 2>/dev/null; then
      echo "$label exited before its window became visible." >&2
      return 1
    fi
    sleep 0.1
  done
  echo "$label did not publish a visible window." >&2
  return 1
}

focus_host_window() {
  local window_id=$1 process_id=$2 label=$3
  for _ in {1..50}; do
    if ! kill -0 "$process_id" 2>/dev/null; then
      echo "$label exited before it could receive focus." >&2
      return 1
    fi
    xdotool windowraise "$window_id" 2>/dev/null || true
    if [[ "$session_mode" == existing-gnome ]]; then
      if ! activate_existing_gnome_window "$window_id"; then
        sleep 0.1
        continue
      fi
    elif ! xdotool windowfocus --sync "$window_id" 2>/dev/null; then
      sleep 0.1
      continue
    fi
    # X11 focus can be visible before the client toolkit has dispatched its
    # focus event and notified Fcitx. This helper is used for cross-process
    # context switching; click the single centered editor, then give that
    # event one bounded loop turn before selecting the per-client engine.
    xdotool mousemove --window "$window_id" 240 15 click 1
    sleep 0.1
    return 0
  done
  echo "$label could not receive X11 focus." >&2
  return 1
}

activate_engine_for_focused_app() {
  local engine_name=$1 label=$2
  fcitx5-remote -o
  for _ in {1..100}; do
    fcitx5-remote -s "$engine_name" || true
    if [[ "$(fcitx5-remote -n)" == "$engine_name" ]]; then
      return 0
    fi
    sleep 0.1
  done
  echo "The $engine_name Fcitx engine is not active for $label." >&2
  return 1
}

wait_for_host_event() {
  local event_file=$1 expected_event=$2 label=$3
  for _ in {1..100}; do
    if [[ -f "$event_file" ]] && grep -Fq "$expected_event" "$event_file"; then
      return 0
    fi
    sleep 0.1
  done
  echo "$label did not report the expected GTK event: $expected_event" >&2
  return 1
}

focus_named_host_window() {
  local title=$1 process_id=$2 label=$3 candidate index
  local -a candidates=()
  for _ in {1..100}; do
    mapfile -t candidates < <(
      xdotool search --onlyvisible --all --pid "$process_id" \
        --name "^${title}$" 2>/dev/null || true)
    for ((index=${#candidates[@]} - 1; index >= 0; --index)); do
      candidate=${candidates[$index]}
      if [[ "$session_mode" == existing-gnome ]]; then
        if activate_existing_gnome_window "$candidate"; then
          printf '%s\n' "$candidate"
          return 0
        fi
      elif xdotool windowfocus --sync "$candidate" 2>/dev/null; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
    if ! kill -0 "$process_id" 2>/dev/null; then
      wait "$process_id" || true
      echo "$label exited before its window was ready." >&2
      return 1
    fi
    sleep 0.1
  done
  echo "$label window could not be focused." >&2
  return 1
}

run_focus_phase() {
  local case_id=$1
  local phase=$2
  local engine_name=$3
  local expected_first=$4
  local expected_second=$5
  local required_events=$6
  shift 6

  local phase_dir="$KEYKEY_E2E_ARTIFACT_DIR/$case_id/$phase"
  local window_id='' engine_ready=false
  local expected_output
  mkdir -p "$phase_dir"
  export KEYKEY_E2E_CASE_DIR="$phase_dir"
  export KEYKEY_E2E_SCENARIO=focus
  export KEYKEY_E2E_EXPECTED_FIRST="$expected_first"
  export KEYKEY_E2E_EXPECTED_SECOND="$expected_second"
  export KEYKEY_E2E_REQUIRED_EVENTS="$required_events"
  unset KEYKEY_E2E_EXPECTED_COMMIT KEYKEY_E2E_EXPECTED_LITERAL \
    KEYKEY_E2E_EXPECTED_THIRD KEYKEY_E2E_REQUIRED_PREEDITS

  "$KEYKEY_E2E_HOST" >"$phase_dir/host.stdout.log" \
    2>"$phase_dir/host.stderr.log" &
  host_pid=$!

  if ! window_id=$(focus_named_host_window "$e2e_host_window_title" \
      "$host_pid" "$e2e_host_label focus host for $case_id/$phase"); then
    host_pid=
    exit 1
  fi

  fcitx5-remote -o
  for _ in {1..100}; do
    fcitx5-remote -s "$engine_name" || true
    if [[ "$(fcitx5-remote -n)" == "$engine_name" ]]; then
      engine_ready=true
      break
    fi
    sleep 0.1
  done
  if [[ "$engine_ready" != true ]]; then
    echo "The $engine_name Fcitx engine is not active for $case_id/$phase." >&2
    exit 1
  fi

  send_key_sequence "$@"
  if ! wait "$host_pid"; then
    host_pid=
    echo "$case_id/$phase did not preserve independent GTK input contexts." >&2
    exit 1
  fi
  host_pid=
  expected_output=$(printf '%s\t%s' "$expected_first" "$expected_second")
  grep -Fxq "$expected_output" "$phase_dir/final.txt"
}

run_editing_phase() {
  local case_id=$1
  local phase=$2
  local engine_name=$3
  local expected_first=$4
  local expected_second=$5
  local expected_third=$6
  local required_events=$7
  shift 7

  local phase_dir="$KEYKEY_E2E_ARTIFACT_DIR/$case_id/$phase"
  local window_id='' engine_ready=false
  local expected_output
  mkdir -p "$phase_dir"
  export KEYKEY_E2E_CASE_DIR="$phase_dir"
  export KEYKEY_E2E_SCENARIO=editing
  export KEYKEY_E2E_EXPECTED_FIRST="$expected_first"
  export KEYKEY_E2E_EXPECTED_SECOND="$expected_second"
  export KEYKEY_E2E_EXPECTED_THIRD="$expected_third"
  export KEYKEY_E2E_REQUIRED_EVENTS="$required_events"
  unset KEYKEY_E2E_EXPECTED_COMMIT KEYKEY_E2E_EXPECTED_LITERAL \
    KEYKEY_E2E_REQUIRED_PREEDITS

  "$KEYKEY_E2E_HOST" >"$phase_dir/host.stdout.log" \
    2>"$phase_dir/host.stderr.log" &
  host_pid=$!

  if ! window_id=$(focus_named_host_window "$e2e_host_window_title" \
      "$host_pid" "$e2e_host_label editing host for $case_id/$phase"); then
    host_pid=
    exit 1
  fi

  fcitx5-remote -o
  for _ in {1..100}; do
    fcitx5-remote -s "$engine_name" || true
    if [[ "$(fcitx5-remote -n)" == "$engine_name" ]]; then
      engine_ready=true
      break
    fi
    sleep 0.1
  done
  if [[ "$engine_ready" != true ]]; then
    echo "The $engine_name Fcitx engine is not active for $case_id/$phase." >&2
    exit 1
  fi

  send_key_sequence "$@"
  if ! wait "$host_pid"; then
    host_pid=
    echo "$case_id/$phase did not preserve the editing-field boundaries." >&2
    exit 1
  fi
  host_pid=
  expected_output=$(printf '%s\t%s\t%s' \
    "$expected_first" "$expected_second" "$expected_third")
  grep -Fxq "$expected_output" "$phase_dir/final.txt"
}

run_client_close_recovery() {
  local case_id=$1
  local close_dir="$KEYKEY_E2E_ARTIFACT_DIR/$case_id/client-close"
  local window_id='' engine_ready=false candidate_ready=false
  local close_required_preedits='ㄓ,ㄓㄨ,ㄓㄨㄥ,ㄓㄨㄥ'
  if [[ "$e2e_host_label" == 'Qt 6' ]]; then
    close_required_preedits='ㄓ,ㄓㄨ,ㄓㄨㄥ'
  fi
  mkdir -p "$close_dir"
  export KEYKEY_E2E_CASE_DIR="$close_dir"
  export KEYKEY_E2E_SCENARIO=close
  export KEYKEY_E2E_REQUIRED_PREEDITS="$close_required_preedits"
  unset KEYKEY_E2E_EXPECTED_COMMIT KEYKEY_E2E_EXPECTED_LITERAL \
    KEYKEY_E2E_EXPECTED_FIRST KEYKEY_E2E_EXPECTED_SECOND \
    KEYKEY_E2E_EXPECTED_THIRD KEYKEY_E2E_REQUIRED_EVENTS

  "$KEYKEY_E2E_HOST" >"$close_dir/host.stdout.log" \
    2>"$close_dir/host.stderr.log" &
  host_pid=$!

  if ! window_id=$(focus_named_host_window "$e2e_host_window_title" \
      "$host_pid" "$e2e_host_label close host for $case_id"); then
    host_pid=
    exit 1
  fi

  fcitx5-remote -o
  for _ in {1..100}; do
    fcitx5-remote -s chichi77-keykey-bopomofo || true
    if [[ "$(fcitx5-remote -n)" == chichi77-keykey-bopomofo ]]; then
      engine_ready=true
      break
    fi
    sleep 0.1
  done
  if [[ "$engine_ready" != true ]]; then
    echo "The Bopomofo engine is not active for $case_id/client-close." >&2
    exit 1
  fi

  send_key_sequence 5 j slash space
  for _ in {1..100}; do
    if [[ -f "$close_dir/ready-to-close" ]] && \
        { [[ "$e2e_host_label" != 'Qt 6' ]] || \
          [[ -n "$(xdotool search --onlyvisible \
            --name '^Fcitx5 Input Window$' 2>/dev/null || true)" ]]; }; then
      candidate_ready=true
      break
    fi
    sleep 0.1
  done
  if [[ "$candidate_ready" != true ]]; then
    echo "$case_id did not open candidates before closing the client." >&2
    exit 1
  fi
  touch "$close_dir/close-now"
  if ! wait "$host_pid"; then
    host_pid=
    echo "$case_id did not close cleanly with active candidates." >&2
    exit 1
  fi
  host_pid=
  grep -Fxq closed "$close_dir/final.txt"
  if ! kill -0 "$fcitx_pid" 2>/dev/null || \
      ! grep -Fq 'chichi77-keykey.so' "/proc/$fcitx_pid/maps"; then
    echo "Fcitx or the KeyKey addon stopped after its client closed." >&2
    exit 1
  fi

  restart_fcitx
  run_case "$case_id/recovery" chichi77-keykey-bopomofo \
    中 '5j/ 1' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space 1
}

run_editing_case() {
  local case_id=$1
  local positive_events='' negative_events=''
  local positive_key_sequence=(
    drag-first-second-character 5 j slash space 1
    Home Right 5 j Left Right Home End Delete Tab
    shift+Left shift+Right shift+Tab slash space 1
    Tab expect-keyboard-us r u p space 1 shift+1
    Tab expect-keyboard-us 5 j slash space 1
  )
  local negative_key_sequence=(
    drag-first-second-character 5 j slash space 1
    Tab r u p space 1 shift+1
    Tab 5 j slash space 1
  )
  if [[ "$e2e_host_label" == 'Qt 6' ]]; then
    positive_key_sequence=(
      drag-first-second-character 5 j slash space 1
      Home Right 5 j Left Right Home End Delete Tab
      shift+Left shift+Right shift+Tab slash space 1
      Tab r u p space 1 shift+1
      Tab 5 j slash space 1
    )
  fi

  positive_events+='first-selection=1:2;first-text=甲中丙;'
  positive_events+='first-text=甲中中丙;'
  positive_events+='second-text=rup 1!;'
  positive_events+='third-focus=in;third-key-press=1'
  negative_events+='first-selection=1:2;first-text=甲5j/ 1丙;'
  negative_events+='second-text=rup 1!;'
  negative_events+='third-focus=in;third-key-press=1'

  run_editing_phase "$case_id" positive chichi77-keykey-bopomofo \
    甲中中丙 'rup 1!' 唯讀 "$positive_events" "${positive_key_sequence[@]}"
  if ! grep -Fq 'chichi77-keykey.so' "/proc/$fcitx_pid/maps"; then
    echo "The running Fcitx process did not load the staged KeyKey addon." >&2
    exit 1
  fi
  run_editing_phase "$case_id" negative keyboard-us \
    '甲5j/ 1丙' 'rup 1!' 唯讀 "$negative_events" \
    "${negative_key_sequence[@]}"
  printf '%s\n' \
    "{\"test\":\"$case_id\",\"engine\":\"chichi77-keykey-bopomofo\",\"expected\":\"甲中中丙|rup 1!|唯讀\",\"negative\":\"甲5j/ 1丙|rup 1!|唯讀\",\"status\":\"passed\"}" \
    >"$KEYKEY_E2E_ARTIFACT_DIR/$case_id/result.json"
}

run_focus_case() {
  local case_id=$1
  local positive_events=
  local positive_key_sequence=(
    5 j slash space click-second-entry
    activate-bopomofo
    j p 6 1
    shift+Tab 1 Escape
    5 j slash space 1
  )
  local negative_key_sequence=(
    5 j slash space click-second-entry
    j p 6 1
    shift+Tab 1 Escape
    5 j slash space 1
  )

  positive_events+='first-preedit=ㄓ;first-preedit=ㄓㄨ;'
  positive_events+='first-preedit=ㄓㄨㄥ;first-preedit=;'
  positive_events+='second-preedit=ㄨ;second-preedit=ㄨㄣ;'
  positive_events+='second-preedit=ㄨㄣˊ;second-text=文;'
  positive_events+='first-preedit=ㄅ;first-preedit=;first-text=中'

  run_focus_phase "$case_id" positive chichi77-keykey-bopomofo \
    中 文 "$positive_events" "${positive_key_sequence[@]}"
  if ! grep -Fq 'chichi77-keykey.so' "/proc/$fcitx_pid/maps"; then
    echo "The running Fcitx process did not load the staged KeyKey addon." >&2
    exit 1
  fi
  run_focus_phase "$case_id" negative keyboard-us \
    '15j/ 1' jp61 '' "${negative_key_sequence[@]}"
  run_client_close_recovery "$case_id"
  printf '%s\n' \
    "{\"test\":\"$case_id\",\"engine\":\"chichi77-keykey-bopomofo\",\"expected\":\"中|文;restart=中\",\"negative\":\"15j/ 1|jp61;restart=5j/ 1\",\"status\":\"passed\"}" \
    >"$KEYKEY_E2E_ARTIFACT_DIR/$case_id/result.json"
}

run_multi_app_phase() {
  local case_id=$1 phase=$2 engine_name=$3
  local app_a_expected=$4 app_b_expected=$5
  local phase_dir="$KEYKEY_E2E_ARTIFACT_DIR/$case_id/$phase"
  local app_a_dir="$phase_dir/app-a" app_b_dir="$phase_dir/app-b"
  local app_a_title="chichi77-keykey-$phase-app-a"
  local app_b_title="chichi77-keykey-$phase-app-b"
  local app_a_window='' app_b_window='' window_id=''
  local app_a_events="$app_a_dir/events.jsonl"
  local app_b_events="$app_b_dir/events.jsonl"
  mkdir -p "$app_a_dir" "$app_b_dir"

  KEYKEY_E2E_CASE_DIR="$app_a_dir" \
    KEYKEY_E2E_SCENARIO=hold \
    KEYKEY_E2E_WINDOW_TITLE="$app_a_title" \
    "$KEYKEY_E2E_HOST" >"$app_a_dir/host.stdout.log" \
      2>"$app_a_dir/host.stderr.log" &
  host_pid=$!
  KEYKEY_E2E_CASE_DIR="$app_b_dir" \
    KEYKEY_E2E_SCENARIO=hold \
    KEYKEY_E2E_WINDOW_TITLE="$app_b_title" \
    "$KEYKEY_E2E_HOST" >"$app_b_dir/host.stdout.log" \
      2>"$app_b_dir/host.stderr.log" &
  secondary_host_pid=$!

  app_a_window=$(wait_for_named_window \
    "$app_a_title" "$host_pid" "$case_id/$phase app A")
  app_b_window=$(wait_for_named_window \
    "$app_b_title" "$secondary_host_pid" "$case_id/$phase app B")

  focus_host_window \
    "$app_a_window" "$host_pid" "$case_id/$phase app A"
  activate_engine_for_focused_app "$engine_name" "$case_id/$phase app A"
  window_id=$app_a_window
  if [[ "$phase" == positive ]]; then
    send_key_sequence ctrl+backslash shift+space a
    wait_for_host_event "$app_a_events" \
      '"type":"text","value":"ａ"' "$case_id/$phase app A"

    focus_host_window \
      "$app_b_window" "$secondary_host_pid" "$case_id/$phase app B"
    activate_engine_for_focused_app "$engine_name" "$case_id/$phase app B"
    window_id=$app_b_window
    send_key_sequence j p 6 1
    wait_for_host_event "$app_b_events" \
      '"type":"text","value":"文"' "$case_id/$phase app B"

    focus_host_window \
      "$app_a_window" "$host_pid" "$case_id/$phase app A"
    activate_engine_for_focused_app "$engine_name" "$case_id/$phase app A"
    window_id=$app_a_window
    send_key_sequence b
    wait_for_host_event "$app_a_events" \
      '"type":"text","value":"ａｂ"' "$case_id/$phase app A"
    send_key_sequence shift+space ctrl+backslash 5 j slash space 1
    wait_for_host_event "$app_a_events" \
      '"type":"text","value":"ａｂ中"' "$case_id/$phase app A"
  else
    send_key_sequence a
    wait_for_host_event "$app_a_events" \
      '"type":"text","value":"a"' "$case_id/$phase app A"

    focus_host_window \
      "$app_b_window" "$secondary_host_pid" "$case_id/$phase app B"
    activate_engine_for_focused_app "$engine_name" "$case_id/$phase app B"
    window_id=$app_b_window
    send_key_sequence j p 6 1
    wait_for_host_event "$app_b_events" \
      '"type":"text","value":"jp61"' "$case_id/$phase app B"

    focus_host_window \
      "$app_a_window" "$host_pid" "$case_id/$phase app A"
    activate_engine_for_focused_app "$engine_name" "$case_id/$phase app A"
    window_id=$app_a_window
    send_key_sequence b 5 j slash space 1
    wait_for_host_event "$app_a_events" \
      '"type":"text","value":"ab5j/ 1"' "$case_id/$phase app A"
  fi

  if ! kill -0 "$host_pid" 2>/dev/null ||
      ! kill -0 "$secondary_host_pid" 2>/dev/null; then
    echo "$case_id/$phase did not keep both GTK apps alive." >&2
    exit 1
  fi
  touch "$app_a_dir/close-now" "$app_b_dir/close-now"
  if ! wait "$host_pid"; then
    echo "$case_id/$phase app A did not close cleanly." >&2
    exit 1
  fi
  host_pid=
  if ! wait "$secondary_host_pid"; then
    echo "$case_id/$phase app B did not close cleanly." >&2
    exit 1
  fi
  secondary_host_pid=
  grep -Fxq "$app_a_expected" "$app_a_dir/final.txt"
  grep -Fxq "$app_b_expected" "$app_b_dir/final.txt"
}

run_multi_app_case() {
  local case_id=$1
  run_multi_app_phase "$case_id" positive \
    chichi77-keykey-bopomofo ａｂ中 文
  if ! grep -Fq 'chichi77-keykey.so' "/proc/$fcitx_pid/maps"; then
    echo "The running Fcitx process did not load the staged KeyKey addon." >&2
    exit 1
  fi
  run_multi_app_phase "$case_id" negative keyboard-us 'ab5j/ 1' jp61
  printf '%s\n' \
    "{\"test\":\"$case_id\",\"engine\":\"chichi77-keykey-bopomofo\",\"expected\":\"ａｂ中|文\",\"negative\":\"ab5j/ 1|jp61\",\"status\":\"passed\"}" \
    >"$KEYKEY_E2E_ARTIFACT_DIR/$case_id/result.json"
}

if case_selected T07-X11-FCITX5-CONFIG-UI-PERSISTENCE; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections McBopomofo
  ui_case_dir="$KEYKEY_E2E_ARTIFACT_DIR/"
  ui_case_dir+=T07-X11-FCITX5-CONFIG-UI-PERSISTENCE
  mkdir -p "$ui_case_dir"
  # Qt is launched through Fcitx/D-Bus. Start the accessibility registry first
  # so the newly launched settings window registers in the AT-SPI tree.
  python3 -c 'import pyatspi; pyatspi.Registry.getDesktop(0)'
  gdbus call --session --dest org.fcitx.Fcitx5 \
    --object-path /controller \
    --method org.fcitx.Fcitx.Controller1.ConfigureIM \
    chichi77-keykey-bopomofo >"$ui_case_dir/configure-im-result.txt"
  python3 tests/fcitx5_config_ui_driver.py "$ui_case_dir"
  cp "$XDG_CONFIG_HOME/fcitx5/conf/chichi77-keykey.conf" \
    "$ui_case_dir/saved-config.ini"
  chmod 0644 "$ui_case_dir/saved-config.ini"
  grep -Fxq 'AssociatedPhraseCollections=agriculture-food' \
    "$ui_case_dir/saved-config.ini"
  grep -Fxq 'McBopomofo=False' "$ui_case_dir/saved-config.ini"
  grep -Fxq 'agriculture-food=True' "$ui_case_dir/saved-config.ini"
  grep -Fxq 'PlaySoundOnTypingError=False' \
    "$ui_case_dir/saved-config.ini"
  grep -Fxq 'ToggleInputMethodWithControlBackslash=False' \
    "$ui_case_dir/saved-config.ini"
  grep -Fxq 'CandidateWindowStyle=Horizontal' \
    "$ui_case_dir/saved-config.ini"
  restart_fcitx
  get_keykey_config_via_dbus "$ui_case_dir/config-after-restart.txt"
  grep -Fq "'McBopomofo': <'False'>" \
    "$ui_case_dir/config-after-restart.txt"
  grep -Fq "'agriculture-food': <'True'>" \
    "$ui_case_dir/config-after-restart.txt"
  grep -Fq "'PlaySoundOnTypingError': <'False'>" \
    "$ui_case_dir/config-after-restart.txt"
  grep -Fq "'ToggleInputMethodWithControlBackslash': <'False'>" \
    "$ui_case_dir/config-after-restart.txt"
  grep -Fq "'CandidateWindowStyle': <'Horizontal'>" \
    "$ui_case_dir/config-after-restart.txt"
  run_case T07-X11-FCITX5-CONFIG-UI-PERSISTENCE \
    chichi77-keykey-bopomofo \
    作物育種 'yji42!' 'ㄗ,ㄗㄨ,ㄗㄨㄛ,ㄗㄨㄛˋ' \
    y j i 4 2 shift+1
  set_associated_phrase_collections ''
  set_candidate_window_style Vertical
fi
if case_selected T01-X11-GTK3-BOPOMOFO-STANDARD; then
  set_bopomofo_layout Standard
  run_case T01-X11-GTK3-BOPOMOFO-STANDARD chichi77-keykey-bopomofo \
    中 '5j/ 1' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space 1
  verify_bopomofo_config_schema
fi
if case_selected T01-X11-GTK4-BOPOMOFO-STANDARD; then
  set_bopomofo_layout Standard
  run_gtk4_case T01-X11-GTK4-BOPOMOFO-STANDARD chichi77-keykey-bopomofo \
    中 '5j/ 1' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space 1
fi
if case_selected T01-X11-QT6-BOPOMOFO-STANDARD; then
  set_bopomofo_layout Standard
  run_qt6_case T01-X11-QT6-BOPOMOFO-STANDARD chichi77-keykey-bopomofo \
    中 '5j/ 1' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space 1
fi
if case_selected T01-X11-GTK3-BOPOMOFO-BIG5-FILTER; then
  set_bopomofo_layout Standard
  set_use_all_unicode_characters False
  run_case T01-X11-GTK3-BOPOMOFO-BIG5-FILTER \
    chichi77-keykey-bopomofo \
    𤦩 ',42' 'ㄝ,ㄝˋ' comma 4 2
  set_use_all_unicode_characters True
fi
if case_selected T01-X11-GTK3-BOPOMOFO-CONTINUOUS; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_case T01-X11-GTK3-BOPOMOFO-CONTINUOUS \
    chichi77-keykey-bopomofo \
    中文 '5j/ jp61' 'ㄓ,ㄓㄨ,ㄓㄨㄥ,ㄨ,ㄨㄣ,ㄨㄣˊ' \
    5 j slash space j p 6 1
fi
if case_selected T01-X11-GTK3-BOPOMOFO-INVALID-INPUT; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_case T01-X11-GTK3-BOPOMOFO-INVALID-INPUT \
    chichi77-keykey-bopomofo \
    中 '5=j/ 1' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' \
    5 equal ctrl+c j slash space 1
fi
if case_selected T08-X11-GTK3-CHINESE-ENGLISH-MODE; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  set_toggle_with_control_backslash True
  run_case T08-X11-GTK3-CHINESE-ENGLISH-MODE \
    chichi77-keykey-bopomofo \
    '5j/aBａ！　文abcde麻' '55j/aB a!  jp61abcdea861' \
    'ㄓ,ㄨ,ㄨㄣ,ㄨㄣˊ,ㄇ,ㄇㄚ,ㄇㄚˊ' \
    5 ctrl+backslash 5 j slash a Caps_Lock b Caps_Lock \
    shift+space a shift+1 space shift+space \
    ctrl+backslash j p 6 1 \
    shift a b c shift-down wait-500ms shift-up d e shift a 8 6 1
fi
if case_selected T08-X11-GTK4-CHINESE-ENGLISH-MODE; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  set_toggle_with_control_backslash True
  run_gtk4_case T08-X11-GTK4-CHINESE-ENGLISH-MODE \
    chichi77-keykey-bopomofo \
    '5j/aBａ！　文abcde麻' '55j/aB a!  jp61abcdea861' \
    'ㄓ,ㄨ,ㄨㄣ,ㄨㄣˊ,ㄇ,ㄇㄚ,ㄇㄚˊ' \
    5 ctrl+backslash 5 j slash a Caps_Lock b Caps_Lock \
    shift+space a shift+1 space shift+space \
    ctrl+backslash j p 6 1 \
    shift a b c shift-down wait-500ms shift-up d e shift a 8 6 1
fi
if case_selected T08-X11-GTK3-CONTROL-BACKSLASH-DISABLED; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  set_toggle_with_control_backslash False
  run_case T08-X11-GTK3-CONTROL-BACKSLASH-DISABLED \
    chichi77-keykey-bopomofo \
    'ㄓ翁' '5j/ 1' 'ㄓ,ㄨ,ㄨㄥ' \
    5 ctrl+backslash j slash space 1
  set_toggle_with_control_backslash True
fi
if case_selected T08-X11-GTK4-CONTROL-BACKSLASH-DISABLED; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  set_toggle_with_control_backslash False
  run_gtk4_case T08-X11-GTK4-CONTROL-BACKSLASH-DISABLED \
    chichi77-keykey-bopomofo \
    '翁ㄓ' '5j/ 1' 'ㄓ,ㄨ,ㄨㄥ' \
    5 ctrl+backslash j slash space 1
  set_toggle_with_control_backslash True
fi
if case_selected T02-X11-GTK3-BOPOMOFO-STANDARD; then
  set_bopomofo_layout Standard
  run_case T02-X11-GTK3-BOPOMOFO-STANDARD chichi77-keykey-bopomofo \
    麻馬罵嘛 'a8\61a831a841a871' \
    'ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    a 8 backslash ctrl+c 6 1 a 8 3 1 a 8 4 1 a 8 7 1
fi
if case_selected T02-X11-GTK3-BOPOMOFO-ETEN; then
  set_bopomofo_layout ETen
  run_case T02-X11-GTK3-BOPOMOFO-ETEN chichi77-keykey-bopomofo \
    麻馬罵嘛 'ma\21ma31ma41ma11' \
    'ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m a backslash ctrl+c 2 1 m a 3 1 m a 4 1 m a 1 1
fi
if case_selected T02-X11-GTK3-BOPOMOFO-ETEN26; then
  set_bopomofo_layout ETen26
  run_case T02-X11-GTK3-BOPOMOFO-ETEN26 chichi77-keykey-bopomofo \
    麻馬罵嘛 'ma\f1maj1mak1mad1' \
    'ㄢ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m a backslash ctrl+c f 1 m a j 1 m a k 1 m a d 1
fi
if case_selected T02-X11-GTK3-BOPOMOFO-HSU; then
  set_bopomofo_layout Hsu
  run_case T02-X11-GTK3-BOPOMOFO-HSU chichi77-keykey-bopomofo \
    麻馬罵嘛 'my\d1myf1myj1mys1' \
    'ㄢ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m y backslash ctrl+c d 1 m y f 1 m y j 1 m y s 1
fi
if case_selected T02-X11-GTK3-BOPOMOFO-HANYU-PINYIN; then
  set_bopomofo_layout HanyuPinyin
  run_case T02-X11-GTK3-BOPOMOFO-HANYU-PINYIN chichi77-keykey-bopomofo \
    麻馬罵嘛 'ma\21ma31ma41ma51' \
    'z,zh,m,ma,ma2,ma3,ma4,ma5' \
    z h BackSpace BackSpace \
    m a backslash ctrl+c 2 1 m a 3 1 m a 4 1 m a 5 1
fi
if case_selected T02-X11-GTK4-BOPOMOFO-STANDARD; then
  set_bopomofo_layout Standard
  run_gtk4_case T02-X11-GTK4-BOPOMOFO-STANDARD chichi77-keykey-bopomofo \
    麻馬罵嘛 'a8\61a831a841a871' \
    'ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    a 8 backslash ctrl+c 6 1 a 8 3 1 a 8 4 1 a 8 7 1
fi
if case_selected T02-X11-GTK4-BOPOMOFO-ETEN; then
  set_bopomofo_layout ETen
  run_gtk4_case T02-X11-GTK4-BOPOMOFO-ETEN chichi77-keykey-bopomofo \
    麻馬罵嘛 'ma\21ma31ma41ma11' \
    'ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m a backslash ctrl+c 2 1 m a 3 1 m a 4 1 m a 1 1
fi
if case_selected T02-X11-GTK4-BOPOMOFO-ETEN26; then
  set_bopomofo_layout ETen26
  run_gtk4_case T02-X11-GTK4-BOPOMOFO-ETEN26 chichi77-keykey-bopomofo \
    麻馬罵嘛 'ma\f1maj1mak1mad1' \
    'ㄢ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m a backslash ctrl+c f 1 m a j 1 m a k 1 m a d 1
fi
if case_selected T02-X11-GTK4-BOPOMOFO-HSU; then
  set_bopomofo_layout Hsu
  run_gtk4_case T02-X11-GTK4-BOPOMOFO-HSU chichi77-keykey-bopomofo \
    麻馬罵嘛 'my\d1myf1myj1mys1' \
    'ㄢ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m y backslash ctrl+c d 1 m y f 1 m y j 1 m y s 1
fi
if case_selected T02-X11-GTK4-BOPOMOFO-HANYU-PINYIN; then
  set_bopomofo_layout HanyuPinyin
  run_gtk4_case T02-X11-GTK4-BOPOMOFO-HANYU-PINYIN \
    chichi77-keykey-bopomofo \
    麻馬罵嘛 'ma\21ma31ma41ma51' \
    'z,zh,m,ma,ma2,ma3,ma4,ma5' \
    z h BackSpace BackSpace \
    m a backslash ctrl+c 2 1 m a 3 1 m a 4 1 m a 5 1
fi
if case_selected T03-X11-GTK3-BOPOMOFO-EDIT-CANCEL; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_case T03-X11-GTK3-BOPOMOFO-EDIT-CANCEL \
    chichi77-keykey-bopomofo \
    中文麻 '5j// 1jpjp61a86a861' \
    'ㄓ,ㄓㄨ,ㄓㄨㄥ,ㄓㄨ,ㄓㄨㄥ,ㄨ,ㄨㄣ,ㄨ,ㄨㄣ,ㄨㄣˊ,ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇ,ㄇㄚ,ㄇㄚˊ' \
    equal BackSpace Escape \
    5 j slash space BackSpace slash space 1 \
    j p Escape j p 6 1 \
    a 8 6 Escape a 8 6 1
fi
if case_selected T03-X11-GTK4-BOPOMOFO-EDIT-CANCEL; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_gtk4_case T03-X11-GTK4-BOPOMOFO-EDIT-CANCEL \
    chichi77-keykey-bopomofo \
    中文麻 '5j// 1jpjp61a86a861' \
    'ㄓ,ㄓㄨ,ㄓㄨㄥ,ㄓㄨ,ㄓㄨㄥ,ㄨ,ㄨㄣ,ㄨ,ㄨㄣ,ㄨㄣˊ,ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇ,ㄇㄚ,ㄇㄚˊ' \
    equal BackSpace Escape \
    5 j slash space BackSpace slash space 1 \
    j p Escape j p 6 1 \
    a 8 6 Escape a 8 6 1
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
  set_candidate_window_style Vertical
  run_case T06-X11-GTK3-CANDIDATE-NAVIGATION chichi77-keykey-bopomofo \
    妐 '5j/ ' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space End Home Page_Down Down Return
fi
if case_selected T06-X11-GTK3-CANDIDATE-MOUSE; then
  set_bopomofo_layout Standard
  set_candidate_window_style Vertical
  run_case T06-X11-GTK3-CANDIDATE-MOUSE chichi77-keykey-bopomofo \
    鐘 '5j/ ' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space click-candidate-2
fi
if case_selected T06-X11-GTK4-CANDIDATE-NAVIGATION; then
  set_bopomofo_layout Standard
  set_candidate_window_style Vertical
  run_gtk4_case T06-X11-GTK4-CANDIDATE-NAVIGATION \
    chichi77-keykey-bopomofo \
    妐 '5j/ ' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space End Home Page_Down Down Return
fi
if case_selected T06-X11-GTK4-CANDIDATE-MOUSE; then
  set_bopomofo_layout Standard
  set_candidate_window_style Vertical
  run_gtk4_case T06-X11-GTK4-CANDIDATE-MOUSE chichi77-keykey-bopomofo \
    鐘 '5j/ ' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space click-candidate-2
fi
if case_selected T06-X11-GTK4-CANDIDATE-HORIZONTAL; then
  set_bopomofo_layout Standard
  set_candidate_window_style Horizontal
  run_gtk4_case T06-X11-GTK4-CANDIDATE-HORIZONTAL \
    chichi77-keykey-bopomofo \
    妐 ' 5j/ ' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' \
    5 j slash space End Home Page_Down Page_Up Right Left space Down Return
fi
if case_selected T07-X11-GTK3-ASSOCIATED-PHRASE; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections McBopomofo
  run_case T07-X11-GTK3-ASSOCIATED-PHRASE chichi77-keykey-bopomofo \
    今天 'rup 1!' 'ㄐ,ㄐㄧ,ㄐㄧㄣ' r u p space 1 shift+1
fi
if case_selected T07-X11-GTK4-ASSOCIATED-PHRASE; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections McBopomofo
  run_gtk4_case T07-X11-GTK4-ASSOCIATED-PHRASE \
    chichi77-keykey-bopomofo \
    今天 'rup 1!' 'ㄐ,ㄐㄧ,ㄐㄧㄣ' r u p space 1 shift+1
fi
if case_selected T07-X11-GTK3-ASSOCIATED-PHRASE-CATEGORY; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections history
  run_case T07-X11-GTK3-ASSOCIATED-PHRASE-CATEGORY \
    chichi77-keykey-bopomofo \
    臺灣史 'w962!' 'ㄊ,ㄊㄞ,ㄊㄞˊ' w 9 6 2 shift+1
fi
if case_selected T07-X11-GTK4-ASSOCIATED-PHRASE-CATEGORY; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections history
  run_gtk4_case T07-X11-GTK4-ASSOCIATED-PHRASE-CATEGORY \
    chichi77-keykey-bopomofo \
    臺灣史 'w962!' 'ㄊ,ㄊㄞ,ㄊㄞˊ' w 9 6 2 shift+1
fi
if case_selected T07-X11-GTK3-ASSOCIATED-PHRASE-DISABLED; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_case T07-X11-GTK3-ASSOCIATED-PHRASE-DISABLED \
    chichi77-keykey-bopomofo \
    '臺!' 'w962!' 'ㄊ,ㄊㄞ,ㄊㄞˊ' w 9 6 2 shift+1
  set_associated_phrase_collections ''
fi
if case_selected T07-X11-GTK4-ASSOCIATED-PHRASE-DISABLED; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_gtk4_case T07-X11-GTK4-ASSOCIATED-PHRASE-DISABLED \
    chichi77-keykey-bopomofo \
    '臺!' 'w962!' 'ㄊ,ㄊㄞ,ㄊㄞˊ' w 9 6 2 shift+1
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
if case_selected T07-X11-GTK4-ASSOCIATED-PHRASE-LEGACY-CONFIG; then
  set_bopomofo_layout Standard
  associated_phrase_collections=government
  write_legacy_keykey_config
  reload_keykey_config
  run_gtk4_case T07-X11-GTK4-ASSOCIATED-PHRASE-LEGACY-CONFIG \
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
if case_selected T07-X11-GTK4-ASSOCIATED-PHRASE-DBUS-PERSISTENCE; then
  set_bopomofo_layout Standard
  associated_phrase_collections=government
  persistence_case_dir="$KEYKEY_E2E_ARTIFACT_DIR/"
  persistence_case_dir+=T07-X11-GTK4-ASSOCIATED-PHRASE-DBUS-PERSISTENCE
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
  run_gtk4_case T07-X11-GTK4-ASSOCIATED-PHRASE-DBUS-PERSISTENCE \
    chichi77-keykey-bopomofo \
    中程計畫 '5j/ 1!' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space 1 shift+1
  set_associated_phrase_collections ''
fi
if case_selected T08-X11-GTK3-FULL-WIDTH; then
  set_bopomofo_layout Standard
  run_case T08-X11-GTK3-FULL-WIDTH chichi77-keykey-bopomofo \
    'Ａ！～　' ' A!~ ' '' shift+space shift+a shift+1 shift+grave space
fi
if case_selected T08-X11-GTK4-FULL-WIDTH; then
  set_bopomofo_layout Standard
  run_gtk4_case T08-X11-GTK4-FULL-WIDTH chichi77-keykey-bopomofo \
    'Ａ！～　' ' A!~ ' '' shift+space shift+a shift+1 shift+grave space
fi
if case_selected T08-X11-GTK3-TRADITIONAL-TO-SIMPLIFIED; then
  set_bopomofo_layout Standard
  set_traditional_to_simplified True
  run_case T08-X11-GTK3-TRADITIONAL-TO-SIMPLIFIED chichi77-keykey-bopomofo \
    台湾 'w962j0 1' 'ㄊ,ㄊㄞ,ㄊㄞˊ,ㄨ,ㄨㄢ' \
    w 9 6 2 j 0 space 1
  set_traditional_to_simplified False
fi
if case_selected T08-X11-GTK4-TRADITIONAL-TO-SIMPLIFIED; then
  set_bopomofo_layout Standard
  set_traditional_to_simplified True
  run_gtk4_case T08-X11-GTK4-TRADITIONAL-TO-SIMPLIFIED \
    chichi77-keykey-bopomofo \
    台湾 'w962j0 1' 'ㄊ,ㄊㄞ,ㄊㄞˊ,ㄨ,ㄨㄢ' \
    w 9 6 2 j 0 space 1
  set_traditional_to_simplified False
fi
if case_selected T09-X11-GTK3-MODIFIER-PASSTHROUGH; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  set_toggle_with_control_backslash True
  run_case T09-X11-GTK3-MODIFIER-PASSTHROUGH \
    chichi77-keykey-bopomofo \
    'x中文' 'x5j/ 1jp61' \
    'ㄓ,ㄓㄨ,ㄓㄨㄥ,ㄨ,ㄨㄣ,ㄨㄣˊ' \
    ctrl-down backslash-down wait-1000ms ctrl-up backslash-up \
    ctrl+a BackSpace x \
    ctrl+backslash \
    5 ctrl+c alt+f j slash space ctrl+c alt+f 1 \
    j p 6 ctrl+c alt+f 1
fi
if case_selected T09-X11-GTK4-MODIFIER-PASSTHROUGH; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  set_toggle_with_control_backslash True
  run_gtk4_case T09-X11-GTK4-MODIFIER-PASSTHROUGH \
    chichi77-keykey-bopomofo \
    'x中文' 'x5j/ 1jp61' \
    'ㄓ,ㄓㄨ,ㄓㄨㄥ,ㄨ,ㄨㄣ,ㄨㄣˊ' \
    ctrl-down backslash-down wait-1000ms ctrl-up backslash-up \
    ctrl+a BackSpace x \
    ctrl+backslash \
    5 ctrl+c alt+f j slash space ctrl+c alt+f 1 \
    j p 6 ctrl+c alt+f 1
fi
if case_selected T10-X11-GTK3-INPUT-CONTEXT-ISOLATION; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_focus_case T10-X11-GTK3-INPUT-CONTEXT-ISOLATION
fi
if case_selected T10-X11-GTK3-MULTI-APP-ISOLATION; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_multi_app_case T10-X11-GTK3-MULTI-APP-ISOLATION
fi
if case_selected T10-X11-GTK4-INPUT-CONTEXT-ISOLATION; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_gtk4_focus_case T10-X11-GTK4-INPUT-CONTEXT-ISOLATION
fi
if case_selected T10-X11-GTK4-MULTI-APP-ISOLATION; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_gtk4_multi_app_case T10-X11-GTK4-MULTI-APP-ISOLATION
fi
if case_selected T11-X11-GTK3-EDITING-SENSITIVE-READONLY; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections McBopomofo
  run_editing_case T11-X11-GTK3-EDITING-SENSITIVE-READONLY
  set_associated_phrase_collections ''
fi
if case_selected T11-X11-GTK4-EDITING-SENSITIVE-READONLY; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections McBopomofo
  run_gtk4_editing_case T11-X11-GTK4-EDITING-SENSITIVE-READONLY
  set_associated_phrase_collections ''
fi
if case_selected T12-X11-GTK3-SYMBOL-LIST; then
  set_bopomofo_layout Standard
  set_candidate_window_style Vertical
  run_case T12-X11-GTK3-SYMBOL-LIST chichi77-keykey-bopomofo \
    ， '1' ， ctrl+0 1
fi
if case_selected T12-X11-GTK3-SYMBOL-LIST-MOUSE; then
  set_bopomofo_layout Standard
  set_candidate_window_style Vertical
  run_case T12-X11-GTK3-SYMBOL-LIST-MOUSE chichi77-keykey-bopomofo \
    '，!' '!' '' ctrl+0 click-candidate-1 wait-500ms shift+1
fi
if case_selected T12-X11-GTK4-SYMBOL-LIST; then
  set_bopomofo_layout Standard
  set_candidate_window_style Vertical
  run_gtk4_case T12-X11-GTK4-SYMBOL-LIST chichi77-keykey-bopomofo \
    ， '1' ， ctrl+0 1
fi
if case_selected T12-X11-GTK4-SYMBOL-LIST-MOUSE; then
  set_bopomofo_layout Standard
  set_candidate_window_style Vertical
  run_gtk4_case T12-X11-GTK4-SYMBOL-LIST-MOUSE \
    chichi77-keykey-bopomofo '，!' '!' '' \
    ctrl+0 click-candidate-1 wait-500ms shift+1
fi
if case_selected T02-X11-QT6-BOPOMOFO-STANDARD; then
  set_bopomofo_layout Standard
  run_qt6_case T02-X11-QT6-BOPOMOFO-STANDARD chichi77-keykey-bopomofo \
    麻馬罵嘛 'a8\61a831a841a871' \
    'ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    a 8 backslash ctrl+c 6 1 a 8 3 1 a 8 4 1 a 8 7 1
fi
if case_selected T02-X11-QT6-BOPOMOFO-ETEN; then
  set_bopomofo_layout ETen
  run_qt6_case T02-X11-QT6-BOPOMOFO-ETEN chichi77-keykey-bopomofo \
    麻馬罵嘛 'ma\21ma31ma41ma11' \
    'ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m a backslash ctrl+c 2 1 m a 3 1 m a 4 1 m a 1 1
fi
if case_selected T02-X11-QT6-BOPOMOFO-ETEN26; then
  set_bopomofo_layout ETen26
  run_qt6_case T02-X11-QT6-BOPOMOFO-ETEN26 chichi77-keykey-bopomofo \
    麻馬罵嘛 'ma\f1maj1mak1mad1' \
    'ㄢ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m a backslash ctrl+c f 1 m a j 1 m a k 1 m a d 1
fi
if case_selected T02-X11-QT6-BOPOMOFO-HSU; then
  set_bopomofo_layout Hsu
  run_qt6_case T02-X11-QT6-BOPOMOFO-HSU chichi77-keykey-bopomofo \
    麻馬罵嘛 'my\d1myf1myj1mys1' \
    'ㄢ,ㄇㄚ,ㄇㄚˊ,ㄇㄚˇ,ㄇㄚˋ,ㄇㄚ˙' \
    m y backslash ctrl+c d 1 m y f 1 m y j 1 m y s 1
fi
if case_selected T02-X11-QT6-BOPOMOFO-HANYU-PINYIN; then
  set_bopomofo_layout HanyuPinyin
  run_qt6_case T02-X11-QT6-BOPOMOFO-HANYU-PINYIN \
    chichi77-keykey-bopomofo \
    麻馬罵嘛 'ma\21ma31ma41ma51' \
    'z,zh,m,ma,ma2,ma3,ma4,ma5' \
    z h BackSpace BackSpace \
    m a backslash ctrl+c 2 1 m a 3 1 m a 4 1 m a 5 1
fi
if case_selected T03-X11-QT6-BOPOMOFO-EDIT-CANCEL; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_qt6_case T03-X11-QT6-BOPOMOFO-EDIT-CANCEL \
    chichi77-keykey-bopomofo \
    中文麻 '5j// 1jpjp61a86a861' \
    'ㄓ,ㄓㄨ,ㄓㄨㄥ,ㄓㄨ,ㄓㄨㄥ,ㄨ,ㄨㄣ,ㄨ,ㄨㄣ,ㄨㄣˊ,ㄇ,ㄇㄚ,ㄇㄚˊ,ㄇ,ㄇㄚ,ㄇㄚˊ' \
    equal BackSpace Escape \
    5 j slash space BackSpace slash space 1 \
    j p Escape j p 6 1 \
    a 8 6 Escape a 8 6 1
fi
if case_selected T06-X11-QT6-CANDIDATE-NAVIGATION; then
  set_bopomofo_layout Standard
  set_candidate_window_style Vertical
  run_qt6_case T06-X11-QT6-CANDIDATE-NAVIGATION \
    chichi77-keykey-bopomofo \
    妐 '5j/ ' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space End Home Page_Down Down Return
fi
if case_selected T06-X11-QT6-CANDIDATE-MOUSE; then
  set_bopomofo_layout Standard
  set_candidate_window_style Vertical
  run_qt6_case T06-X11-QT6-CANDIDATE-MOUSE chichi77-keykey-bopomofo \
    鐘 '5j/ ' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space click-candidate-2
fi
if case_selected T06-X11-QT6-CANDIDATE-HORIZONTAL; then
  set_bopomofo_layout Standard
  set_candidate_window_style Horizontal
  run_qt6_case T06-X11-QT6-CANDIDATE-HORIZONTAL \
    chichi77-keykey-bopomofo \
    妐 ' 5j/ ' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' \
    5 j slash space End Home Page_Down Page_Up Right Left space Down Return
fi
if case_selected T07-X11-QT6-ASSOCIATED-PHRASE; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections McBopomofo
  run_qt6_case T07-X11-QT6-ASSOCIATED-PHRASE \
    chichi77-keykey-bopomofo \
    今天 'rup 1!' 'ㄐ,ㄐㄧ,ㄐㄧㄣ' r u p space 1 shift+1
fi
if case_selected T07-X11-QT6-ASSOCIATED-PHRASE-CATEGORY; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections history
  run_qt6_case T07-X11-QT6-ASSOCIATED-PHRASE-CATEGORY \
    chichi77-keykey-bopomofo \
    臺灣史 'w962!' 'ㄊ,ㄊㄞ,ㄊㄞˊ' w 9 6 2 shift+1
fi
if case_selected T07-X11-QT6-ASSOCIATED-PHRASE-DISABLED; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_qt6_case T07-X11-QT6-ASSOCIATED-PHRASE-DISABLED \
    chichi77-keykey-bopomofo \
    '臺!' 'w962!' 'ㄊ,ㄊㄞ,ㄊㄞˊ' w 9 6 2 shift+1
  set_associated_phrase_collections ''
fi
if case_selected T07-X11-QT6-ASSOCIATED-PHRASE-LEGACY-CONFIG; then
  set_bopomofo_layout Standard
  associated_phrase_collections=government
  write_legacy_keykey_config
  reload_keykey_config
  run_qt6_case T07-X11-QT6-ASSOCIATED-PHRASE-LEGACY-CONFIG \
    chichi77-keykey-bopomofo \
    中程計畫 '5j/ 1!' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space 1 shift+1
  set_associated_phrase_collections ''
fi
if case_selected T07-X11-QT6-ASSOCIATED-PHRASE-DBUS-PERSISTENCE; then
  set_bopomofo_layout Standard
  associated_phrase_collections=government
  persistence_case_dir="$KEYKEY_E2E_ARTIFACT_DIR/"
  persistence_case_dir+=T07-X11-QT6-ASSOCIATED-PHRASE-DBUS-PERSISTENCE
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
  run_qt6_case T07-X11-QT6-ASSOCIATED-PHRASE-DBUS-PERSISTENCE \
    chichi77-keykey-bopomofo \
    中程計畫 '5j/ 1!' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' 5 j slash space 1 shift+1
  set_associated_phrase_collections ''
fi
if case_selected T08-X11-QT6-CHINESE-ENGLISH-MODE; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  set_toggle_with_control_backslash True
  run_qt6_case T08-X11-QT6-CHINESE-ENGLISH-MODE \
    chichi77-keykey-bopomofo \
    '5j/aBａ！　文abcde麻' '55j/aB a!  jp61abcdea861' \
    'ㄓ,ㄨ,ㄨㄣ,ㄨㄣˊ,ㄇ,ㄇㄚ,ㄇㄚˊ' \
    5 ctrl+backslash 5 j slash a Caps_Lock b Caps_Lock \
    shift+space a shift+1 space shift+space \
    ctrl+backslash j p 6 1 \
    shift a b c shift-down wait-500ms shift-up d e shift a 8 6 1
fi
if case_selected T08-X11-QT6-CONTROL-BACKSLASH-DISABLED; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  set_toggle_with_control_backslash False
  run_qt6_case T08-X11-QT6-CONTROL-BACKSLASH-DISABLED \
    chichi77-keykey-bopomofo \
    中 '5j/ 1' 'ㄓ,ㄓㄨ,ㄓㄨㄥ' \
    5 ctrl+backslash j slash space 1
  set_toggle_with_control_backslash True
fi
if case_selected T08-X11-QT6-FULL-WIDTH; then
  set_bopomofo_layout Standard
  run_qt6_case T08-X11-QT6-FULL-WIDTH chichi77-keykey-bopomofo \
    'Ａ！～　' ' A!~ ' '' shift+space shift+a shift+1 shift+grave space
fi
if case_selected T08-X11-QT6-TRADITIONAL-TO-SIMPLIFIED; then
  set_bopomofo_layout Standard
  set_traditional_to_simplified True
  run_qt6_case T08-X11-QT6-TRADITIONAL-TO-SIMPLIFIED \
    chichi77-keykey-bopomofo \
    台湾 'w962j0 1' 'ㄊ,ㄊㄞ,ㄊㄞˊ,ㄨ,ㄨㄢ' \
    w 9 6 2 j 0 space 1
  set_traditional_to_simplified False
fi
if case_selected T09-X11-QT6-MODIFIER-PASSTHROUGH; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  set_toggle_with_control_backslash True
  run_qt6_case T09-X11-QT6-MODIFIER-PASSTHROUGH \
    chichi77-keykey-bopomofo \
    'xff中f文' 'x5fj/ f1jp6f1' \
    'ㄓ,ㄓㄨ,ㄓㄨㄥ,ㄨ,ㄨㄣ,ㄨㄣˊ' \
    ctrl+backslash \
    ctrl+a BackSpace x \
    ctrl+backslash \
    5 ctrl+c alt+f j slash space ctrl+c alt+f 1 \
    j p 6 ctrl+c alt+f 1
fi
if case_selected T10-X11-QT6-INPUT-CONTEXT-ISOLATION; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_qt6_focus_case T10-X11-QT6-INPUT-CONTEXT-ISOLATION
fi
if case_selected T10-X11-QT6-MULTI-APP-ISOLATION; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections ''
  run_qt6_multi_app_case T10-X11-QT6-MULTI-APP-ISOLATION
fi
if case_selected T11-X11-QT6-EDITING-SENSITIVE-READONLY; then
  set_bopomofo_layout Standard
  set_associated_phrase_collections McBopomofo
  run_qt6_editing_case T11-X11-QT6-EDITING-SENSITIVE-READONLY
  set_associated_phrase_collections ''
fi
if case_selected T12-X11-QT6-SYMBOL-LIST; then
  set_bopomofo_layout Standard
  set_candidate_window_style Vertical
  run_qt6_case T12-X11-QT6-SYMBOL-LIST chichi77-keykey-bopomofo \
    ， '1' ， ctrl+0 1
fi
if case_selected T12-X11-QT6-SYMBOL-LIST-MOUSE; then
  set_bopomofo_layout Standard
  set_candidate_window_style Vertical
  run_qt6_case T12-X11-QT6-SYMBOL-LIST-MOUSE \
    chichi77-keykey-bopomofo '，!' '!' '' \
    ctrl+0 click-candidate-1 wait-500ms shift+1
fi
test_status=passed

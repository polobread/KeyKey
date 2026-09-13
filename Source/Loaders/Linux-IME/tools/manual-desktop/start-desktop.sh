#!/usr/bin/env bash
# Local GNOME/X11 typing desktop; see docs/manual-desktop.md.
set -euo pipefail

tool_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
linux_root=$(cd -- "$tool_dir/../.." && pwd)
session_root=${KEYKEY_MANUAL_DESKTOP_DIR:-$linux_root/out/manual-vnc}
desktop_display=${KEYKEY_MANUAL_DISPLAY:-:21}
desktop_port=${KEYKEY_MANUAL_PORT:-6080}

if [[ ${1:-} == --help ]]; then
    printf '%s\n' \
        'Run this script in a user systemd service; see docs/manual-desktop.md.' \
        'Defaults: display :21, localhost port 6080, out/manual-vnc state.' \
        'Overrides: KEYKEY_MANUAL_DISPLAY, KEYKEY_MANUAL_PORT, KEYKEY_MANUAL_DESKTOP_DIR.'
    exit 0
fi
if [[ $# -gt 1 || ( $# == 1 && $1 != --session ) ]]; then
    printf 'Unknown argument; use --help.\n' >&2
    exit 2
fi
if [[ $session_root != /* || ! $desktop_display =~ ^:[0-9]+$ ||
      ! $desktop_port =~ ^[1-9][0-9]{3,4}$ ]]; then
    printf 'Use an absolute state directory, :NUMBER display and port 1024-65535.\n' >&2
    exit 2
fi
if (( desktop_port < 1024 || desktop_port > 65535 )); then
    printf 'Port must be between 1024 and 65535.\n' >&2
    exit 2
fi
if (( ${#session_root} + 17 > 107 )); then
    printf 'State directory is too long for the VNC Unix socket; choose a shorter path.\n' >&2
    exit 2
fi

if [[ ${1:-} != --session ]]; then
    for dependency in Xtigervnc gnome-shell gedit fcitx5 fcitx5-remote \
        websockify xauth mcookie xdpyinfo xprop xdotool setxkbmap \
        dbus-run-session dbus-update-activation-environment gsettings curl; do
        if ! command -v "$dependency" >/dev/null; then
            printf 'Missing %s; install the packages in docs/manual-desktop.md.\n' "$dependency" >&2
            exit 1
        fi
    done
    if [[ -e /tmp/.X11-unix/X${desktop_display#:} ]]; then
        printf 'Display %s already exists; reuse the desktop or choose another display.\n' "$desktop_display" >&2
        exit 1
    fi
    if [[ ! -f /usr/share/novnc/vnc.html ]]; then
        printf 'Missing /usr/share/novnc/vnc.html.\n' >&2
        exit 1
    fi
    unset DBUS_SESSION_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE
    exec dbus-run-session -- bash "$0" --session
fi

umask 077
mkdir -p "$session_root/runtime" "$session_root/logs" "$session_root/data" \
    "$session_root/cache" "$session_root/config/fcitx5"
chmod 700 "$session_root/runtime"
export XDG_RUNTIME_DIR="$session_root/runtime"
export XDG_CONFIG_HOME="$session_root/config"
export XDG_DATA_HOME="$session_root/data"
export XDG_CACHE_HOME="$session_root/cache"
export XDG_DATA_DIRS=/usr/local/share:/usr/share
export DISPLAY="$desktop_display" XAUTHORITY="$session_root/runtime/Xauthority"
export XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=GNOME GNOME_SHELL_SESSION_MODE=user
export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx
export GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 LANG=C.UTF-8
unset WAYLAND_DISPLAY SESSION_MANAGER AT_SPI_BUS_ADDRESS

if [[ ! -e $XDG_CONFIG_HOME/fcitx5/profile ]]; then
    install -m 600 "$linux_root/tests/fixtures/fcitx5-profile" "$XDG_CONFIG_HOME/fcitx5/profile"
fi
if [[ ! -e $XDG_CONFIG_HOME/fcitx5/config ]]; then
    install -m 600 "$tool_dir/fcitx5-config" "$XDG_CONFIG_HOME/fcitx5/config"
fi
printf '%s\n' "$DBUS_SESSION_BUS_ADDRESS" > "$session_root/runtime/bus-address"
printf '%s\n' "$DISPLAY" > "$session_root/runtime/display"

pids=()
cleanup() {
    trap - EXIT INT TERM
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    wait || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

await_ready() {
    local label=$1 pid=$2
    shift 2
    for ((attempt=0; attempt<150; ++attempt)); do
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        if "$@"; then return 0; fi
        sleep 0.1
    done
    printf '%s did not become ready; see %s/logs.\n' "$label" "$session_root" >&2
    return 1
}
x_ready() { xdpyinfo >/dev/null 2>&1; }
wm_ready() { xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id'; }
addon_ready() { grep -q chichi77-keykey.so "/proc/$fcitx_pid/maps"; }
editor_ready() {
    editor_window=$(xdotool search --onlyvisible --class '^Gedit$' 2>/dev/null | head -n 1 || true)
    [[ -n $editor_window ]] && xprop -id "$editor_window" _NET_WM_DESKTOP 2>/dev/null | grep -q CARDINAL
}
focus_ready() {
    xdotool windowactivate "$editor_window" 2>/dev/null || return 1
    xdotool windowfocus "$editor_window" 2>/dev/null || return 1
    [[ $(xdotool getwindowfocus 2>/dev/null) == "$editor_window" ]]
}
ime_ready() {
    fcitx5-remote -o
    fcitx5-remote -s chichi77-keykey-bopomofo
    [[ $(fcitx5-remote -n) == chichi77-keykey-bopomofo ]]
}
web_ready() { curl --noproxy '*' --max-time 1 -fsS -o /dev/null "http://127.0.0.1:$desktop_port/vnc.html" 2>/dev/null; }

xauth -f "$XAUTHORITY" add "$DISPLAY" . "$(mcookie)"
Xtigervnc "$DISPLAY" -geometry 1280x800 -depth 24 -nolisten tcp \
    -auth "$XAUTHORITY" -rfbport -1 \
    -rfbunixpath "$session_root/runtime/vnc.sock" -rfbunixmode 0600 \
    -SecurityTypes None -AlwaysShared -desktop 'Ubuntu 24.04 - 琦琦注音測試' \
    >> "$session_root/logs/xvnc.log" 2>&1 &
pids+=("$!")
await_ready X11 "${pids[0]}" x_ready
setxkbmap us
dbus-update-activation-environment DISPLAY XAUTHORITY XDG_RUNTIME_DIR \
    XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_DATA_DIRS \
    XDG_SESSION_TYPE XDG_CURRENT_DESKTOP GTK_IM_MODULE QT_IM_MODULE \
    XMODIFIERS GDK_BACKEND LIBGL_ALWAYS_SOFTWARE LANG

gnome-shell --x11 --sm-disable >> "$session_root/logs/gnome-shell.log" 2>&1 &
pids+=("$!")
await_ready GNOME "${pids[1]}" wm_ready

fcitx5 --disable wayland,waylandim >> "$session_root/logs/fcitx5.log" 2>&1 &
fcitx_pid=$!
pids+=("$fcitx_pid")
await_ready 'Fcitx addon' "$fcitx_pid" addon_ready

if [[ ! -e $session_root/editor-initialized ]]; then
    gsettings set org.gnome.gedit.preferences.editor use-default-font false
    gsettings set org.gnome.gedit.preferences.editor editor-font 'Monospace 18'
    touch "$session_root/editor-initialized"
fi
gedit --standalone --new-window >> "$session_root/logs/gedit.log" 2>&1 &
pids+=("$!")
await_ready gedit "${pids[3]}" editor_ready
await_ready 'gedit focus' "${pids[3]}" focus_ready
await_ready '琦琦注音' "$fcitx_pid" ime_ready

websockify --web=/usr/share/novnc \
    --auth-plugin=ExpectOrigin \
    --auth-source="http://localhost:$desktop_port http://127.0.0.1:$desktop_port" \
    --unix-target="$session_root/runtime/vnc.sock" "127.0.0.1:$desktop_port" \
    >> "$session_root/logs/websockify.log" 2>&1 &
pids+=("$!")
await_ready 'Browser connection' "${pids[4]}" web_ready
printf 'Desktop ready: http://localhost:%s/vnc.html?autoconnect=true&resize=scale\n' "$desktop_port"
wait -n "${pids[@]}"

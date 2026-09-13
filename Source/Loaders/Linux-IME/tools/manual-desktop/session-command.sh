#!/usr/bin/env bash
set -euo pipefail
tool_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
linux_root=$(cd -- "$tool_dir/../.." && pwd)
session_root=${KEYKEY_MANUAL_DESKTOP_DIR:-$linux_root/out/manual-vnc}
if [[ $# == 0 || ${1:-} == --help ]]; then
    printf 'Usage: session-command.sh COMMAND [ARGUMENTS...]\n'
    exit 0
fi
if [[ ! -r $session_root/runtime/bus-address ]]; then
    printf 'No desktop session at %s; see docs/manual-desktop.md.\n' "$session_root" >&2
    exit 1
fi
export XDG_RUNTIME_DIR="$session_root/runtime" XDG_CONFIG_HOME="$session_root/config"
export XDG_DATA_HOME="$session_root/data" XDG_CACHE_HOME="$session_root/cache"
export XDG_DATA_DIRS=/usr/local/share:/usr/share
export DISPLAY=${KEYKEY_MANUAL_DISPLAY:-:21} XAUTHORITY="$session_root/runtime/Xauthority"
if [[ -r $session_root/runtime/display ]]; then
    IFS= read -r DISPLAY < "$session_root/runtime/display"
fi
export DBUS_SESSION_BUS_ADDRESS
IFS= read -r DBUS_SESSION_BUS_ADDRESS < "$session_root/runtime/bus-address"
export XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=GNOME
export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx
export GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 LANG=C.UTF-8
unset WAYLAND_DISPLAY SESSION_MANAGER AT_SPI_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE
if ! dbus-send --session --print-reply --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
    printf 'Desktop session is no longer running; start it before using this command.\n' >&2
    exit 1
fi
exec "$@"

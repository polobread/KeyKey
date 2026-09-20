#!/usr/bin/env bash
# Enable or disable the separately packaged GNOME panel for the current user.
set -euo pipefail

uuid=kimpanel@kde.org
system_extension=/usr/share/gnome-shell/extensions/$uuid
user_extension=${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$uuid

case ${1:-} in
  enable)
    [[ $# == 1 ]] || exit 2
    if [[ ! -f $system_extension/extension.js ]]; then
      echo 'The system GNOME panel package is not installed.' >&2
      exit 1
    fi
    if [[ -e $user_extension ]]; then
      echo "A user-local $uuid extension shadows the system package: $user_extension" >&2
      echo 'Move it aside and log in again before enabling the packaged panel.' >&2
      exit 1
    fi
    if ! gnome-extensions enable "$uuid"; then
      echo 'Log out and in to let GNOME discover the installed extension, then retry.' >&2
      exit 1
    fi
    ;;
  disable)
    [[ $# == 1 ]] || exit 2
    gnome-extensions disable "$uuid"
    ;;
  status)
    [[ $# == 1 ]] || exit 2
    if [[ -e $user_extension ]]; then
      echo "User-local extension shadows package: $user_extension"
    fi
    gnome-extensions info "$uuid"
    ;;
  *)
    echo 'Usage: keykey-gnome-panel enable|disable|status' >&2
    exit 2
    ;;
esac

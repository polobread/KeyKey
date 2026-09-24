#!/usr/bin/env bash
# Runs inside the Ubuntu 24.04 VM after gnome-vm.sh copies package and host files.
set -euo pipefail

# shellcheck disable=SC1091
if [[ $(. /etc/os-release; echo "$VERSION_ID") != 24.04 ||
      $(dpkg --print-architecture) != amd64 ]]; then
  echo 'Expected Ubuntu 24.04 amd64 guest.' >&2
  exit 1
fi
if [[ $(id -un) != keykey ]]; then
  echo 'Expected the keykey VM user.' >&2
  exit 1
fi

sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ubuntu-desktop-minimal gdm3 gedit gnome-text-editor \
  fcitx5 fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 \
  fcitx5-frontend-qt6 fcitx5-config-qt qt6-wayland \
  fonts-wqy-zenhei libcanberra-pulse x11-utils xdotool qemu-guest-agent \
  /tmp/chichi77-keykey-data_1.2.10-1+ubuntu24.04_all.deb \
  /tmp/fcitx5-chichi77-keykey_1.2.10-1+ubuntu24.04_amd64.deb \
  /tmp/gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_all.deb

# The cloud image uses networkd. The minimal desktop's Netplan defaults can
# select NetworkManager even though --no-install-recommends does not install it.
printf '%s\n' 'network:' '  version: 2' '  renderer: networkd' | \
  sudo tee /etc/netplan/99-keykey-vm.yaml >/dev/null
sudo chmod 600 /etc/netplan/99-keykey-vm.yaml
sudo netplan generate

host_dir=$HOME/.local/libexec/keykey-e2e
mkdir -p "$host_dir"
for host in gtk3 gtk4 qt6; do
  install -m 755 "/tmp/keykey_linux_${host}_e2e_host" \
    "$host_dir/keykey_linux_${host}_e2e_host"
done

mkdir -p ~/.config/autostart ~/.config/fcitx5 ~/.config/environment.d \
  ~/.config/gtk-3.0 ~/.config/gtk-4.0
install -m 600 /tmp/keykey-fcitx5-profile ~/.config/fcitx5/profile
install -m 644 /usr/share/applications/org.fcitx.Fcitx5.desktop \
  ~/.config/autostart/org.fcitx.Fcitx5.desktop
printf '%s\n' 'XMODIFIERS=@im=fcitx' 'QT_IM_MODULE=fcitx' \
  > ~/.config/environment.d/50-keykey-ime.conf
printf '%s\n' '[Settings]' 'gtk-im-module=fcitx' \
  > ~/.config/gtk-3.0/settings.ini
printf '%s\n' '[Settings]' 'gtk-im-module=fcitx' \
  > ~/.config/gtk-4.0/settings.ini

sudo sed -i \
  -e 's/^#  AutomaticLoginEnable = true/AutomaticLoginEnable = true/' \
  -e 's/^#  AutomaticLogin = user1/AutomaticLogin = keykey/' \
  /etc/gdm3/custom.conf
if systemctl is-active --quiet gdm3; then
  sudo systemctl restart gdm3
else
  sudo systemctl start gdm3
fi

ready=false
for ((attempt=0; attempt<60; attempt++)); do
  while read -r fcitx_pid; do
    if [[ -r /proc/$fcitx_pid/maps ]] && \
       grep -q /fcitx5/chichi77-keykey.so "/proc/$fcitx_pid/maps"; then
      ready=true
      break
    fi
  done < <(pgrep -u keykey -x fcitx5 || true)
  [[ $ready == true ]] && break
  sleep 1
done
if [[ $ready != true ]]; then
  echo 'GNOME session did not load the installed Fcitx addon.' >&2
  exit 1
fi
if ! loginctl list-sessions --no-legend | while read -r session _; do
  [[ $(loginctl show-session "$session" -p Type --value) == wayland &&
     $(loginctl show-session "$session" -p State --value) == active ]] && exit 0
done; then
  echo 'No active Wayland login session.' >&2
  exit 1
fi
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \
  gsettings set org.gnome.settings-daemon.plugins.xsettings overrides \
  "{'Gtk/IMModule':<'fcitx'>}"
if [[ -e $HOME/.local/share/gnome-shell/extensions/kimpanel@kde.org ]]; then
  echo 'A user-local Kimpanel copy shadows the installed panel package.' >&2
  exit 1
fi
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \
  keykey-gnome-panel enable
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \
  keykey-gnome-panel status | grep -F 'State: ACTIVE'
echo 'GNOME Wayland guest ready with installed KeyKey addon and candidate panel.'

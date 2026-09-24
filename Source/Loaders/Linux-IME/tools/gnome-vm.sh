#!/usr/bin/env bash
# Ubuntu 24.04 GNOME guest for local Wayland validation. Run from a normal WSL2 shell.
set -euo pipefail

tool_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
linux_root=$(cd -- "$tool_dir/.." && pwd)
vm_dir=$linux_root/out/gnome-vm
image_url=https://cloud-images.ubuntu.com/noble/current
image_name=noble-server-cloudimg-amd64.img
ssh_port=2222
vnc_display=2

usage() {
  echo "Usage: $0 prepare|start|provision|status|ssh [command ...]|stop" >&2
  exit 2
}

running() {
  [[ -f $vm_dir/qemu.pid ]] && kill -0 "$(cat "$vm_dir/qemu.pid")" 2>/dev/null
}

prepare() {
  "$tool_dir/check-wsl-vm-host.sh"
  for program in curl cloud-localds ssh-keygen; do
    command -v "$program" >/dev/null || { echo "Missing $program" >&2; exit 1; }
  done
  mkdir -p "$vm_dir"
  if [[ ! -f $vm_dir/$image_name ]]; then
    curl -fL --retry 3 "$image_url/$image_name" -o "$vm_dir/$image_name.part"
    mv -- "$vm_dir/$image_name.part" "$vm_dir/$image_name"
  fi
  curl -fL --retry 3 "$image_url/SHA256SUMS" -o "$vm_dir/SHA256SUMS.part"
  mv -- "$vm_dir/SHA256SUMS.part" "$vm_dir/SHA256SUMS"
  (cd "$vm_dir" && sha256sum --check --ignore-missing SHA256SUMS)
  if [[ ! -f $vm_dir/id_ed25519 ]]; then
    ssh-keygen -q -t ed25519 -N '' -C keykey-gnome-vm -f "$vm_dir/id_ed25519"
  fi
  if [[ ! -f $vm_dir/seed.img ]]; then
    cat > "$vm_dir/user-data" <<EOF
#cloud-config
users:
  - name: keykey
    groups: [adm, sudo, video, input]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $(cat "$vm_dir/id_ed25519.pub")
ssh_pwauth: false
disable_root: true
package_update: true
packages:
  - openssh-server
EOF
    cat > "$vm_dir/meta-data" <<EOF
instance-id: keykey-gnome-$(date +%Y%m%d)-01
local-hostname: keykey-gnome
EOF
    cloud-localds "$vm_dir/seed.img" "$vm_dir/user-data" "$vm_dir/meta-data"
  fi
  if [[ ! -f $vm_dir/guest.qcow2 ]]; then
    qemu-img create -f qcow2 -F qcow2 -b "$vm_dir/$image_name" "$vm_dir/guest.qcow2"
    qemu-img resize "$vm_dir/guest.qcow2" 40G
  fi
  if [[ ! -f $vm_dir/ovmf-vars.fd ]]; then
    cp -- /usr/share/OVMF/OVMF_VARS_4M.fd "$vm_dir/ovmf-vars.fd"
  fi
  echo "Guest files ready in $vm_dir"
}

guest_ssh() {
  ssh -i "$vm_dir/id_ed25519" -p "$ssh_port" \
    -o UserKnownHostsFile="$vm_dir/known_hosts" \
    -o StrictHostKeyChecking=accept-new -o BatchMode=yes \
    keykey@127.0.0.1 "$@"
}

provision() {
  if ! running; then
    echo 'Start the guest before provisioning.' >&2
    exit 1
  fi
  local package_dir=$linux_root/out/package-build/ubuntu-24.04-amd64-release-candidate
  local panel_dir=$linux_root/out/packages/ubuntu-24.04-amd64/release-candidate
  local host_dir=$linux_root/out/build/ubuntu-24.04-package-amd64
  local files=(
    "$package_dir/chichi77-keykey-data_1.2.10-1+ubuntu24.04_all.deb"
    "$package_dir/fcitx5-chichi77-keykey_1.2.10-1+ubuntu24.04_amd64.deb"
    "$panel_dir/gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_all.deb"
    "$host_dir/keykey_linux_gtk3_e2e_host"
    "$host_dir/keykey_linux_gtk4_e2e_host"
    "$host_dir/keykey_linux_qt6_e2e_host"
    "$linux_root/tests/fixtures/fcitx5-profile"
  )
  local file
  for file in "${files[@]}"; do
    [[ -f $file ]] || { echo "Missing build artifact: $file" >&2; exit 1; }
  done
  scp -i "$vm_dir/id_ed25519" -P "$ssh_port" \
    -o UserKnownHostsFile="$vm_dir/known_hosts" \
    -o StrictHostKeyChecking=accept-new -o BatchMode=yes \
    "${files[@]}" keykey@127.0.0.1:/tmp/
  guest_ssh mv /tmp/fcitx5-profile /tmp/keykey-fcitx5-profile
  guest_ssh bash -s < "$tool_dir/gnome-vm-setup-guest.sh"
}

case ${1:-} in
  prepare) [[ $# == 1 ]] || usage; prepare ;;
  start)
    [[ $# == 1 ]] || usage
    if running; then echo "Guest already running: PID $(cat "$vm_dir/qemu.pid")"; exit 0; fi
    [[ -f $vm_dir/guest.qcow2 && -f $vm_dir/seed.img ]] || prepare
    "$tool_dir/check-wsl-vm-host.sh"
    rm -f -- "$vm_dir/qmp.sock" "$vm_dir/qemu.pid"
    qemu-system-x86_64 -name keykey-gnome -machine q35,accel=kvm -cpu host \
      -smp 4 -m 6144 \
      -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
      -drive if=pflash,format=raw,file="$vm_dir/ovmf-vars.fd" \
      -drive if=virtio,format=qcow2,file="$vm_dir/guest.qcow2" \
      -drive if=virtio,format=raw,file="$vm_dir/seed.img" \
      -vga none -device virtio-vga,id=keykey-display,max_outputs=2 \
      -netdev user,id=net0,hostfwd=tcp:127.0.0.1:"$ssh_port"-:22 \
      -device virtio-net-pci,netdev=net0 \
      -vnc 127.0.0.1:"$vnc_display" \
      -serial file:"$vm_dir/serial.log" \
      -qmp unix:"$vm_dir/qmp.sock",server=on,wait=off \
      -pidfile "$vm_dir/qemu.pid" -daemonize
    echo "Guest started: PID $(cat "$vm_dir/qemu.pid"), SSH port $ssh_port, VNC port $((5900 + vnc_display))"
    ;;
  provision) [[ $# == 1 ]] || usage; provision ;;
  status)
    [[ $# == 1 ]] || usage
    if running; then
      echo "Guest running: PID $(cat "$vm_dir/qemu.pid"), SSH port $ssh_port, VNC port $((5900 + vnc_display))"
    else
      echo 'Guest stopped'
      exit 1
    fi
    ;;
  ssh) shift; guest_ssh "$@" ;;
  stop)
    [[ $# == 1 ]] || usage
    if running; then guest_ssh sudo systemctl poweroff; else echo 'Guest already stopped'; fi
    ;;
  *) usage ;;
esac

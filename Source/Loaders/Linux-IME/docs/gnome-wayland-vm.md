# Ubuntu 24.04 GNOME Wayland VM

This dedicated guest tests an installed Fcitx 5 addon in a complete GNOME login
session. It is separate from WSLg, Xvfb, and the user's desktop. Run these
commands from the repository root in a normal WSL2 Ubuntu shell with the
checkout on the WSL Linux filesystem. The guest is disposable; save any work
before restarting its desktop or replacing packages.

## Prepare and start

Install host tools and confirm KVM access:

```sh
sudo apt-get install qemu-system-x86 qemu-utils ovmf cloud-image-utils curl
Source/Loaders/Linux-IME/tools/check-wsl-vm-host.sh
Source/Loaders/Linux-IME/tools/gnome-vm.sh prepare
Source/Loaders/Linux-IME/tools/gnome-vm.sh start
Source/Loaders/Linux-IME/tools/gnome-vm.sh ssh cloud-init status --wait
```

## Install the candidate package

Build the current candidate before provisioning; old files in `out/` do not
become a new version when source code changes.

```sh
Source/Loaders/Linux-IME/ci/run-debian-package.sh ubuntu-24.04
Source/Loaders/Linux-IME/tools/gnome-vm.sh provision
Source/Loaders/Linux-IME/tools/gnome-vm.sh ssh loginctl list-sessions
Source/Loaders/Linux-IME/tools/gnome-vm.sh ssh pgrep -a fcitx5
Source/Loaders/Linux-IME/tools/gnome-vm.sh status
```

Record package versions, hashes, the active Wayland login, loaded addon, and
panel provider. Verify that each toolkit's Fcitx frontend is installed. The
presence of an SSH connection or a running Fcitx process does not prove that
the intended input context is active.

## Focused typing checks

```sh
Source/Loaders/Linux-IME/tools/gnome-vm-wayland-smoke.py --case T06-navigation --mode gtk3-xwayland
Source/Loaders/Linux-IME/tools/gnome-vm-real-app-smoke.py --mode wayland --mode xwayland
Source/Loaders/Linux-IME/tools/gnome-vm-focus-smoke.py
Source/Loaders/Linux-IME/tools/gnome-vm-editing-smoke.py --phase positive --phase negative --phase extended
Source/Loaders/Linux-IME/tools/gnome-vm-multi-app-smoke.py
Source/Loaders/Linux-IME/tools/gnome-vm-wayland-smoke.py --case T12-symbol-mouse
Source/Loaders/Linux-IME/tools/gnome-vm-recovery-smoke.py
```

Select cases affected by the change. Run `gnome-vm-wayland-smoke.py` without
filters only when the full frontend matrix is required. The runner supports
repeated `--case` and `--mode` filters, sends physical QMP keyboard events, and
checks preedit plus exact application text. `keyboard-us` receives the same
keys as a literal negative control. Native Wayland, XWayland, direct Fcitx,
and GNOME's default GTK bridge are distinct paths and require separate results.

For browser-specific work, the guest needs Firefox Snap and Epiphany:

```sh
Source/Loaders/Linux-IME/tools/gnome-vm.sh ssh 'snap list firefox || sudo snap install firefox'
Source/Loaders/Linux-IME/tools/gnome-vm.sh ssh 'sudo apt-get install -y epiphany-browser'
Source/Loaders/Linux-IME/tools/gnome-vm-browser-smoke.py
```

Reports and QMP captures are written to ignored `out/gnome-vm/`; event traces
and text remain inside the disposable guest. Preserve failures and environment
metadata with the candidate version. Do not carry forward pass counts from an
older core, package, or panel.

## Candidate popup edges and displays

The launcher exposes two virtio outputs. Inspect guest DRM connector names
before enabling a second display; the example connector can vary by QEMU.
Restarting GDM ends the guest's desktop session.

```sh
Source/Loaders/Linux-IME/tools/gnome-vm.sh ssh 'sudo sh -c "echo on > /sys/class/drm/card1-Virtual-2/status"'
Source/Loaders/Linux-IME/tools/gnome-vm.sh ssh 'sudo systemctl restart gdm3'
Source/Loaders/Linux-IME/tools/gnome-vm-popup-smoke.py --panel kimpanel --mouse
Source/Loaders/Linux-IME/tools/gnome-vm-multimonitor-smoke.py --panel kimpanel --mouse
```

Check display placement, mixed DPI, popup edges, real pointer selection,
clearance, and literal controls. Record Kimpanel bus ownership and the loaded
extension path; use `--panel classic-ui` separately when testing Classic UI.
See the [panel integration guide](gnome-candidate-panel.md) and
[panel package README](../gnome-panel/README.md) for renderer and licensing
boundaries. Virtual outputs do not establish physical monitor or hotplug
acceptance.

## Stop and resume

```sh
Source/Loaders/Linux-IME/tools/gnome-vm.sh stop
Source/Loaders/Linux-IME/tools/gnome-vm.sh start
```

An explicit desktop logout/login, a guest restart, Fcitx restart, client closure,
and focus change exercise different lifecycle paths. Record them separately.
The [Guanyinma adapter guide](../../../../docs/GUANYINMA_LINUX_ADAPTER.md)
describes current input and data contracts. VM acceptance does not establish
FreeBSD behavior, every application/sandbox, or release readiness.

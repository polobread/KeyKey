# Ubuntu 24.04 GNOME Wayland VM

This local guest tests the installed Fcitx 5 addon in a complete GNOME login
session. It is separate from WSLg and from the Xvfb container gates. Run the
commands from the repository root in a normal WSL2 Ubuntu shell, with the
checkout on the WSL Linux filesystem.

## Prepare and start

Install the host tools and confirm that the current user can access KVM:

```sh
sudo apt-get install qemu-system-x86 qemu-utils ovmf cloud-image-utils curl
Source/Loaders/Linux-IME/tools/check-wsl-vm-host.sh
Source/Loaders/Linux-IME/tools/gnome-vm.sh prepare
Source/Loaders/Linux-IME/tools/gnome-vm.sh start
Source/Loaders/Linux-IME/tools/gnome-vm.sh ssh cloud-init status --wait
```

`prepare` downloads the official Ubuntu Noble amd64 cloud image and checks it
against Ubuntu's `SHA256SUMS`, then creates a 40 GB copy-on-write guest disk,
NoCloud seed, SSH key and OVMF variable file under the ignored
`Source/Loaders/Linux-IME/out/gnome-vm/`. The image download is about 600 MB;
GNOME packages require further network and disk space. The guest uses 4 vCPUs,
6 GB RAM and KVM. SSH is forwarded only to `127.0.0.1:2222`; QEMU VNC is
bound only to `127.0.0.1:5902`. The VM SSH key has access to a passwordless
sudo account inside this disposable guest. Keep the private key and guest disk
in ignored `out/` and do not publish them.

## Install the tested package and desktop

First build the Ubuntu 24.04 release candidate package and three toolkit test
hosts with the existing package gate:

```sh
Source/Loaders/Linux-IME/ci/run-debian-package.sh ubuntu-24.04
Source/Loaders/Linux-IME/tools/gnome-vm.sh provision
```

`provision` copies the resulting two `.deb` files, the GTK 3/GTK 4/Qt 6 test
hosts and the test Fcitx profile into the guest. It installs Ubuntu's minimal
GNOME desktop, GDM, Fcitx 5, toolkit frontends and Qt Wayland plugin; enables
automatic login for the guest user; configures Fcitx autostart and restarts
GDM. The host binaries are installed under the guest user's
`~/.local/libexec/keykey-e2e/`, so smoke tests still work after a VM reboot.
The current package filenames are `1.2.8-1+ubuntu24.04`, even when the
development branch is `v1.2.9`; verify the package version and hashes for
each release candidate. Provisioning is repeatable but interrupts any active
guest desktop session. It also fixes the guest's Netplan renderer to the
installed `systemd-networkd`: the minimal GNOME package set otherwise selects
NetworkManager without installing its service, leaving `enp0s2` DOWN after
the next VM boot and delaying `systemd-networkd-wait-online` by two minutes.

Check the session and addon before testing:

```sh
Source/Loaders/Linux-IME/tools/gnome-vm.sh ssh loginctl list-sessions
Source/Loaders/Linux-IME/tools/gnome-vm.sh ssh pgrep -a fcitx5
Source/Loaders/Linux-IME/tools/gnome-vm.sh status
```

## Native Wayland typing smoke

```sh
Source/Loaders/Linux-IME/tools/gnome-vm-wayland-smoke.py
```

The runner requires an active Wayland login, the installed
`chichi77-keykey.so`, Fcitx Wayland and IBus frontends, and the three guest
test hosts. It forces native Wayland for GTK 3/4 and Qt 6, sends actual VM
keyboard events through QMP, checks the three Bopomofo preedit states and
exact committed `中`, switches to `keyboard-us`, and checks literal `5j/ 1`.
GTK 3/4 are each exercised twice: with their Fcitx IM module and with
`GTK_IM_MODULE` unset, which tests GNOME's text-input-v3/IBus bridge. The
runner writes event traces and final text under `/tmp/keykey-wayland-smoke-*`
inside the guest. A passing smoke is a narrow functional result: it does not
establish candidate positioning, visual timing, XWayland behavior, browser or
sandbox behavior, full T01–T12 coverage, or release readiness.

On 2026-09-20 a separate QMP screenshot during the GTK 3 candidate stage
showed all nine vertical candidates next to the focused entry at the guest's
1024×768 virtual resolution. Fcitx also displayed a Wayland diagnostic
notification recommending the GNOME Shell Input Method Panel extension. The
before/candidate PNG files are in the ignored `out/gnome-vm/` directory; they
are one visual sample, not the planned popup geometry and timing sweep.

The QMP socket and KVM device can be hidden from a restricted process even
when the ordinary WSL user can access them. In that case run the scripts from
a normal WSL shell or grant that process access to the local VM socket. Do not
change `/dev/kvm` or socket permissions merely to bypass process isolation.

The guest has also been stopped and started again after provisioning; the
Wayland login, SSH and installed addon recovered, and all five smoke cases
passed again. This checks a VM power cycle, not a user logout/login cycle.

To stop or resume the guest without deleting its disk:

```sh
Source/Loaders/Linux-IME/tools/gnome-vm.sh stop
Source/Loaders/Linux-IME/tools/gnome-vm.sh start
```

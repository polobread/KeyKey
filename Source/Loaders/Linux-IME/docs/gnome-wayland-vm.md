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

## GNOME typing matrix

```sh
Source/Loaders/Linux-IME/tools/gnome-vm-wayland-smoke.py
Source/Loaders/Linux-IME/tools/gnome-vm-wayland-smoke.py --case T06-navigation --mode gtk3-xwayland
Source/Loaders/Linux-IME/tools/gnome-vm-real-app-smoke.py --mode wayland --mode xwayland
Source/Loaders/Linux-IME/tools/gnome-vm-real-app-smoke.py
Source/Loaders/Linux-IME/tools/gnome-vm-focus-smoke.py
```

The runner requires an active Wayland login, the installed
`chichi77-keykey.so`, Fcitx Wayland and IBus frontends, and the three guest
test hosts. It forces native Wayland or XWayland backends for GTK 3/4 and Qt 6,
then sends actual VM keyboard events through QMP. GTK 3/4 also run with
`GTK_IM_MODULE` unset on native Wayland to exercise GNOME's default input
path. Every case checks required preedit states and exact application text,
switches to `keyboard-us`, and checks the literal negative control. Cases
include T01 standard/continuous/invalid typing, T02's five Bopomofo layouts,
T03 editing/cancel, T06 vertical and horizontal keyboard navigation plus a
real pointer click on candidate two, T07 associated phrases, T08 full-width,
simplified output and mode switching, T09 shortcut pass-through, and T12 symbol
selection. The current matrix is 20 cases across eight toolkit/backend modes,
or 160 combinations. `--case` and `--mode` can be repeated to narrow a
diagnostic run. The complete 2026-09-20 guest run passed 160/160 and restored
the guest settings without errors. The pointer case takes QMP screenshots
before, during and after the candidate popup; it checks that the selected text
is `鐘` and that the
popup region clears within roughly half a second. These are sampled display
pixels in the VM, not a full geometry, theme or multi-monitor sweep.
The runner records the installed package and addon hash, individual results,
and any failure in ignored `out/gnome-vm/gnome-typing-last.json`; event traces
and final text remain under `/tmp/keykey-gnome-e2e/` inside the guest. A
passing run is functional evidence for these key sequences. It does not
establish browser or sandbox behavior, full T01–T12 coverage, all popup
positions/styles, or release readiness.

The second runner opens real gedit and GNOME Text Editor documents in four
paths each: direct Fcitx native Wayland, native Wayland with `GTK_IM_MODULE`
unset, explicit GTK Wayland IM, and XWayland. It sends the same physical VM
keys and reads the document through AT-SPI, including a `keyboard-us` literal
negative control. It writes an ignored `out/gnome-vm/gnome-real-app-last.json`
report even when a case fails and restores the original desktop settings.
On 2026-09-20 gedit passed all four paths. GNOME Text Editor passed direct
Fcitx Wayland and XWayland but failed the two other native paths: the focused
document accepted the priming `x` and Backspace, while `fcitx5-remote` reported
an empty active engine and `status=0`. The failing processes had the intended
Wayland environment, a focused document, and the GTK 4 Fcitx module mapped;
this does not establish why the context was inactive. The tested guest has
GNOME Text Editor 46.3, GTK 4.14.5 and Fcitx GTK4 frontend 5.1.1.
Keep this as an open GTK 4 application integration gap; the direct
`GTK_IM_MODULE=fcitx` path is the tested route for
that editor (`GTK_IM_MODULE=fcitx gnome-text-editor` inside the guest). The
synthetic GTK 4 host passed its corresponding unset-variable path,
which does not establish compatibility for every GTK 4 application.

The focus runner opens two fields in each GTK 3, GTK 4 and Qt 6 host. It
starts a candidate in the first field, clicks the second through the VM
pointer, commits `文`, returns to the first and commits `中`. A separate
`keyboard-us` phase checks literal text in both fields. The 2026-09-20 run
passed 16/16 phases, with two distinct focus-out results: six direct Fcitx
native Wayland/XWayland paths commit the first field's raw `ㄓㄨㄥ` on blur,
yielding `ㄓㄨㄥ中|文`; the two GTK native Wayland paths with `GTK_IM_MODULE`
unset clear the preedit and yield `中|文`. The runner preserves these exact
expectations and records `raw_preedit_on_blur` in
`out/gnome-vm/gnome-focus-last.json`. This observed path difference
from the existing X11 focus test and still needs a product decision before
declaring active-candidate focus behavior complete.

The runner temporarily disables GNOME idle lock and unlocks the guest's active
Wayland session before injecting keys. It restores the prior idle/lock settings,
the KeyKey config file, and the active KeyKey engine on exit. Without this step,
an unattended VM can lock between test runs: QMP keys then enter the lock
screen, and the test host times out with no input events despite a healthy
Fcitx addon.

On 2026-09-20 a separate QMP screenshot during the GTK 3 candidate stage
showed all nine vertical candidates next to the focused entry. Fcitx also
displayed a Wayland diagnostic
notification recommending the GNOME Shell Input Method Panel extension. The
before/candidate PNG files are in the ignored `out/gnome-vm/` directory; they
are one visual sample, not the planned popup geometry and timing sweep.

The QMP socket and KVM device can be hidden from a restricted process even
when the ordinary WSL user can access them. In that case run the scripts from
a normal WSL shell or grant that process access to the local VM socket. Do not
change `/dev/kvm` or socket permissions merely to bypass process isolation.

The guest has also been stopped and started again after provisioning; the
Wayland login, SSH and installed addon recovered, and the original five T01
smoke cases passed again. After an explicit `systemctl restart gdm3`, the
active Wayland session, GNOME Shell and Fcitx processes were new, the installed
addon loaded, and T01 standard plus T06 pointer selection passed in all eight
toolkit/backend modes (16/16). This checks display-manager session restart;
manual logout/login and application state recovery still need separate checks.

To stop or resume the guest without deleting its disk:

```sh
Source/Loaders/Linux-IME/tools/gnome-vm.sh stop
Source/Loaders/Linux-IME/tools/gnome-vm.sh start
```

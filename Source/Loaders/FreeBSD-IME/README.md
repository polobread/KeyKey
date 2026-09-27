# FreeBSD Fcitx 5 frontend

The initial FreeBSD targets are i386 and amd64. This frontend builds the
shared engine and Fcitx 5 addon from `../Fcitx5-Common`. The installed addon
and data identifiers remain `chichi77-keykey`; only the FreeBSD Port is named
`fcitx5-keykey`.

The candidate Port lives in `ports/chinese/fcitx5-keykey`. It targets the
first release that includes this directory. Update `DISTVERSION` and the
CMake project version together when that release is tagged, then generate
`distinfo` with `make makesum` inside an up-to-date FreeBSD ports tree.
The shared source built and passed its engine test on FreeBSD 15.1 amd64 and
FreeBSD 14.4 i386 in QEMU VMs. Both staged installs matched `pkg-plist`.
A tagged distfile and `distinfo` are still needed. Before submitting the Port,
also run a desktop input test, `make stage-qa check-plist package`, and
`poudriere testport`.

The Port installs the Fcitx 5 addon, Bopomofo/Cangjie/Simplex descriptors,
shared input data, and `keykey-smart-phrases`. The Linux GNOME launcher
and separately packaged GNOME candidate panel are not included.

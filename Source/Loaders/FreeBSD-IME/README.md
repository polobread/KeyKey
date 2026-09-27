# FreeBSD Fcitx 5 frontend

This frontend builds the shared engine and Fcitx 5 addon from
`../Fcitx5-Common`. The installed addon and data identifiers remain
`chichi77-keykey`; only the FreeBSD Port is named `fcitx5-keykey`.

The candidate Port lives in `ports/chinese/fcitx5-keykey`. It targets the
first release that includes this directory. Update `DISTVERSION` and the
CMake project version together when that release is tagged, then generate
`distinfo` with `make makesum` inside an up-to-date FreeBSD ports tree.
Do not submit the Port until it passes a native FreeBSD build, runtime input
test, `make stage-qa check-plist package`, and `poudriere testport`.

The Port installs the Fcitx 5 addon, Bopomofo/Cangjie/Simplex descriptors,
shared input data, and `keykey-smart-phrases`. The Linux GNOME launcher
and separately packaged GNOME candidate panel are not included.

# Shared Fcitx 5 implementation

`engine/` contains the input engine and local learning store.
`adapters/fcitx5/` supplies the Fcitx 5 addon. `tools/` builds the
Smart Mandarin database and phrase utility. `data/` contains the
generated Traditional-to-Simplified table.

`Linux-IME` and `FreeBSD-IME` each provide a platform CMake entry
point and include this directory with `add_subdirectory`. Runtime addon
and data names remain `chichi77-keykey`; the C++ namespace remains
`keykey::linux_ime` to preserve source compatibility during this move.

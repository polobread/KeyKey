# chichi77 KeyKey for Linux

This directory contains the new native Linux implementation. It does not link
or modify the legacy KeyKeyEngine or OpenVanilla frameworks. The first release
target is 1.2.8, led by Ubuntu Desktop 24.04 LTS with Fcitx 5.

## Current development status

The initial vertical slice provides:

- a display-server-independent C++17 engine contract;
- a strict CIN reader using the repository's read-only input tables;
- isolated state for each input context;
- Standard, ETen, ETen 26-key, Hsu, and Hanyu Pinyin Bopomofo layouts, plus
  initial Cangjie and Simplex table composition using CIN key names;
- candidate lookup, cyclic arrow/PageUp/PageDown navigation, numeric selection,
  Backspace, Escape, Enter, and Space;
- a native associated-phrase parser for the McBopomofo base and all 29 bundled
  category collections, with source-order merge, deduplication, filtering,
  Shift+1–9 suffix selection, first-run base default, an all-disabled state,
  and a nested Fcitx-native Boolean setting for every collection;
- a per-input-context full/half-width mode toggled by `Shift+Space`, including
  direct ASCII punctuation/letter/space conversion while preserving an active
  reading or candidate list;
- one loadable Fcitx 5 addon with Bopomofo, Cangjie, and Simplex registrations;
- unit and real-data tests for all five packaged tables, including pinned
  round-trip coverage for more than 1,490 real Bopomofo readings per symbolic
  layout, representative Hanyu Pinyin initials/finals/tones, and punctuation
  shortcut/list behavior;
- an installed-package X11 E2E test that sends physical key events into a real
  GTK 3 entry and verifies all five Bopomofo layouts → `中`, Cangjie `a` →
  `日`, Simplex `a` → second candidate `曰`, and Bopomofo second-page keyboard
  navigation → `妐`, `Shift+Space` full-width input → `Ａ！～　`, plus
  Traditional-to-Simplified output `臺灣` → `台湾`, plus `Ctrl+0` symbol-list
  selection → `，`, plus associated-phrase default `今` → `今天`,
  `history`-only `臺` → `臺灣史`, and all-disabled `臺` → `臺!`;
  a fourth association case verifies migration from the earlier comma-separated
  setting, while a fifth writes through the Fcitx D-Bus settings API, restarts
  Fcitx, reads the value back, and types with the persisted selection. A sixth
  opens the installed `fcitx5-config-qt` window, finds controls through AT-SPI,
  clicks the Bopomofo configuration and collection checkboxes, saves, restarts
  Fcitx, and types `作物育種` with the selected `agriculture-food` collection;
  every flow has a `keyboard-us` negative control;
- Debian packages named `chichi77-keykey-data` and
  `fcitx5-chichi77-keykey`, built with debhelper and checked by lintian;
- a package lifecycle test covering install, controlled preview-to-1.2.8
  upgrade, removal, reinstall, dependency/file/hash checks, the sixteen
  keyboard-only X11 cases after each installed state, and the settings-window
  case once after reinstall;
- a persistent Fcitx-native settings schema with a five-layout combo box, a
  Traditional-to-Simplified Boolean option, and a nested pane containing 30
  associated-phrase collection checkboxes, exposed directly from the
  `chichi77 KeyKey Bopomofo` input method. The earlier comma-separated field is
  hidden and migrated when an existing development configuration is loaded.

Advanced Cangjie/Simplex behaviors, IBus, a Linux equivalent for the macOS
Traditional-to-Simplified shortcut, full-width behavior outside an active
Linux input context, the remaining settings and complete
symbol/emoticon/common-text windows, RPM/Arch packaging, native Wayland, and
full desktop/App tests are not
implemented yet. The current Debian packages contain only the implemented
data and Fcitx 5 components; they are development artifacts, not a complete
1.2.8 Linux release. These three input-method paths and five-layout tests are
vertical slices, not complete feature-parity claims.

Current feature evidence is tracked in [`docs/parity.md`](docs/parity.md). The
compatibility inventory is machine-readable in
[`ci/support-matrix.json`](ci/support-matrix.json): nine Ubuntu targets are the
active phase, while Debian and Fedora are eleven explicit future TODO targets.
Entries marked `build-only` have not passed installed desktop typing acceptance.

## Configure and GNU Make source build

The traditional source-build entry point is a thin wrapper around the same
CMake targets and install rules used by the development and package builds. On
Ubuntu, install the required compiler, build system, and Fcitx headers first:

```sh
sudo apt-get install build-essential cmake libfcitx5core-dev
cd Source/Loaders/Linux-IME
./configure
make -j2
make check
make DESTDIR="$PWD/out/source-stage" install
```

The default prefix is `/usr/local`. A real install therefore uses
`sudo make install`; `sudo make uninstall` removes only files recorded in that
build's CMake install manifest. It does not remove Fcitx user configuration,
learning data, or unrelated files, and it never selects an input method for
the user. Some Fcitx builds do not include `/usr/local` in every compiled-in
search path, so set the addon and data roots in the desktop session before
restarting Fcitx:

```sh
fcitx_system_libdir=$(pkg-config --variable=libdir Fcitx5Core)
export FCITX_ADDON_DIRS="/usr/local/lib/fcitx5:$fcitx_system_libdir/fcitx5${FCITX_ADDON_DIRS:+:$FCITX_ADDON_DIRS}"
export XDG_DATA_DIRS="/usr/local/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
fcitx5 -r -d
```

Then add one of the three chichi77 KeyKey input methods with the normal Fcitx
configuration tool. Put the variables in the desktop session environment when
Fcitx is started through D-Bus or the desktop; an unrelated terminal does not
change an already-running Fcitx process.

Use `./configure --prefix=/usr` for a distribution-style system install.
Do not overlay files owned by the `fcitx5-chichi77-keykey` or
`chichi77-keykey-data` Debian packages: remove the packages before a source
install, or run `make uninstall` before returning to package-managed files.

`./configure --help` lists the supported switches, including `--libdir`,
`--datadir`, adapter, test-host, and sanitizer controls. `CXX`, `CPPFLAGS`,
`CXXFLAGS`, and `LDFLAGS` are passed through. `make clean` keeps the
configuration; `make distclean` removes only the wrapper Makefile and private
build directory generated by that configure invocation. An out-of-source
build is also supported:

```sh
mkdir build-keykey
cd build-keykey
../KeyKey/Source/Loaders/Linux-IME/configure --prefix=/usr
make -j2
make check
```

For another nonstandard prefix, use the directories printed by `configure` in
the same session environment. For example, with
`--prefix=/opt/keykey --libdir=lib --datadir=share`:

```sh
fcitx_system_libdir=$(pkg-config --variable=libdir Fcitx5Core)
export FCITX_ADDON_DIRS="/opt/keykey/lib/fcitx5:$fcitx_system_libdir/fcitx5${FCITX_ADDON_DIRS:+:$FCITX_ADDON_DIRS}"
export XDG_DATA_DIRS="/opt/keykey/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
fcitx5 -r -d
```

The Ubuntu 24.04 gate performs a temporary default `/usr/local` install, applies
those explicit session search paths, loads the addon in Fcitx 5, types through
GTK 3 on X11, and uninstalls it through the manifest.

Release maintainers can create the Linux source archive and checksum from a
committed revision, then rebuild the archive without a Git directory or prior
cache:

```sh
Source/Loaders/Linux-IME/ci/create-source-archive.sh
Source/Loaders/Linux-IME/ci/test-source-archive.sh
```

`--enable-x11-e2e-host` additionally requires `pkg-config` and the GTK 3
development files; these are test-only and are not required for the normal
engine and Fcitx addon build.

## Persistent Ubuntu 24.04 development container

On macOS or Windows 11 with WSL2, the fastest edit/build/test loop uses one
persistent Ubuntu 24.04 container instead of creating a fresh container for
every command:

```sh
Source/Loaders/Linux-IME/ci/dev.sh up
Source/Loaders/Linux-IME/ci/dev.sh build
Source/Loaders/Linux-IME/ci/dev.sh test
Source/Loaders/Linux-IME/ci/dev.sh source
Source/Loaders/Linux-IME/ci/dev.sh e2e T01-X11-GTK3-BOPOMOFO-STANDARD
Source/Loaders/Linux-IME/ci/dev.sh verify
Source/Loaders/Linux-IME/ci/dev.sh package
```

`up` builds the dependency image only when the Ubuntu 24.04 Dockerfile changes,
then keeps the container running. Subsequent commands use `docker exec`, an
incremental Ninja build directory, and a persistent staging directory. The
build and stage directories live in Docker named volumes so C++ object-file
traffic does not cross the macOS bind mount. E2E evidence and development
packages remain visible in the checkout under `out/e2e/` and `out/packages/`.

The development entry point automatically selects the host architecture. An
Apple Silicon Mac therefore uses `linux/arm64` without emulation. Export
`KEYKEY_DOCKER_PLATFORM=linux/amd64` before every command only when an emulated
amd64 development result is explicitly needed. ARM64 output is a preview and
cannot replace the release-gate amd64 packages.

`e2e` accepts `all`, one case ID, or a comma-separated list of case IDs. Set
`KEYKEY_E2E_KEY_DELAY_MS` to adjust the physical-key delay for local diagnosis;
the persistent development path defaults to 25 ms, while the independent
one-shot and package gates retain the conservative 80 ms default. `verify` runs
CTest, staged-install checks, and E2E in the same persistent container. `package` builds one native-
architecture Ubuntu 24.04 release-candidate package set; it intentionally does
not replace the clean install/upgrade/removal lifecycle below.

`source` runs both source-directory and out-of-source configure/GNU Make
builds, including CTest, custom install directories, DESTDIR staging,
uninstall, clean, and distclean. It is separate from the incremental Ninja
cache used by `build` and `test`.

Use `ci/dev.sh status` to inspect the session, `ci/dev.sh shell` for an
interactive shell, and `ci/dev.sh down` to remove the container. `down` retains
the named build volumes, so a later `up` can continue incrementally.

### Windows 11 and WSL2 checklist

- Use an Ubuntu WSL2 shell and keep the checkout on its Linux filesystem, for
  example `/home/user/KeyKey`. Do not run these scripts from `/mnt/c` or a
  Windows Git checkout that may change LF line endings or executable bits.
- Run `uname -m`, `findmnt -T .`, and `docker info` before the first `up`.
  A normal x64 Windows host should report `x86_64`, the checkout should use a
  Linux filesystem such as `ext4`, and the Docker server must report Linux.
- A rootless Docker context is valid. If `docker info` succeeds in the normal
  WSL shell but a restricted automation process receives `permission denied`
  for `/run/user/UID/docker.sock`, grant that process access to the local
  Docker socket and retry. Do not use `sudo docker`, change the socket to mode
  `666`, or add unrelated groups merely to bypass a process sandbox.
- Run `ci/dev.sh status`, `ci/dev.sh test`, and then `ci/dev.sh verify` after
  `up`. Container presence alone does not prove that the build and X11 paths
  can use the persistent volumes.

The stage named volume is mounted at `out/stage`, while each architecture uses
a removable child such as `out/stage/dev-container-amd64`. The staging action
deletes and recreates that child on every verification run. Therefore
`initialize_writable_paths` must assign the host UID/GID ownership to the
mounted `out/stage` parent (`${stage_dir%/*}`), not only to the child directory.
Otherwise a fresh root-owned volume can fail with `Permission denied` when the
non-root development user tries to recreate the staging directory. Keep this
ownership invariant when changing the volume layout.

## One-shot Ubuntu container checks

Rancher Desktop or another Docker-compatible engine can run the same build in
an Ubuntu 24.04 userspace:

```sh
Source/Loaders/Linux-IME/ci/run-ubuntu-24.04.sh
```

The one-shot script defaults to the primary `linux/amd64` architecture, builds the
development image, configures with CMake and Ninja, compiles the engine and
Fcitx addon, runs CTest, and installs into an architecture-specific staging
directory under `out/stage`. To exercise the ARM64 preview build, run
`KEYKEY_DOCKER_PLATFORM=linux/arm64` with the same script. These are L1/build
checks. A container does not provide the GNOME Wayland session needed for
desktop E2E acceptance.

The Ubuntu 24.04 image can also run the current L3 installed X11/GTK 3 typing
test under Xvfb:

```sh
Source/Loaders/Linux-IME/ci/run-ubuntu-24.04-x11-e2e.sh
```

This builds a separate test image, stages the addon and real CIN data into an
ephemeral container, starts a private D-Bus session, Xvfb, and Fcitx 5, then
uses XTest through `xdotool` to type all five Bopomofo layout sequences plus
the Cangjie, Simplex, candidate-navigation, `Shift+Space` full-width,
Traditional-to-Simplified, and `Ctrl+0` symbol-list sequences. The full-width
case verifies the exact GTK text `Ａ！～　`, while the English-keyboard control
receives ` A!~ `. The conversion case selects `臺` and `灣`, verifies committed
`台湾`, and uses literal `w96 2j0 1` as its negative control.
The six associated-phrase cases verify the built-in default with `今天`, the
`history` category in isolation with `臺灣史`, the all-disabled state, and
migration of the earlier comma-separated setting through real `Shift+1` key
events. The fifth case writes the native
configuration through `SetConfig`, verifies the saved INI, restarts Fcitx,
reads the selection back, and then verifies its typing effect. The sixth opens
the installed Fcitx configuration window, locates its controls through AT-SPI,
uses real X11 clicks and accessibility actions to disable `McBopomofo` and
enable `agriculture-food`, captures before/after PNGs, presses OK, verifies the
saved INI and D-Bus value after restart, and physically types `作物育種`. It also checks
that Fcitx exposes the layout, conversion, and all 30 Boolean collection
settings through the input method's native configuration schema. It does
not inject Chinese text, call GTK setters, or use the clipboard. Each case is
switched back to `keyboard-us` and receives the same keys as a negative
control. Evidence is written under
`out/e2e/ubuntu-24.04-x11-ARCH/`. Passing this test proves these three minimal
installed Fcitx 5 to GTK 3 X11 paths, not GNOME or native Wayland.

To build the two native `.deb` files and test their complete current package
lifecycle in separate build and runtime containers:

```sh
Source/Loaders/Linux-IME/ci/run-debian-package.sh ubuntu-24.04
Source/Loaders/Linux-IME/ci/run-debian-package.sh ubuntu-22.04
```

The 24.04 path installs a controlled `1.2.8~preview1` fixture, runs the sixteen
keyboard-only X11 cases, upgrades to `1.2.8`, runs them again, removes and
reinstalls the packages, then runs all seventeen cases. Running the UI-heavy
case once keeps the installed-package proof while avoiding three identical Qt
startup cycles. The 22.04 path performs build, lintian,
dependency, file/data checksum, install/remove/reinstall, and ELF checks but
does not claim desktop typing acceptance. Packages and evidence are written
under `out/packages/` and `out/e2e/`; both directories are ignored by Git.

The minimum Ubuntu dependency boundary has a separate repeatable check:

```sh
Source/Loaders/Linux-IME/ci/run-ubuntu-22.04.sh
```

On an Ubuntu 24.04 development system with the dependencies already installed:

```sh
cd Source/Loaders/Linux-IME
cmake --preset linux-release
cmake --build --preset linux-release
ctest --preset linux-release
DESTDIR="$PWD/out/stage" cmake --install out/build/release
```

For engine-only development on another host, use the `engine-only` presets.
The `engine-sanitized` configure, build, and test presets run the same engine
suite with AddressSanitizer and UndefinedBehaviorSanitizer.

## Data override for addon development

An installed addon loads `bpmf-ext.cin`, `cj-ext.cin`, `simplex-ext.cin`,
`bpmf-punctuations.cin`, `tc2sc.cin`, and the 30 flattened collection files
plus their display-name map under `associated-phrases/` from
`/usr/share/chichi77-keykey/data` by default. A test session may set
`CHICHI77_KEYKEY_DATA_DIR` to a directory containing all five CIN files and
the `associated-phrases/` directory.
Production packages must install the pinned data and must not depend on a
source checkout.

# chichi77 KeyKey for Linux

This directory contains the new native Linux implementation. It does not link
or modify the legacy KeyKeyEngine or OpenVanilla frameworks. The first release
target is 1.2.8, led by Ubuntu Desktop 24.04 LTS with Fcitx 5.

## Current development status

Linux 1.2.8 phase one targets all behavior currently shipped by the Windows
TSF frontend. Standard, ETen, ETen 26-key, Hsu, and Hanyu Pinyin are therefore
all in scope. The already implemented Cangjie, Simplex, and
Traditional-to-Simplified slices remain available as extension points instead
of being removed, although they do not block Windows parity. Bopomofo learning,
dynamic frequency, and auto-correction are outside this phase because the
Windows runtime does not provide them.

The initial vertical slice provides:

- a display-server-independent C++17 engine contract;
- a strict CIN reader using the repository's read-only input tables;
- isolated state for each input context;
- Standard, ETen, ETen 26-key, Hsu, and Hanyu Pinyin Bopomofo layouts, plus
  Cangjie and Simplex table composition using CIN key names and `%endkey`
  metadata. Table punctuation, single-candidate commit, Cangjie error clearing
  and `?`/`*` wildcard queries, and Simplex two-code auto-query/continuous
  typing are implemented;
- candidate lookup, cyclic arrow/PageUp/PageDown navigation, numeric selection,
  Backspace, Escape, Enter, and Space; Backspace edits one reading component,
  including after closing candidates, while Escape cancels the complete reading;
  empty-state edit keys pass through to the application. An explicit Bopomofo
  tone immediately opens candidates, matching the Windows runtime;
- an optional Bopomofo Big5-HKSCS candidate filter that preserves source order;
- a native associated-phrase parser for the McBopomofo base and all 29 bundled
  category collections, with source-order merge, deduplication, filtering,
  Shift+1–9 suffix selection, first-run base default, an all-disabled state,
  and a nested Fcitx-native Boolean setting for every collection;
- a persistent vertical/horizontal candidate-window preference, applied to
  every Fcitx candidate list through its native layout hint;
- a per-input-context full/half-width mode toggled by `Shift+Space`, including
  direct ASCII punctuation/letter/space conversion while preserving an active
  reading or candidate list;
- a per-input-context Chinese/English mode with compact Fcitx status labels,
  toggled by `Ctrl+\` by default or by a bare Shift tap within 300 ms. Entering
  English abandons the active composition; half-width printable keys pass to
  the application, while full-width ASCII remains available;
- one loadable Fcitx 5 addon with Bopomofo, Cangjie, and Simplex registrations;
- default-enabled typing-error feedback using the XDG `bell-window-system`
  event sound, with a Fcitx-native option to disable it;
- unit and real-data tests for all five packaged tables, including pinned
  round-trip coverage for more than 1,490 real Bopomofo readings per symbolic
  layout, representative Hanyu Pinyin initials/finals/tones, and punctuation
  shortcut/list behavior;
- an installed-package X11 E2E test that sends physical key events into a real
  GTK 3 entry and verifies Standard Bopomofo → `中`, all five layouts and all
  four explicit tones → `麻馬罵嘛`, candidate-to-next-reading continuous input
  → `中文`, invalid `=` plus `Ctrl+C` recovery → `中`, incomplete Pinyin backspace recovery,
  macOS-first, Windows-cross-checked empty/reading/candidate Backspace and Escape
  boundaries → `中文麻`,
  Cangjie `a` → `日`, direct punctuation/error recovery → `，用`, wildcard
  queries → `昌日`, Simplex
  `a` → second candidate `曰`, full-code/continuous/direct-punctuation input →
  `明銖䍤、`, and Bopomofo Home/End plus second-page keyboard navigation → `妐`,
  `Shift+Space` full-width input → `Ａ！～　`, Big-5 filtering of `ㄝˋ`
  candidates → `𤦩`, plus
  Chinese/English switching by `Ctrl+\` and a short Shift tap, including
  composition cancellation, Caps Lock, English full-width input, long-Shift
  rejection, and disabled-shortcut pass-through, plus
  a modifier-boundary flow that holds `Ctrl+\` for one second without repeated
  toggles and preserves active readings/candidates across `Ctrl+C` and `Alt+F`,
  committing exact `x中文`, plus
  a two-entry input-context lifecycle flow that clears the first entry's
  candidate preedit after a geometry-derived pointer click focuses the second,
  independently commits `文` there,
  returns to commit `中` in the first without reviving the old candidate,
  closes a client while candidates are active, verifies Fcitx and the staged
  addon remain alive, restarts Fcitx, and types `中` from a fresh client, plus
  an editing-field flow that preserves the active reading and insertion point
  across navigation, Delete, Tab, and Shift-selection attempts, commits at the
  original caret, then replaces the selected middle character in `甲中乙丙`
  with a Bopomofo candidate to produce `甲中中丙`, verifies GTK's
  password content purpose disables the custom input method and associated
  phrases, and confirms a read-only entry stays unchanged after a complete key
  sequence, plus
  Traditional-to-Simplified output `臺灣` → `台湾`, plus `Ctrl+0` symbol-list
  selection → `，`, plus associated-phrase default `今` → `今天`,
  `history`-only `臺` → `臺灣史`, and all-disabled `臺` → `臺!`;
  a fourth association case verifies migration from the earlier comma-separated
  setting, while a fifth writes through the Fcitx D-Bus settings API, restarts
  Fcitx, reads the value back, and types with the persisted selection. A sixth
  opens the installed `fcitx5-config-qt` window, finds controls through AT-SPI,
  clicks the Bopomofo configuration, collection, typing-error sound, and
  `Ctrl+\` checkboxes, changes the candidate style from vertical to horizontal,
  saves, restarts Fcitx, and types `作物育種` with the selected
  `agriculture-food` collection and persisted horizontal layout hint;
  every flow has a `keyboard-us` negative control;
- Debian packages named `chichi77-keykey-data` and
  `fcitx5-chichi77-keykey`, built with debhelper and checked by lintian;
- a package lifecycle test covering install, controlled preview-to-1.2.8
  upgrade, removal, reinstall, dependency/file/hash checks, the twenty-nine
  keyboard-only X11 cases after each installed state, and all thirty cases,
  including the settings window, once after reinstall;
- a persistent Fcitx-native settings schema with the five Windows-supported
  Bopomofo layouts and vertical/horizontal candidate styles,
  Traditional-to-Simplified, all-Unicode, typing-error sound, and `Ctrl+\`
  mode-toggle Boolean options, and a nested pane containing 30
  associated-phrase collection checkboxes, exposed directly from the
  `chichi77 KeyKey Bopomofo` input method. The earlier comma-separated field is
  hidden and migrated when an existing development configuration is loaded.

The engine now opens candidates as soon as an explicit tone is entered, and
commits the highlighted candidate before starting a new reading when the next
valid Bopomofo key is pressed, across all five layouts. Invalid
printable keys and no-candidate queries preserve an active reading and report
an error-feedback request; application shortcuts still pass through. The Fcitx
adapter plays the desktop's XDG window-system bell for that request unless the
setting is disabled. Installed Fcitx-to-GTK3 cases cover the error flow and the
settings UI persists the disabled state; actual audible output still requires
GNOME-session acceptance because the Xvfb container has no audio session.
The Fcitx adapter also clears associated-phrase state defensively for clients
that report Password or Sensitive capabilities. In the current GTK 3 X11 path,
password purpose is stricter: Fcitx switches that input context to
`keyboard-us` and rejects forcing the custom method back on.
Other remaining work includes combined filter-order coverage, IBus,
full-width behavior outside an active Linux input context, symbol-list mouse
and visual behavior, RPM/Arch
packaging, native Wayland, and full desktop/App tests. The current Debian packages contain only the implemented
data and Fcitx 5 components; they are development artifacts, not a complete
1.2.8 Linux release. The Bopomofo path remains a vertical slice rather than a
complete feature-parity claim; the other two paths are retained extension
features rather than Windows-parity blockers.

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
sudo apt-get install build-essential cmake libcanberra-dev libfcitx5core-dev pkg-config
cd Source/Loaders/Linux-IME
./configure
make -j2
make check
make DESTDIR="$PWD/out/source-stage" install
```

The Debian frontend package links to the distribution's libcanberra runtime
and recommends `libcanberra-pulse` for the PulseAudio-compatible service used
by Ubuntu GNOME. The sound setting remains optional and the input method keeps
working when an audio service is unavailable.

The default prefix is `/usr/local`. A real install therefore uses
`sudo make install`; `sudo make uninstall` removes only files recorded in that
build's CMake install manifest. It does not remove Fcitx user configuration,
other user data, or unrelated files, and it never selects an input method for
the user. Some Fcitx builds do not include `/usr/local` in every compiled-in
search path, so set the addon and data roots in the desktop session before
restarting Fcitx:

```sh
fcitx_system_libdir=$(pkg-config --variable=libdir Fcitx5Core)
export FCITX_ADDON_DIRS="/usr/local/lib/fcitx5:$fcitx_system_libdir/fcitx5${FCITX_ADDON_DIRS:+:$FCITX_ADDON_DIRS}"
export XDG_DATA_DIRS="/usr/local/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
fcitx5 -r -d
```

Then add `chichi77 KeyKey Bopomofo` with the normal Fcitx configuration tool.
The existing Cangjie and Simplex registrations remain available as optional
extension paths; they are regression-tested but do not block phase-one parity.
Put the variables in the desktop session environment when
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
not replace the clean install/upgrade/removal lifecycle below. When a prior
one-shot package run left container-root-owned generated files on a rootless
engine, `package` removes only the matching architecture's work and
release-candidate directories as container root, then performs the new build
as the development UID. No manual `sudo rm` or checkout-wide permission change
is needed.

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
- The one-shot build, X11, and package scripts detect a rootless engine and
  use container-side UID/GID 0 for the bind-mounted checkout. Rootful engines
  continue to use the host UID/GID. Do not simplify those paths to an
  unconditional `--user "$(id -u):$(id -g)"`: after a clean build-directory
  removal, CMake may no longer be able to recreate `CMakeFiles` on WSL.
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
uses XTest through `xdotool` to type the five Windows-supported Bopomofo layouts and
the Cangjie, Simplex, table-end-key, candidate-navigation, `Shift+Space` full-width,
Chinese/English mode, Traditional-to-Simplified, and `Ctrl+0` symbol-list
sequences. The mode cases verify `Ctrl+\`, a 300 ms Shift tap, a rejected long
Shift hold, Caps Lock, English full-width input, and disabled-shortcut
pass-through. A separate modifier case holds `Ctrl+\` for one second, switches
back to Chinese, and sends `Ctrl+C` and `Alt+F` through active reading and
candidate states before committing exact `x中文`; its literal negative control
is `\x5j/ 1jp61`: releasing Ctrl first makes the unowned physical backslash
reach the client. Super-key behavior remains an engine-level check here because
Xvfb has no GNOME window manager to own desktop shortcuts. The full-width case
verifies the exact GTK text `Ａ！～　`, while the English-keyboard control
receives ` A!~ `. The conversion case selects `臺` and `灣`, verifies committed
`台湾`, and uses literal `w962j0 1` as its negative control.
A context-lifecycle case uses Tab and Shift+Tab between two real GTK entries,
verifies ordered per-entry preedit events and exact `中`／`文` text without
reviving the first entry's old candidates, then closes a client with candidates
open. It checks that Fcitx and the staged addon survive, restarts Fcitx, and
types `中` in a fresh client. Because Fcitx may track active input methods per
input context when shared input state is disabled, the test explicitly selects
and polls Bopomofo after moving to a newly focused entry; the matching
`keyboard-us` phase keeps every key literal.
The six associated-phrase cases verify the built-in default with `今天`, the
`history` category in isolation with `臺灣史`, the all-disabled state, and
migration of the earlier comma-separated setting through real `Shift+1` key
events. The fifth case writes the native
configuration through `SetConfig`, verifies the saved INI, restarts Fcitx,
reads the selection back, and then verifies its typing effect. The sixth opens
the installed Fcitx configuration window, locates its controls through AT-SPI,
uses real X11 clicks and accessibility actions to disable `McBopomofo`, the
typing-error sound and `Ctrl+\` mode toggle, enable `agriculture-food`, capture
before/after PNGs, change the candidate style from vertical to horizontal,
press OK, verify the saved INI and D-Bus value after restart, and physically
type `作物育種` while the horizontal hint is active. It also checks that Fcitx
exposes both candidate styles, the Bopomofo layout, conversion, mode toggle,
and all 30 Boolean collection
settings through the input method's native configuration schema. It does
not inject Chinese text, call GTK setters, or use the clipboard. Each case is
switched back to `keyboard-us` and receives the same keys as a negative
control. Evidence is written under
`out/e2e/ubuntu-24.04-x11-ARCH/`. Passing this test proves these minimal
installed Fcitx 5 to GTK 3 X11 paths, not GNOME or native Wayland.

Candidate size and highlight colors remain owned by the active Fcitx UI and
theme. The input-method addon API available in Ubuntu 22.04 and 24.04 provides
a per-list vertical/horizontal hint, but no per-input-method scale or highlight
color controls. Matching the Windows-only 75%–350% and purple/green/yellow/red
choices would therefore require a separate custom Fcitx UI addon or an explicit
platform-level difference; those controls are not exposed as no-op settings.

To build the two native `.deb` files and test their complete current package
lifecycle in separate build and runtime containers:

```sh
Source/Loaders/Linux-IME/ci/run-debian-package.sh ubuntu-24.04
Source/Loaders/Linux-IME/ci/run-debian-package.sh ubuntu-22.04
```

The 24.04 path installs a controlled `1.2.8~preview1` fixture, runs the twenty-nine
keyboard-only X11 cases, upgrades to `1.2.8`, runs them again, removes and
reinstalls the packages, then runs all thirty cases. Running the UI-heavy
case once keeps the installed-package proof while avoiding three identical Qt
startup cycles. The latest completed package evidence passes 29/29 cases after
both preview install and release upgrade, then 30/30 after reinstall. The 22.04
path performs build, lintian,
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

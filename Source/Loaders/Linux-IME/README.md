# chichi77 KeyKey for Linux and FreeBSD

The Fcitx 5 frontend uses **Guanyinma (Rust) as its only input core** for
好打注音, 傳統注音, Cangjie, and Simplex. C++ handles Fcitx events, input contexts,
native font checks, associated phrases, output conversion, and administrative
data conversion. Input algorithms, candidate ranking, and learning run in Rust.
The current integration, desktop preferences, and data contracts are described
in the [Guanyinma adapter guide](../../../docs/GUANYINMA_LINUX_ADAPTER.md).

Released packages and their desktop setup are documented separately in the
[Linux installation guide](../../../LINUX_INSTALL.md) and
[FreeBSD installation guide](../../../FREEBSD_INSTALL.md). A source build or
isolated test does not establish acceptance of an installed package, GNOME
Wayland, or FreeBSD.

## Input and preferences

Fcitx configuration groups expose general behavior, Smart Mandarin, Cangjie,
Simplex, and associated-phrase settings. Bopomofo supports Standard, ETen,
ETen26, Hsu, and Hanyu Pinyin layouts. 好打注音 is the initial Bopomofo mode.

The frontend preserves desktop Manjusri/OpenVanilla behavior through Guanyinma:
sentence composition, cursor-based word selection, configurable candidate keys,
10–20 completed-syllable buffers, candidate and Bigram learning, and table-input
preferences. The default buffer holds ten completed syllables; completing the
eleventh commits the first whole word. The native frontend also provides
Chinese/English switching, full/half-width output, Traditional-to-Simplified
conversion, typing-error sound, and per-context state.

Associated phrases use the McBopomofo base plus 29 category collections. Each
collection has a Boolean option in the `[AssociatedPhrases]` section. The base is
enabled initially, and disabling every collection disables associated phrases.
`Shift+1–9` selects a suggested suffix. Candidate size, font, scale, and colors
belong to the active Fcitx UI or GNOME candidate panel; the addon provides a
vertical/horizontal layout hint.

The **自訂詞…** entry opens the GTK phrase editor, which supports add, edit,
delete, model reading suggestions, learning reset, and Guanyinma JSON backup and
import. The **關於琦琦輸入法 — 版本 …** and **更新通知與下載…** entries open the
shared GTK About and update tools. See [update notifications](docs/update-notifications.md)
for the Linux/FreeBSD feed and ports integration.

## Configure and GNU Make source build

Install CMake 3.22+, GNU Make, a C++17 compiler, `pkg-config`, Python 3,
SQLite, json-c, PangoFT2/Fontconfig, Fcitx 5 Core, and libcanberra development
files. GUI tools require Python GI and GTK 3. Rust is required for every build;
prepare the exact toolchain in `Source/Guanyinma/rust-toolchain.toml` and the
locked Cargo dependencies. In Bash, `source ci/prepare-guanyinma.sh` prepares
that toolchain. Prepared environments may set `CARGO`, `CARGO_HOME`, and
`RUSTUP_HOME` explicitly.

On Ubuntu:

```sh
sudo apt-get install build-essential cmake curl libcanberra-dev libfcitx5core-dev libsqlite3-dev libjson-c-dev libpango1.0-dev pkg-config python3 python3-gi gir1.2-gtk-3.0
cd Source/Loaders/Linux-IME
./configure
make -j2
make check
make DESTDIR="$PWD/out/source-stage" install
```

The last command stages files without changing the system. For an actual source
installation use `sudo make install`; use `sudo make uninstall` from the same
build to remove its recorded files. Do not overwrite package-managed files.
Use `--prefix=/usr` for a distribution layout. `./configure --help` lists path,
adapter, test, and offline-build options. Out-of-source invocation and `CXX`,
`CPPFLAGS`, `CXXFLAGS`, and `LDFLAGS` are supported. `make clean` preserves the
configuration; `make distclean` removes the generated wrapper and private build.

A nonstandard prefix must be discoverable by the Fcitx process. Point
`FCITX_ADDON_DIRS` to its addon directory and `XDG_DATA_DIRS` to its share directory,
then start an isolated Fcitx process with those variables. A shell environment
change does not change an already-running desktop process.

## CMake development and focused checks

With Ninja and the dependencies installed, enable GTK 3/4 and Qt 6 test hosts
for the isolated smoke run. Their development packages are `libgtk-3-dev`,
`libgtk-4-dev`, and `qt6-base-dev`; runtime Fcitx GTK 3/4 and Qt 6 frontend
plugins must also be available:

```sh
cd Source/Loaders/Linux-IME
cmake --preset linux-release -DKEYKEY_BUILD_X11_E2E_HOST=ON
cmake --build --preset linux-release
ctest --preset linux-release
DESTDIR="$PWD/out/stage/current" cmake --install out/build/release
bash ci/run-guanyinma-smoke.sh out/build/release out/stage/current
```

The smoke runner uses private D-Bus and Xvfb sessions with GTK 3, GTK 4, and Qt 6
test clients. It sends physical keys through the staged Fcitx addon and verifies
application text. It does not operate the user's desktop input method.
`engine-only` builds the same Rust adapter without Fcitx or a display server;
Rust, JSON, and native font dependencies remain required. `engine-sanitized`
instruments native C++ adapter/helper code with ASan/UBSan; Rust remains a normal
pinned-toolchain build.

Tests cover settings and event mapping, font filtering, context lifetime,
candidate generations, one-shot host effects, CLI administration, and the GTK
phrase tool. The complete Rust algorithm matrix belongs to `guanyinma-core.yml`.
Linux frontend workflows run the relevant integration checks rather than
repeating that matrix. Test only the layers affected by a change; record source,
build, staged, package, X11, GNOME Wayland, and FreeBSD results separately.

For source, container, and package workflows see [BUILDING.md](../../../BUILDING.md).
Optional dedicated-desktop procedures are in the
[GNOME X11 runbook](docs/manual-desktop.md) and
[GNOME Wayland VM runbook](docs/gnome-wayland-vm.md).
The [GNOME panel integration guide](docs/gnome-candidate-panel.md) describes
renderer ownership and its separate acceptance scope.

## Runtime data

CMake verifies and installs the repository's pre-generated shared `KeyKey.db`
as `smart-mandarin.db`; it never recooks the model. Runtime addon/data names
remain `chichi77-keykey`, and the C++ namespace is `keykey::linux_ime`.

The Guanyinma user database is
`$XDG_DATA_HOME/chichi77-keykey/guanyinma-user.db`, or under
`~/.local/share` when XDG is unset. `CHICHI77_KEYKEY_GUANYINMA_USER_DB` overrides
this private user-data path. The packaged model remains read-only.

```sh
keykey-smart-phrases list
keykey-smart-phrases readings 琦琦
keykey-smart-phrases add 詞語 'ㄘˊ ㄩˇ'
keykey-smart-phrases remove 詞語 'ㄘˊ ㄩˇ'
keykey-smart-phrases reset-learning
keykey-smart-phrases export backup.json
keykey-smart-phrases import backup.json
```

A development session may set `CHICHI77_KEYKEY_DATA_DIR` to a directory containing
`bpmf-ext.cin`, `cj-ext.cin`, `simplex-ext.cin`, `bpmf-punctuations.cin`,
`tc2sc.cin`, `smart-mandarin.db`, and the `associated-phrases/` directory. Normal
packages install pinned data and notices under the configured prefix and do not
require a source checkout.

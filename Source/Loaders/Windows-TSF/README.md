# 琦琦輸入法 Windows TSF frontend

Windows 1.3.1 的兩種安裝流程稽核、舊版遷移設計與待驗收矩陣見
[Windows 安裝與舊版遷移規劃](../../../docs/WINDOWS_INSTALLATION_1_3_1_PLAN.md)。
共用安裝核心、兩種入口與文件已依規劃修改；歷代實際安裝包的 VM 升級／移除驗收仍待完成。

Windows 1.3.1 的安裝與日常操作見 [Windows 安裝與使用指南](../../../WINDOWS_INSTALL.md)；本頁記錄實作、建置與部署細節。

The standard `GUID_LBI_INPUTMODE` item exposes a menu style (without a split-button arrow):
Windows can invoke `InitMenu`/`OnMenuSelect` to switch all four methods even when
an immersive host cannot use the desktop popup. `KeyKeyTsfSystemTrayTest` checks
the item through the native TSF language-bar manager and verifies its mode menu.
Chinese/English mode synchronizes both open/close and the conversion compartment's
`NATIVE` bit, retaining width and the other conversion flags.
If a restricted Search/Store process cannot access Roaming preferences, the
frontend and engine share that process's sandboxed Temp profile. Preferences and
learning data remain private; no file permissions are expanded. The current input
method is shared through a TSF global compartment, read at activation, focus, menu,
and key dispatch. A stale profile cannot overwrite that choice on activation.
Desktop settings changes and explicit menu selections publish a new choice.
`KeyKeySharedInputMethodTest` uses a random compartment GUID and separate processes
and profiles to verify all four modes, actual composition, and reverse propagation.
Pass the other architecture's executable as its argument to test x64/x86 sharing.
`--container` creates a temporary AppContainer, gives only that SID read/execute
access to disposable executable/database copies, and runs all four child cases
with private writable profiles. The AppContainer registration is removed afterward.
Run this test in the normal user session: a restricted command sandbox cannot
write the session-wide TSF compartment and reports `E_FAIL`.
Local verification passed 15 x64 and 14 x86 tests, plus both directions of
x64/x86 mode sharing. On 2026-10-01, the user confirmed that the installed
Windows Search mode switching and menu fixes work. This is separate from
the automated AppContainer tests and from release/upgrade validation.

This directory contains the Windows 10 and 11 Text Services Framework (TSF)
frontend. It is separate from `Windows-IMM`, so the existing macOS IMK target
and its Xcode project remain unchanged.

## Current milestone

- Smart Mandarin (好打注音) sentence composition and the existing Traditional
  Mandarin mode through the OpenVanilla and PlainVanilla core
- Cangjie (倉頡) and Simplex (簡易) through the shared `OVIMGeneric` engine and
  canonical database, with Windows-specific settings and short learning transactions
- per-user phrases, candidate overrides, and contextual learning stored in
  `%APPDATA%\chichi77 KeyKey\SmartMandarinUserData.db`
- TSF composition, caret placement, commit, and candidate-window flow
- Immersive TSF registration for modern Windows text hosts such as Start/Search
- Taskbar language-bar indicators for Chinese/English (`ㄅ`/`倉`/`簡`/`英`) and
  half-/full-width (`半`/`全`) modes, with a menu section for direct Smart or
  Traditional Mandarin, Cangjie or Simplex selection
- `ITfFnConfigure` keyboard-options entry and a standalone five-page Fluent WPF
  settings app that follows the Windows light/dark preference; its native backend
  retains the existing user phrase and learning-data behavior
- vertical or horizontal candidate windows with independent Windows-style
  scaling choices and purple, green, yellow, or red highlighting; optional
  typing-error sound and `Ctrl+\` mode switching
- Standard, ETen, ETen 26, Hsu, and Hanyu Pinyin Bopomofo layouts, plus a
  switch between Big-5-only candidates and the full CNS11643 character set
- One selectable Traditional Chinese profile (`zh-TW`), disabled by default.
  All regions share this entry; users add it themselves in Settings. Upgrades
  retire both old Hong Kong/Macao definitions. Users of those old entries must
  select the shared entry in Settings; personal preferences and data are retained.
- x86 and x64 builds completed for 1.3.0; a Notepad Bopomofo smoke test passed,
  with broader application testing pending

New profiles start in Smart Mandarin. Existing profiles retain their selected
mode. The settings app's General page controls which input methods appear in
the taskbar menu; the Bopomofo page keeps layout and character-set options.
The reset-learning button removes Smart Mandarin learned bigrams and
candidate overrides while preserving user phrases and table candidate ordering.
The old IMM32 loader and Windows preference panels supply behavioral references
for Cangjie and Simplex. The old IMM32 loader is retained as historical
reference and is not linked into this DLL.

### Cangjie and Simplex development build

This source adds these modes to 1.3.1 local builds; published installers and
already installed DLLs are separate artifacts and may still contain only Mandarin.
Cangjie retains up to five radicals and queries with Space/Enter; Simplex queries
at two radicals. Number keys select candidates, Page Up/Down page, Backspace
edits radicals and Esc cancels. Cangjie supports `?` and `*` wildcard lookup.
The table settings page controls live lookup, clear-on-error and Big-5 filtering;
Cangjie also offers full-code querying, punctuation overrides and dynamic ordering.
Live lookup and clear-on-error are mutually exclusive. Dynamic ordering defaults
off, as in the old Windows preference application. Each input method uses its own
`Generic-*-cin-DynamicCandidateOrder.sqlite3` file. Learned candidates remain
subject to the current character-set restriction. Busy or unwritable learning
storage does not block text input.

The current `com.polobread` preference files take precedence over the earlier
`org.openvanilla.chichi77-keykey.windows` files. Migration now includes both table
modules and preserves the old files. The old Simplex `ComposeWhenTyping` alias
is accepted until `ComposeWhenTypingMigrated=true` records a modern setting.
Raw Yahoo IMM/MSI installation state and its different profile directory are not
automatically imported. Mode changes preserve visible text (including unfinished
radicals) before new input starts in the selected mode.

Local verification uses `KeyKeyTableInputTest` for basic input, paging, live
lookup, Windows-translated Backspace/Enter/Esc events, legacy settings, Unicode, settings reload, mode changes, and an independent
SQLite writer while an engine session remains active. Settings tests cover all
15 non-empty visibility combinations and native-backend WPF control events,
Apply and reopening. `KEYKEY_TSF_TEST_PROFILE_DIR` isolates both the engine and
settings backend. Desktop visual QA, actual TSF host input, and installer
upgrade verification remain separate acceptance steps.

## Screenshots

The [Windows installation guide](../../../WINDOWS_INSTALL.md) uses clearly
labelled 1.3.0 reference captures; the 1.3.1 installer has no destination page.
After first installation, add KeyKey under Traditional Chinese (Taiwan), Hong
Kong or Macao in Windows Settings > Language options > Add a keyboard, then
select it using Win+Space. The shared entry selection is preserved; users of the
retired regional entries must add and select the shared entry.

In Notepad, Smart Mandarin composes Bopomofo and displays numbered Chinese
candidate choices. The underline on active composition text may look different
in other applications because the text host controls its rendering.
Esc closes an open candidate list or cancels an unfinished reading while keeping
the completed sentence. By default, Esc also keeps a completed sentence in
composition; the Phonetic settings tab offers an explicit option to clear it.

![Smart Mandarin composition and Chinese candidates in Notepad, Windows 1.3.0](IMAGES/v1.3.0-smart-mandarin-composition.png)

The taskbar menu directly selects Smart Mandarin (好打注音), Traditional
Mandarin (傳統注音), Cangjie (倉頡), or Simplex (簡易). Check marks show the selected input method and width mode;
the same menu switches Chinese/English and opens settings. After upgrading,
sign out and back in once so Explorer loads the new menu.

![Windows 1.3.0 taskbar menu with Smart and Traditional Mandarin](IMAGES/v1.3.0-taskbar-input-method-menu.png)

The General settings page controls which input methods appear in the taskbar
menu, candidate-window direction and size, and other keyboard options. At
least one input method must remain visible.

![Windows 1.3.0 General settings page](IMAGES/v1.3.0-settings-general.png)

The Associated Phrases page selects the public phrase collections to load;
changes take effect on the next input. The User Phrases page adds, edits,
deletes, imports, and exports personal phrases and learning data.

![Windows 1.3.0 Associated Phrases settings page](IMAGES/v1.3.0-settings-associated-phrases.png)

![Windows 1.3.0 User Phrases settings page](IMAGES/v1.3.0-settings-user-phrases.png)

These captures show the light appearance. The Fluent settings app follows
the Windows light/dark preference.

## Prerequisites

- Windows 10 or later; development builds have been launched on Windows 11,
  while Windows 10 x64/x86 device verification remains pending
- .NET 10 SDK for building the self-contained settings and deployment apps (not needed on user PCs)
- Visual Studio 2026 with **Desktop development with C++** (a Visual Studio
  2022 compatibility preset is also included)
- CMake 3.25 or newer
- Python 3 to verify the pre-generated Smart Mandarin database
- NSIS 3.12 when building the Store EXE

Windows uses the operating system's `winsqlite3.dll` through the Windows SDK's
`winsqlite3.h` and `winsqlite3.lib`. The runtime SQLite version can vary with
Windows Update. No GNU Make, `awk`, `sed`, or standalone `sqlite3` program is
required. CMake verifies and packages the repository's pre-generated shared
`Source\Distributions\Takao\CookedDatabase\KeyKey.db`; Windows builds do not
recook the language model. This keeps Windows, macOS, iOS, Android, and Linux
on the exact same validated bytes.

To verify and deploy another pre-generated database, pass
`-DKEYKEY_DATABASE_PATH=C:\path\to\KeyKey.db` when configuring.
It must contain the 885,627-row Smart Mandarin bigram model and pass the
manifest, file hash, and SQLite integrity checks. CMake verifies it during the build.
If an existing CMake build directory cached the old default database path,
reconfigure with `cmake --fresh --preset windows-x64` (and likewise for x86)
to use the checked-in shared database.

## Build and register (x64 and x86)

Open an **x64 Native Tools Command Prompt/PowerShell for Visual Studio**, then
run from this directory:

```powershell
cmake --preset windows-x64
cmake --build --preset windows-x64-release
cmake --preset windows-x86
cmake --build --preset windows-x86-release
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x64-ninja\KeyKeyTsf.dll
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x86\Release\KeyKeyTsf.dll
```

The build creates `KeyKeyTsf.dll`, `KeyKeySettings.exe`,
`KeyKeySettingsBackend.dll`, `KeyKeyDeployment.exe`, `KeyKeyRegistration.exe`,
and `out\build\x64-ninja\Databases\KeyKey.db`.
Keep the settings backend beside the executable;
Windows Keyboard options and the language-bar settings button both launch it.
The settings app has a 自訂詞 tab: enter a word and comma-separated Bopomofo
readings, one syllable per character, then add or update the row. Deletion and
editing use the stored SQLite `rowid`, so gaps from earlier deletions are safe.
The same tab can import a `SmartMandarinUserData.db` backup: user phrases are
merged by reading and text, while the imported candidate and contextual
learning replace the current learning tables. Export uses SQLite's online
backup API, so a database can be saved while the input method is active.
The settings window footer shows `1.3.1`; the frontend validation script checks
that this visible version matches the CMake project and packaging version.
Language-model source changes do not alter a platform build automatically.
Generate and validate a new canonical `KeyKey.db` first, then commit the file
and its manifest before rebuilding the package.

To verify the Bopomofo core independently of TSF, run:

```powershell
ctest --test-dir .\out\build\x64-ninja --output-on-failure
```

The smoke test sends the Standard-layout `1`, `u`, `3` sequence and fails if
the engine passes those keys through as ASCII instead of producing a Bopomofo
reading and candidates.

The TSF service marks active composition text with a solid underline display
attribute. Text hosts decide how to render that attribute, so the underline
may differ between apps. Switching to English mode or away from the TIP ends
the active composition while keeping its visible text in the document.

The development registration script makes **琦琦輸入法** available in Windows
Settings. Add it yourself under a Traditional Chinese language's keyboard
options before selecting it with `Win+Space`. Existing profile choices are
preserved. Registration needs elevation because COM is machine-wide.

To unregister:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x64-ninja\KeyKeyTsf.dll -Unregister
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-Tip.ps1 `
  -DllPath .\out\build\x86\Release\KeyKeyTsf.dll -Unregister
```

The DLL and the hosting application must have matching architectures. In
particular, any 32-bit application cannot load the x64 TIP even on x64 Windows.
The x64 package therefore includes and registers both x64 and x86 DLLs.
The separate x86 ZIP serves 32-bit Windows and contains an x86 settings executable
and an x86 settings backend. The NSIS EXE is still x64-only.

## Package for another Windows PC

`Register-Tip.ps1` registers a DLL at its current location, so it is intended
for development. To create a self-contained home installation package after a
successful build and test, run:

```powershell
.\Package-Windows.ps1 -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86
.\Package-Windows.ps1 -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86 -Architecture x86
```

The results are x64 and x86 ZIPs. Use the package that matches the Windows OS
architecture. On the other PC, extract the entire ZIP and copy the folder to a local
`C:\` path such as `C:\KeyKeyInstaller`, and run `Install.cmd` there. Do not
install directly from a mapped network drive, NAS, or UNC path: it can become
inaccessible after UAC elevation and the installer window can close
immediately. Record any exit code; once deployment starts, diagnostics are in
`%ProgramFiles%\chichi77 KeyKey\Deployment.log`.
The elevated installer:

- copies the x64 and x86 DLLs, settings app, database, and notices to
  `C:\Program Files\chichi77 KeyKey\1.3.1-<fingerprint>`;
- registers the TSF from that permanent location; and
- adds **琦琦輸入法** to Windows Installed apps for uninstallation.

On first installation, add the keyboard in Windows Settings under Traditional
Chinese (Taiwan, Hong Kong or Macao). On upgrade, sign out and back in to load
the new DLLs; existing keyboard choices are kept. The ZIP is unsigned for trusted home
testing; Windows may warn after a download.

## Build and sign a Microsoft Store NSIS EXE

The Windows GitHub Actions workflow installs NSIS 3.12 and emits this test-only
installer in addition to the ZIP package:

```text
out\store-package\chichi77-KeyKey-1.3.1-windows-x64-setup.unsigned.exe
```

To build the same unsigned installer locally after building x64 and x86, run:

```powershell
.\Package-Store-Windows.ps1 -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86 -UnsignedTest
```

The `.unsigned.exe` artifact supports `/S` silent installation but is not
eligible for Store submission. It contains unsigned TSF DLLs and an unsigned
settings executable, and the outer installer is unsigned as well.
It retains product version `1.3.1` and installs into a fingerprinted directory
such as `C:\Program Files\chichi77 KeyKey\1.3.1-xxxxxxxxxxxx`.
Rebuilding changed binaries gets a new directory, so an existing text host
can continue using its previously loaded DLL. Signed production packages use
the same version-and-fingerprint naming scheme.

The finish page explains how users add KeyKey in Windows Settings. Installation
does not launch the settings app, enable a keyboard, or change a default.

Pushing a tag that exactly matches the repository version, such as `v1.3.1`,
automatically publishes this unsigned EXE, the ZIP package, and SHA-256 files.
The workflow uploads to the corresponding Release when it already exists, or
creates the Release when needed; it never creates the tag or overwrites an
existing asset. For recovery after a failed tag run, manually run the workflow
from the version's branch and enter the existing tag in `release_tag`. Leave
`release_tag` blank to keep the files only as a seven-day Actions artifact. The
unsigned EXE must never be used for Store submission.

The NSIS installer displays the licensing pages in this order: the mixed-license
scope map (`LICENSING.md`), the MIT terms for the original Windows TSF frontend,
then the Yahoo BSD 3-Clause terms. The scope map must stay first so the MIT page
does not imply that the bundled database or Yahoo-derived material is MIT-only.
The installed `LICENSES` directory also retains the collection and third-party
notices.

The production release path is intentionally local and interactive, so a
private key is not stored in GitHub Actions. Install NSIS 3.12 and a CA-issued
code-signing certificate that exposes its private key through the Windows
certificate store, then run:

```powershell
$thumbprint = 'YOUR_40_CHARACTER_CERTIFICATE_THUMBPRINT'
$timestampUrl = 'YOUR_CA_RFC3161_TIMESTAMP_URL'

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Package-Store-Windows.ps1 `
  -BuildDirectory .\out\build\x64-ninja `
  -X86BuildDirectory .\out\build\x86 `
  -CertificateThumbprint $thumbprint `
  -TimestampUrl $timestampUrl
```

The certificate defaults to `Cert:\CurrentUser\My`. Add
`-CertificateStoreLocation LocalMachine` if the certificate provider installed
it in `Cert:\LocalMachine\My`. Use `-MakensisPath` if NSIS is not in `PATH` or
its default installation directory. The script requires NSIS 3.12, copies the
build outputs to a temporary staging directory, signs and verifies
`KeyKeyTsf_x64.dll`, `KeyKeyTsf_x86.dll`, `KeyKeySettings.exe`, and
`KeyKeySettingsBackend.dll`, `KeyKeyDeployment.exe` and
`KeyKeyRegistration_x86.exe`, builds an
offline x64 installer, and finally signs and verifies the outer EXE. It never
edits the original build outputs and does not accept or store a PFX password.
The installed uninstaller is a copy of the signed deployment executable;
NSIS does not generate a separate unsigned uninstaller. Payload hashes are
recorded after signing, so the manifest describes the actual installed bytes.

The output is:

```text
out\store-package\chichi77-KeyKey-1.3.1-windows-x64-setup.exe
out\store-package\chichi77-KeyKey-1.3.1-windows-x64-setup.exe.sha256
```

Test the signed installer's silent installation and uninstallation on a
disposable clean Windows 11 VM before submission. NSIS treats `/S` as
case-sensitive:

```powershell
.\chichi77-KeyKey-1.3.1-windows-x64-setup.exe /S
& "$env:ProgramFiles\chichi77 KeyKey\Uninstall.exe" uninstall --quiet
```

For an EXE Store submission, Partner Center takes a versioned HTTPS package URL
rather than a direct file upload. The automated version Release contains only
the unsigned test assets. Upload the separately signed EXE as a distinct asset
to that existing Release, then use a URL such as:

```text
https://github.com/polobread/KeyKey/releases/download/v1.3.1/chichi77-KeyKey-1.3.1-windows-x64-setup.exe
```

Do not replace an asset after submitting its URL. In Partner Center select
`EXE`, architecture `x64`, and enter `/S` as the silent install parameter. The
installer and deployment tool report `0` on success, `3010` when file removal
needs a restart, `1602` on UAC cancellation, `1618` when another deployment is
running, `1633` for unsupported architecture, and `1638` for a downgrade or
stale owner. Other failures remain nonzero. Quiet removal needs an elevated
caller and uses `uninstall --quiet` (the installed ARP QuietUninstallString also
includes an owner ID). Publish a new versioned URL for every update.

## Deployment layout

```text
KeyKeyTsf_x64.dll
KeyKeyTsf_x86.dll
KeyKeySettings.exe
KeyKeySettingsBackend.dll
KeyKeyDeployment.exe
KeyKeyRegistration_x86.exe
Databases/
  KeyKey.db
LICENSES/
```

ZIP and NSIS invoke the same deployment executable and use the same layout in
`C:\Program Files\chichi77 KeyKey\1.3.1-<fingerprint>`. Repair or reinstall before
a pending reboot uses a fresh `1.3.1-<instance-id>` path. New directory names do
not contain `test` or `repair`; old directories with those labels remain
recognizable for migration. The product root holds protected state, a durable
transaction journal while installing, diagnostics and compatibility uninstall
entrypoints. Neither installer overwrites an occupied version directory.

Upgrades snapshot the product's two COM views, TSF profiles/categories and ARP
values, register the new DLLs without `/u`, then commit. Failures restore the
previous registration; interrupted transactions recover on the next deployment.
The existing shared profile is preserved, including its user enable state.
After the main installation commits, TSF APIs unregister exactly the two obsolete
Hong Kong/Macao definitions in each registry view. No user-hive scan is needed.
Users who selected a retired entry must add/select the shared entry in Windows
Settings, including choosing it again as default if desired. Deployment does not
rewrite language lists or select a replacement for users; personal data is kept.
Cleanup failure is logged and retried on rerun; it does not undo a working install.
The native registration bridge reports the actual HRESULT and failure phase.
Category snapshots read the five exact machine definition keys: TSF enumeration
can cache an empty list across DLL reloads inside the installer STA apartment.
The regression test reproduces the old 0x1 vs. required 0x1f01 failure in separate
processes, then verifies install/remove/reinstall with the corrected snapshot.
The documented hidden flag was accepted but ignored by RegisterProfile on the
Windows build used for testing, so deployment does not depend on that flag.
Earlier payloads remain while installed for existing icon references.

Uninstall checks current ownership, uses the verified new TSF maintenance APIs
instead of executing old DLLs, and deletes only inventoried, unchanged files.
Occupied payloads and maintenance files (including the running uninstaller)
are queued together for removal at restart. Empty version subdirectories are
removed or queued after their children; the shared root is never queued.
After all removals/deletion requests succeed, the app list entry is removed.
Exit 3010 asks for a restart without a second uninstall. Failures retain a retry
entry. Extra/modified files, per-user data and root diagnostic/state records stay.
`RemovalQueued` records accepted deletion requests, not proof of reboot completion. Use the current Windows Installed apps entry or a new package's
`Uninstall.cmd`; saved historical uninstallers outside the managed directory
cannot be made safe by this code. Yahoo IMM/MSI is a separate product.

`KeyKeyDeployment.exe inspect` is read-only. For package maintenance use
`install --package <extracted-directory>`, `repair --package <directory>`,
`uninstall --package <directory>` (can prepare maintenance for a legacy TSF
installation without registering the new IME), or `cleanup`. Protected/custom
legacy path inconsistencies stop automatic migration for individual diagnosis.

Runtime preferences are stored under `%APPDATA%\chichi77 KeyKey`. General
frontend settings share the PlainVanilla loader plist, while Traditional
Mandarin and associated-phrase options use their module plists. Settings are
picked up on the next key or candidate-window update. `KeyKey.db` remains
external runtime data rather than being compiled into the TSF DLL.

## Verification checklist

Test at least Notepad, Windows Terminal, Edge, Word, the lock/sign-in boundary,
and an elevated desktop application. Verify Bopomofo input, backspace, arrow
navigation, candidate paging/selection, commit with Enter/Space, focus changes,
and repeated enable/disable cycles. Also verify every Bopomofo layout, both
candidate-window orientations, all four colors, `Ctrl+\`, disabled error sound,
and the CNS11643 switch. Compare composition underlines in Notepad and another
text host, check that switching to English keeps the composed text, and verify
the taskbar mode menu and settings after signing out and back in. On upgrade,
check that Windows does not request a Simplified Chinese input dictionary.
Secure desktop and Microsoft Store app coverage should
be treated as release gates, not assumed from registration.

## License

Original Windows TSF frontend code in this directory is Copyright (c) 2026
Chui-Ping Cheng and distributed under the MIT License. OpenVanilla,
PlainVanilla, input-method modules, and the packaged database retain their
respective licenses. See `LICENSE.txt` in this directory and `LICENSING.md` at
the repository root for the complete scope map.

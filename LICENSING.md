# Licensing map

chichi77 KeyKey is a mixed-license repository. A license applies only to the
files and original material for which its copyright holder can grant rights.
A build may therefore contain material under more than one license.

## Yahoo! KeyKey source — BSD 3-Clause

The original Yahoo! KeyKey source and files derived from it remain under the
BSD 3-Clause terms in [`LICENSE.txt`](LICENSE.txt). All existing Yahoo!
copyright and license headers must be retained. This includes the legacy
frameworks, modules, data tables, utilities, preference applications, and the
existing `Source/Loaders/OSX-IMK/` implementation.

Later changes to an existing Yahoo! file do not remove the Yahoo! notice or
its BSD conditions.

## Original platform frontends — MIT

Copyright (c) 2026 Chui-Ping Cheng

Except where a file or the exceptions below state otherwise, original source,
tests, project configuration, and documentation authored for these frontends
are licensed under the MIT License:

- `Source/Loaders/Android-IME/`
- `Source/Loaders/iOS-Keyboard/`
- `Source/Loaders/Windows-TSF/`

The MIT License text for these frontends is in
[`LICENSES/MIT.txt`](LICENSES/MIT.txt). Each frontend also has a directory-level
`LICENSE.txt`, so individual source files do not need repetitive license
headers.

The MIT License applies only to the original frontend material in those
directories. It does not change the license of libraries, modules, data,
generated assets, or other material that a frontend reads, links, copies, or
packages.

## Exceptions

- The Gradle wrapper files under `Source/Loaders/Android-IME/gradle/wrapper/`,
  `gradlew`, `gradlew.bat`, and generated Gradle JVM criteria retain their
  upstream notices and licenses.
- McBopomofo data under `DataSource/McBopomofo/` remains under its MIT License.
- A generated or bundled `KeyKey.db` retains the licenses of its input data;
  packaging it with an MIT frontend does not relicense the database.
- OpenVanilla, PlainVanilla, Formosa, Manjusri, and module packages retain the
  licenses and copyright notices stated in their source files.
- OpenSSL and other third-party components retain the licenses recorded in
  [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) or their own license files.
- Product names, logos, and application icons are not licensed by this map.
  Open-source software licenses do not grant trademark rights.
- The separately maintained private `chichi77Collection` is not part of this
  repository and is not covered by any repository license.

## New macOS loader files

A genuinely new file added to `Source/Loaders/OSX-IMK/` may be licensed under
the MIT License when it is original work and contains no copied Yahoo! or
third-party code. Add its path to this map so the scope remains explicit.
Existing files in that directory are not relicensed by this rule.

## Binary distribution

A binary distribution must reproduce the applicable Yahoo BSD, frontend MIT,
and third-party notices in its documentation or other accompanying materials.
The MIT License does not require a distributor to publish modified source.

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
- `Source/Loaders/Linux-IME/`
- `Source/Loaders/Windows-TSF/`

The MIT License text for these frontends is in
[`LICENSES/MIT.txt`](LICENSES/MIT.txt). Each frontend also has a directory-level
`LICENSE.txt`, so individual source files do not need repetitive license
headers.

The MIT License applies only to the original frontend material in those
directories. It does not change the license of libraries, modules, data,
generated assets, or other material that a frontend reads, links, copies, or
packages.

## AI articles and bigram data — no license currently granted

AI-generated articles in `DataSource/AISyntheticArticles/` and AI-generated
corpora and derived bigram data, counts, and weights in
`DataSource/AISyntheticBigram/` are not currently offered under a usage license.
This includes article samples, training and validation articles, seed files,
JSONL exports, corpus snapshots, and covered portions incorporated into `KeyKey.db`.
No permission is granted for reuse, modification, redistribution, commercial use,
or model training or evaluation without separate express written permission.

See [`LICENSES/AI-DATA-NOTICE.txt`](LICENSES/AI-DATA-NOTICE.txt) and the matching
notices in both data directories for the full scope and limitations. This notice
reserves only legally protectable rights; it does not revoke valid prior grants,
restrict statutory or platform-granted rights, or relicense tools, third-party
data, or separately licensed collections such as `DataSource/chichi77Collection`.

## Exceptions

- The Gradle wrapper files under `Source/Loaders/Android-IME/gradle/wrapper/`,
  `gradlew`, `gradlew.bat`, and generated Gradle JVM criteria retain their
  upstream notices and licenses.
- McBopomofo data under `DataSource/McBopomofo/` remains under its MIT License.
- A generated or bundled `KeyKey.db` retains the licenses of its input data;
  packaging it with an MIT frontend does not relicense the database. Its covered
  AI-derived portions remain subject to the no-license notice above.
- OpenVanilla, PlainVanilla, Formosa, Manjusri, and module packages retain the
  licenses and copyright notices stated in their source files.
- Windows simplified output links the existing `OVOFHanConvert` implementation
  and both conversion tables. Their MIT and BSD notices and Encode::HanConvert
  attribution are retained in [`LICENSES/OpenVanilla-HanConvert.txt`](LICENSES/OpenVanilla-HanConvert.txt)
  and included in Windows packages.
- `Source/Loaders/Linux-IME/data/tc2sc.cin` is generated from the read-only
  OpenVanilla `VXHCTC2SCTable.c` mapping and retains that table's BSD 3-Clause
  terms and attribution, including its recorded Encode::HanConvert origin.
- `Source/Loaders/Linux-IME/gnome-panel/` contains inspected GNOME Input
  Method Panel source, the placement patch, and its packaging tools under
  GPL-2.0. The license text is in `gnome-panel/COPYING`. This directory builds
  a separate GNOME Shell package; the independent Linux engine and Fcitx addon
  remain under MIT.
- OpenSSL and other third-party components retain the licenses recorded in
  [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) or their own license files.
- Product names, logos, and application icons are not licensed by this map.
  Open-source software licenses do not grant trademark rights.
- `DataSource/chichi77Collection` is released under its own MIT License. That
  license applies only to material the copyright holder can license, including
  original selection, classification, and arrangement where copyrightable. No
  exclusive rights are claimed in common expressions, facts, public-domain
  material, or other uncopyrightable content. The collection was generated,
  inferred, and normalized automatically, has not been reviewed or corrected
  item by item, and is provided without any guarantee of accuracy or
  completeness.

## New macOS loader files

A genuinely new file added to `Source/Loaders/OSX-IMK/` may be licensed under
the MIT License when it is original work and contains no copied Yahoo! or
third-party code. Add its path to this map so the scope remains explicit.
Existing files in that directory are not relicensed by this rule.

## Binary distribution

A binary distribution must reproduce the applicable Yahoo BSD, frontend MIT,
and third-party notices in its documentation or other accompanying materials.
The MIT License does not require a distributor to publish modified source.

Preserving open-source notices alone does not authorize redistribution of the
covered AI data or database portions. Those portions require separate permission
unless the distributor already holds applicable rights.

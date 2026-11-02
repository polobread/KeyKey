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

## Original platform frontends and Guanyinma — MIT

Copyright (c) 2026 Chui-Ping Cheng

Except where a file or the exceptions below state otherwise, original source,
tests, project configuration, and documentation authored for these frontends
and the original Guanyinma shared Rust core
are licensed under the MIT License:

- `Source/Loaders/Android-IME/`
- `Source/Loaders/iOS-Keyboard/`
- `Source/Loaders/Linux-IME/`
- `Source/Loaders/Windows-TSF/`
- `Source/Shared/` (except Unicode-derived data; see below)
- `Source/Guanyinma/` (original Rust core, C ABI, and tests; source/data exceptions below)

The MIT License text for this original material is in
[`LICENSES/MIT.txt`](LICENSES/MIT.txt). Each frontend and Guanyinma also has a directory-level
`LICENSE.txt`, so individual source files do not need repetitive license
headers.

The MIT License applies only to the original frontend/core material in those
directories. It does not change the license of libraries, modules, data,
generated assets, or other material that a frontend reads, links, copies, or
packages.

## AI articles and original database content — MIT

Copyright (c) 2026 Chui-Ping Cheng

To the extent the project rights holder can grant rights, AI-generated articles
in `DataSource/AISyntheticArticles/` and AI-generated corpora and project-original
derived database content, bigram data, counts, and weights in
`DataSource/AISyntheticBigram/` are licensed under the MIT License.
This includes article samples, training and validation articles, seed files,
JSONL exports, corpus snapshots, and covered portions incorporated into `KeyKey.db`.
The grant permits reuse, modification, redistribution, commercial use, and model
training or evaluation, subject to the MIT copyright and permission notice requirements.

See [`LICENSES/AI-DATA-NOTICE.txt`](LICENSES/AI-DATA-NOTICE.txt) and the matching
notices in both data directories for the scope and full MIT License text. This grant
does not assert that AI output, individual words, facts, or statistics necessarily
qualify for copyright protection. It does not reduce valid prior grants, restrict
uses requiring no permission under law, or relicense tools, third-party
data, or separately licensed collections such as `DataSource/chichi77Collection`.

## Exceptions

- `Source/Guanyinma/src/bopomofo.rs` retains the Formosa phonetic source's
  MIT notice (Copyright (c) 2007-2010 Lukhnos D. Liu) and the BSD 3-Clause
  notice for the Yahoo-derived Hsu transcription (Copyright (c) 2007-2012
  Yahoo! Inc.). The source keeps both complete notices; copies for binary
  distribution and source provenance are in
  [Source/Guanyinma/LICENSES/Formosa-OpenVanilla-NOTICES.txt](Source/Guanyinma/LICENSES/Formosa-OpenVanilla-NOTICES.txt).
- `Source/Guanyinma/src/walker.rs` and `smart.rs` port the Yahoo Manjusri
  graph, scoring and Smart Mandarin composition rules under BSD 3-Clause.
  They retain the original notices; the Guanyinma notices file records the
  source paths. Original additions remain MIT.
- `Source/Loaders/Android-IME/app/src/main/java/tw/chichi77/keykey/android/PhraseReadingCodec.java`
  retains the Yahoo BSD 3-Clause notice from the former reading converter.
  It is limited to explicit legacy phrase-format exchange, outside the input engine.
  `Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/BopomofoKeyboardLayout.swift`
  retains its Yahoo BSD notice for frontend Hsu key classification; parsing is in Rust.
- The traditional/table state-machine port in `Source/Guanyinma/src/engine.rs`
  follows the MIT-licensed `OVIMTraditionalMandarin` and `OVIMGeneric` modules
  (Copyright (c) 2004-2010 The OpenVanilla Project). Their notice is retained in
  the same Guanyinma notices file. Original Guanyinma additions remain MIT.
- `Source/Guanyinma/build.rs` generates Rust constants from the shared Cangjie
  headers. The Unicode 16.0.0-derived canonical mappings and exclusion ranges
  retain Unicode License v3 (`Unicode-3.0`), reproduced unchanged in
  [Source/Guanyinma/LICENSES/Unicode-LICENSE.txt](Source/Guanyinma/LICENSES/Unicode-LICENSE.txt).
  The Cargo package declares the mixed MIT, BSD-3-Clause and Unicode-3.0
  contents together; this does not apply all three licenses to every file.

- `Source/Shared/CangjieUnicodeData.h` derives canonical CJK mappings and category ranges
  from Unicode 16.0.0. Its data retains Unicode License V3 in
  `Source/Shared/Unicode-LICENSE.txt`, included in desktop distributions.

- The Gradle wrapper files under `Source/Loaders/Android-IME/gradle/wrapper/`,
  `gradlew`, `gradlew.bat`, and generated Gradle JVM criteria retain their
  upstream notices and licenses.
- McBopomofo data under `DataSource/McBopomofo/` remains under its MIT License.
- A generated or bundled `KeyKey.db` retains the licenses of its input data;
  its project-original AI-derived portions are licensed under the MIT grant above.
  Packaging or combining the data does not relicense third-party portions.
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

Distributions containing the covered AI data or project-original database portions
must retain the applicable MIT copyright and permission notices. Third-party
portions of a combined database remain subject to their own license requirements.

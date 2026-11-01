"""Mobile notice catalog, selected from the actual Rust static archives.

No network access. rust-src must match the pinned compiler distribution.
License bodies are shared only when their words match after whitespace folding;
component-specific attribution and source hashes are retained separately.
"""
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in ("p", "div", "h2", "h3", "li"):
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in ("p", "div", "h2", "h3", "li"):
            self.parts.append("\n")

    def handle_data(self, data):
        self.parts.append(data)


def plain_text(html):
    reader = PlainText()
    reader.feed(html)
    return re.sub(r"\n[ \t\n]*\n", "\n\n", "".join(reader.parts)).strip()


def field(text, name):
    match = re.search(r'^' + re.escape(name) + r'\s*=\s*"([^"]+)"', text, re.M)
    if not match:
        raise RuntimeError("Missing Cargo field: " + name)
    return match.group(1)


def runtime_packages(metadata):
    packages = {p["id"]: p for p in metadata["packages"]}
    nodes = {n["id"]: n for n in metadata["resolve"]["nodes"]}
    queue, selected = [metadata["resolve"]["root"]], set()
    while queue:
        identity = queue.pop()
        package = packages[identity]
        if identity in selected or any("proc-macro" in t["kind"] for t in package["targets"]):
            continue
        selected.add(identity)
        for dep in nodes[identity]["deps"]:
            if any(kind["kind"] is None for kind in dep["dep_kinds"]):
                queue.append(dep["pkg"])
    return {i: packages[i] for i in selected}


class Catalog:
    def __init__(self, include_equal_rules=False):
        self.extended_terms = include_equal_rules
        self.rule_pattern = r"\n[-=]{20,}\s*\n" if include_equal_rules else r"\n-{20,}\s*\n"
        self.components = []
        self.licenses = {}

    def component(self, identity, name, expression, documents, source_label):
        attribution, references, sources = [], [], []
        for label, text in documents:
            if not text.strip():
                raise RuntimeError("Empty notice: " + label)
            sources.append({"path": label, "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest()})
            # Some upstream files contain several licenses separated by rules.
            for part in re.split(self.rule_pattern, text):
                part = part.strip()
                if not part:
                    continue
                # Move only recognisable, complete MIT/BSD bodies into the
                # shared store. Preserve every surrounding word and copyright.
                pattern = (r"Permission is hereby granted, free of charge,.*?SOFTWARE\."
                           r"|Redistribution and use in source and binary forms,.*?"
                           r"POSSIBILITY OF SUCH DAMAGE\.")
                if self.extended_terms:
                    pattern += r"|Apache License\s+Version 2\.0, January 2004.*?END OF TERMS AND CONDITIONS"
                matches = list(re.finditer(pattern, part, re.S))
                bodies = []
                if matches:
                    cursor = 0
                    for match in matches:
                        prefix = part[cursor:match.start()].strip()
                        if prefix and prefix not in attribution:
                            attribution.append(prefix)
                        bodies.append(match.group())
                        cursor = match.end()
                    suffix = part[cursor:].strip()
                    if suffix and suffix not in attribution:
                        attribution.append(suffix)
                else:
                    bodies.append(part)
                for body in bodies:
                    normalized = " ".join(body.split())
                    key = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
                    self.licenses.setdefault(key, {"id": key, "text": body})
                    if key not in references:
                        references.append(key)
        if self.extended_terms:
            # Vendor archives often repeat the same large third-party notice.
            # Share exact notice fragments too; short per-component copyrights
            # stay at the top, and every component keeps its own references.
            short_attribution, shared_notices = [], []
            for prefix in attribution:
                if len(prefix) <= 512:
                    short_attribution.append(prefix)
                else:
                    key = hashlib.sha256(" ".join(prefix.split()).encode("utf-8")).hexdigest()
                    self.licenses.setdefault(key, {"id": key, "text": prefix})
                    if key not in shared_notices:
                        shared_notices.append(key)
            attribution = short_attribution
            references = shared_notices + [key for key in references if key not in shared_notices]
        existing = next((c for c in self.components if c["id"] == identity), None)
        if existing is not None:
            for prefix in attribution:
                if prefix not in existing["attribution"]:
                    existing["attribution"] += "\n\n" + prefix
            existing["licenseIDs"] += [key for key in references if key not in existing["licenseIDs"]]
            existing["sources"] += [source for source in sources if source not in existing["sources"]]
        else:
            self.components.append({"id": identity, "name": name, "license": expression,
                                    "attribution": "\n\n".join(attribution), "licenseIDs": references,
                                    "source": source_label, "sources": sources})

    def files(self, identity, name, expression, paths, root):
        self.component(identity, name, expression,
                       [(p.relative_to(root).as_posix(), p.read_bytes().decode("utf-8")) for p in paths],
                       "https://github.com/polobread/KeyKey" if root.name == "KeyKey" else "Rust / Cargo source distribution")


def package_mobile(root, core, channel, sysroot, metadatas, archives, targets, output, license_files,
                   platform="ios", ndk=None, artifacts=(), audit_output=None):
    if not archives or len(archives) != len(targets):
        raise RuntimeError("Mobile notices require matching runtime archives and Rust targets")
    library = sysroot / "lib/rustlib/src/rust/library"
    if not (library / "Cargo.lock").is_file():
        raise RuntimeError("Mobile notices require rustup component add rust-src --toolchain " + channel)
    lock = (library / "Cargo.lock").read_text()
    locked = {}
    for block in lock.split("[[package]]")[1:]:
        name, version = field(block, "name"), field(block, "version")
        locked.setdefault(name.replace("-", "_"), []).append((name, version))
    runtime, std_crates, members_by_target = {}, set(), {}
    for metadata in metadatas:
        runtime.update(runtime_packages(metadata))
    for archive, target in zip(archives, targets):
        allowed = r"(?:aarch64|x86_64)-apple-ios(?:-sim)?" if platform == "ios" else r"(?:aarch64-linux-android|armv7-linux-androideabi|x86_64-linux-android|i686-linux-android)"
        if not re.fullmatch(allowed, target):
            raise RuntimeError("Not a matching mobile Rust target: " + target)
        if platform == "ios":
            command = ["xcrun", "ar"]
        else:
            command = [str(next((ndk / "toolchains/llvm/prebuilt").glob("*/bin/llvm-ar*")))]
        members = subprocess.check_output(command + ["-t", str(archive)], text=True).splitlines()
        prefixes = {m.split(".", 1)[0] for m in members}
        observed = {m.group(1) for value in prefixes
                    if (m := re.fullmatch(r"([a-zA-Z0-9_]+)-[0-9a-f]+", value))}
        # Match both crate name AND hash to this target's installed sysroot.
        standard = {p.stem[3:] for p in (sysroot / "lib/rustlib" / target / "lib").glob("lib*.rlib")}
        selected = {p.rsplit("-", 1)[0] for p in prefixes & standard}
        if not {"std", "core", "alloc", "compiler_builtins"} <= selected:
            raise RuntimeError("Cannot identify linked mobile standard-library archive members")
        std_crates.update(selected)
        expected = {p["name"].replace("-", "_") for p in runtime.values() if p["name"] != "guanyinma"}
        if not expected <= observed:
            raise RuntimeError("Runtime Cargo/archive mismatch: " + repr(sorted(expected - observed)))
        members_by_target[target] = sorted(observed)
    catalog = Catalog(include_equal_rules=platform == "android")
    repository = [
        ("keykey", "琦琦輸入法／Guanyinma", "MIT", ["Source/Guanyinma/LICENSE.txt"]),
        ("yahoo", "Yahoo! KeyKey", "BSD-3-Clause", ["LICENSE.txt"]),
        ("formosa", "Formosa／OpenVanilla 衍生程式", "MIT AND BSD-3-Clause", ["Source/Guanyinma/LICENSES/Formosa-OpenVanilla-NOTICES.txt"]),
        ("unicode", "Unicode 資料", "Unicode-3.0", ["Source/Guanyinma/LICENSES/Unicode-LICENSE.txt"]),
        ("mcbopomofo", "McBopomofo 詞庫", "MIT", ["DataSource/McBopomofo/LICENSE.txt"]),
        ("ai-data", "專案原創語料與詞庫內容", "MIT", ["DataSource/AISyntheticBigram/LICENSE.txt"]),
        ("collection", "chichi77Collection 詞彙整理", "MIT", ["DataSource/chichi77Collection/LICENSE.txt"]),
    ]
    for identity, name, expression, paths in repository:
        catalog.files(identity, name, expression, [root / p for p in paths], root)
    for package in sorted(runtime.values(), key=lambda p: (p["name"], p["version"])):
        if package["name"] == "guanyinma":
            continue
        directory = Path(package["manifest_path"]).parent
        files = set(license_files(directory))
        if package["license_file"]:
            files.add(directory / package["license_file"])
        if not files:
            raise RuntimeError("Missing runtime crate notices: " + package["name"])
        catalog.files("cargo-" + package["name"], package["name"] + " " + package["version"],
                      package["license"], sorted(files), directory)
        component = catalog.components[-1]
        component["source"] = package.get("repository") or package.get("source") or component["source"]
        if package.get("authors"):
            component["attribution"] += "\n\nAuthors: " + "; ".join(package["authors"])

    # Keep in-tree copyrights/Unicode exceptions, excluding the explicit Fuchsia-only source.
    html = (sysroot / "share/doc/rust/COPYRIGHT-library.html").read_text()
    in_tree = html.split('<h2 id="in-tree-files">', 1)[1].split('<h2 id="out-of-tree-dependencies">', 1)[0]
    in_tree, excluded = re.subn(r'<div[^>]*>\s*<p>\s*<b>File/Directory:</b> <code>library/std/src/sys/sync/mutex/fuchsia.rs</code>.*?</div>', "", in_tree, flags=re.S)
    if excluded != 1:
        raise RuntimeError("Rust in-tree exceptions changed; review mobile attribution scope")
    attribution = plain_text(in_tree)
    if "BSD-2-Clause" in attribution:
        raise RuntimeError("Unreviewed Rust in-tree license exception")
    mit = (sysroot / "share/doc/rust/licenses/MIT.txt").read_text()
    mit = mit[mit.index("Permission is hereby granted"):]
    unicode = (core / "LICENSES/Unicode-LICENSE.txt").read_text()
    catalog.component("rust", "Rust 標準函式庫 " + channel, "MIT AND Unicode-3.0",
                      [("Rust/COPYRIGHT-library.html (" + ("iOS" if platform == "ios" else "Android") + " in-tree notices)", attribution + "\n\n" + mit),
                       ("Rust/Unicode-3.0", unicode)], "https://github.com/rust-lang/rust")
    internal = {"std", "core", "alloc", "panic_unwind", "unwind", "rustc_std_workspace_core",
                "rustc_std_workspace_alloc", "rustc_std_workspace_std"}
    for crate in sorted(std_crates - internal):
        candidates = locked.get(crate, [])
        if len(candidates) != 1:
            raise RuntimeError("Cannot identify Rust source version: " + crate)
        name, version = candidates[0]
        if crate == "compiler_builtins":
            directory = library / "compiler-builtins"
            manifest = directory / "compiler-builtins/Cargo.toml"
        elif crate == "std_detect":
            directory = library / "std_detect"
            manifest = directory / "Cargo.toml"
        else:
            directory = library / "vendor" / (name + "-" + version)
            manifest = directory / "Cargo.toml"
        source = manifest.read_text()
        if field(source, "version") != version:
            raise RuntimeError("Rust source version mismatch: " + name)
        expression = field(source, "license")
        files = license_files(directory)
        if crate == "std_detect" and not files:
            # Original stdarch material uses the Rust project MIT option.
            catalog.component("rust-" + crate, name + " " + version, expression,
                              [("Rust/library/std_detect", "Authors: " + re.search(r"authors\s*=\s*(\[.*?\])", source, re.S).group(1) + "\nCopyright (c) The Rust Project Contributors\n\n" + mit)],
                              "https://github.com/rust-lang/stdarch")
        elif not files:
            raise RuntimeError("Missing Rust runtime notices: " + name)
        else:
            same_runtime = any(p["name"] == name and p["version"] == version for p in runtime.values())
            identity = "cargo-" + name if same_runtime else "rust-" + crate
            catalog.files(identity, name + " " + version + "（Rust）", expression, files, library)
        if crate == "compiler_builtins":
            # compiler-builtins/src/math/mod.rs includes this source directly;
            # it is not represented by a separate rlib/Cargo dependency.
            catalog.files("rust-libm", "libm（compiler-builtins 數學函式）", "MIT",
                          [library / "compiler-builtins/libm/LICENSE.txt"], library)

    if platform == "android":
        from android_runtime_notices import add_android_notices
        android_audit = add_android_notices(catalog, core, ndk, runtime, archives, artifacts)
    data = {"schemaVersion": 1, "components": catalog.components, "licenses": list(catalog.licenses.values())}
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    texts = ["琦琦輸入法 " + ("iOS" if platform == "ios" else "Android") + " 授權與致謝\n本產品以 Yahoo! KeyKey 為基礎，但不是 Yahoo 官方產品。\n"]
    for component in catalog.components:
        texts.append(component["name"] + "\n" + component["license"] + "\n" + component["attribution"] +
                     "\n條款：" + ", ".join(component["licenseIDs"]))
    for body in catalog.licenses.values():
        texts.append("條款 " + body["id"] + "\n" + body["text"])
    output.write_text("\n\n".join(texts) + "\n", encoding="utf-8")
    output.with_suffix(".json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    audit = {"rust": channel, "targets": members_by_target, "standardLibraryCrates": sorted(std_crates),
             "runtimeCargoPackages": sorted(p["name"] + " " + p["version"] for p in runtime.values()),
             "systemLibraries": {"provider": "SQLite, iconv and libunwind are supplied by iOS, not redistributed",
                                 "sqliteUpstream": "https://www.sqlite.org/copyright.html"},
             "sourceLockSHA256": hashlib.sha256((library / "Cargo.lock").read_bytes()).hexdigest(),
             "excluded": ["Cargo build/dev/proc-macro dependencies", "unused Rust distribution crates and license catalog", "Fuchsia-only std source", "desktop updater/OpenSSL/HanConvert notices", "other-platform frontends"]}
    if platform == "android":
        audit["systemLibraries"] = {"provider": "Android platform C/Java APIs supplied by OS; SQLite/C++ runtime bundled"}
        audit.update(android_audit)
    audit_path = audit_output or output.with_suffix(".audit.json")
    audit_path.parent.mkdir(parents=True, exist_ok=True)
    audit_path.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
    print(platform + " notices: %d components, %d shared text blocks, %d bytes" %
          (len(catalog.components), len(catalog.licenses), output.stat().st_size))


def package_ios(*args, **kwargs):
    return package_mobile(*args, **kwargs)

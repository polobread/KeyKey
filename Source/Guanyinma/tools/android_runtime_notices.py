"""Android-specific bundled runtimes and resolved Java artifacts, without network access."""
import hashlib
import io
import json
from pathlib import Path
import re
import zipfile

NDK_BASE = "3c92011b600bdf70424e2547594dd461fe411a41"
UNWIND_SHA = "b5efebcaca80879234098e52d1725e6d9eb8fb96a19fce625d39184b705f7b6d"


def coordinate(path):
    parts = path.parts
    try:
        index = parts.index("files-2.1")
    except ValueError as error:
        raise RuntimeError("Cannot identify runtime artifact coordinates: " + str(path)) from error
    return ":".join(parts[index + 1:index + 4])


def vendor_notices(archive):
    if "third_party_licenses.json" not in archive.namelist():
        return {}
    metadata = json.loads(archive.read("third_party_licenses.json"))
    raw = archive.read("third_party_licenses.txt")
    result = {}
    for name, span in metadata.items():
        start, length = span["start"], span["length"]
        if start < 0 or length <= 0 or start + length > len(raw):
            raise RuntimeError("Invalid upstream notice span: " + name)
        result[name] = raw[start:start + length].decode("utf-8")
    return result


def embedded_notices(archive):
    documents = []
    for name in archive.namelist():
        if re.search(r"(?:^|/)(?:LICENSE[^/]*|NOTICE[^/]*|COPYING[^/]*|COPYRIGHT[^/]*)$", name, re.I) and not name.endswith("/"):
            documents.append((name, archive.read(name).decode("utf-8")))
    if "classes.jar" in archive.namelist():
        with zipfile.ZipFile(io.BytesIO(archive.read("classes.jar"))) as nested:
            documents.extend(("classes.jar/" + n, text) for n, text in embedded_notices(nested))
    return documents


def add_android_notices(catalog, core, ndk, runtime, archives, artifacts):
    if ndk is None or not artifacts:
        raise RuntimeError("Android notices require NDK and resolved runtime artifacts")
    toolchain = next((ndk / "toolchains/llvm/prebuilt").glob("*/NOTICE")).parent
    revision = re.search(r"^Pkg.Revision\s*=\s*(.+)$", (ndk / "source.properties").read_text(), re.M).group(1).strip()
    if NDK_BASE not in (toolchain / "clang_source_info.md").read_text():
        raise RuntimeError("NDK LLVM source changed; re-audit bundled libunwind notice")
    unwind = core / "LICENSES/android-ndk/libunwind-LICENSE.txt"
    if hashlib.sha256(unwind.read_bytes()).hexdigest() != UNWIND_SHA:
        raise RuntimeError("Pinned libunwind source notice changed")
    notice = (toolchain / "NOTICE").read_text()
    starts = list(re.finditer(r"^={10,}\nThe LLVM Project is under the Apache License v2.0 with LLVM Exceptions:", notice, re.M))
    sections = [notice[m.start():starts[i + 1].start() if i + 1 < len(starts) else len(notice)] for i, m in enumerate(starts)]
    for name in ("compiler_rt", "libc++", "libc++abi"):
        selected = [part for part in sections if "The " + name + " library is dual licensed" in part]
        if len(selected) != 1:
            raise RuntimeError("Cannot identify NDK runtime notice: " + name)
        catalog.component("ndk-" + name, "NDK " + name + " " + revision,
                          "Apache-2.0 WITH LLVM-exception／MIT／NCSA",
                          [("NDK/NOTICE (" + name + ")", selected[0])], "https://github.com/llvm/llvm-project")
    catalog.component("ndk-libunwind", "NDK libunwind " + revision, "Apache-2.0 WITH LLVM-exception／MIT／NCSA",
                      [("llvm-project/" + NDK_BASE + "/libunwind/LICENSE.TXT", unwind.read_text())],
                      "https://github.com/llvm/llvm-project/tree/" + NDK_BASE)
    # libc++ static, ABI and unwinder archives are the configured CMake runtime.
    native = {}
    for abi in ("aarch64-linux-android", "arm-linux-androideabi", "i686-linux-android", "x86_64-linux-android"):
        for name in ("libc++_static.a", "libc++abi.a"):
            path = toolchain / "sysroot/usr/lib" / abi / name
            native[abi + "/" + name] = hashlib.sha256(path.read_bytes()).hexdigest()
        clang_runtime = next(toolchain.glob("lib/clang/*/lib/linux"))
        architecture = {"aarch64-linux-android": "aarch64", "arm-linux-androideabi": "arm", "i686-linux-android": "i386", "x86_64-linux-android": "x86_64"}[abi]
        unwind_archive = clang_runtime / architecture / "libunwind.a"
        native[abi + "/libunwind.a"] = hashlib.sha256(unwind_archive.read_bytes()).hexdigest()
        builtins_arch = "i686" if architecture == "i386" else architecture
        builtins = clang_runtime / ("libclang_rt.builtins-" + builtins_arch + "-android.a")
        native[abi + "/compiler-rt.a"] = hashlib.sha256(builtins.read_bytes()).hexdigest()
    sqlite_package = next(p for p in runtime.values() if p["name"] == "libsqlite3-sys")
    sqlite = Path(sqlite_package["manifest_path"]).parent / "sqlite3/sqlite3.c"
    import subprocess
    archiver = next(toolchain.glob("bin/llvm-ar*"))
    for archive in archives:
        members = subprocess.check_output([str(archiver), "-t", str(archive)], text=True)
        if "-sqlite3.o" not in members:
            raise RuntimeError("Bundled SQLite object missing: " + str(archive))
    source = sqlite.read_text()
    version = re.search(r'^#define SQLITE_VERSION\s+"([^"]+)"', source, re.M).group(1)
    blessing = next(c for c in re.findall(r"/\*.*?\*/", source, re.S)
                    if "The author disclaims copyright to this source code." in c)
    catalog.component("sqlite", "SQLite " + version, "Public domain",
                      [("libsqlite3-sys/sqlite3/sqlite3.c", blessing)], "https://www.sqlite.org/copyright.html")
    artifacts = sorted(set(artifacts), key=coordinate)
    billing = next((p for p in artifacts if coordinate(p).startswith("com.android.billingclient:billing:")), None)
    if billing is None:
        raise RuntimeError("Resolved Billing runtime is missing")
    apache_source = next(p for p in artifacts if coordinate(p) == "androidx.core:core:1.15.0")
    with zipfile.ZipFile(apache_source) as archive:
        apache_document = next((name, text) for name, text in embedded_notices(archive) if "Apache License" in text)
    review = json.loads((core / "tools/android-runtime-license-review.json").read_text())["artifacts"]
    artifact_audit = []
    for artifact in artifacts:
        identity = coordinate(artifact)
        declaration = review.get(identity)
        if declaration is None:
            raise RuntimeError("Unreviewed publisher license: " + identity)
        declared_apache = all("apache.org/licenses/LICENSE-2.0" in item["url"] for item in declaration["licenses"])
        with zipfile.ZipFile(artifact) as archive:
            documents = embedded_notices(archive)
            bundled = vendor_notices(archive)
        if bundled:
            # Preserve the provider's complete notices for its shipped/obfuscated
            # code; do not guess away subcomponents by class-name inspection.
            documents += [("third_party_licenses/" + name, name + "\n\n" + text) for name, text in sorted(bundled.items())]
        if not documents:
            if not declared_apache:
                raise RuntimeError("No complete notices for Android runtime: " + identity)
            documents = [(coordinate(apache_source) + "/" + apache_document[0], apache_document[1])]
        group, name, version = identity.split(":")
        prefix = "AndroidX " if group.startswith("androidx.") else ""
        label = prefix + name + " " + version
        if group == "com.android.billingclient": label = "Google Play Billing " + version
        catalog.component("android-" + identity, label, "Apache-2.0" if declared_apache else "Google SDK 授權與隨附第三方聲明",
                          [(identity + "/" + n, text) for n, text in documents],
                          "https://maven.google.com" if identity.startswith(("androidx.", "com.google.", "com.android.")) else "https://repo.maven.apache.org/maven2")
        artifact_audit.append({"coordinate": identity, "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
                               "publisherLicenseReview": declaration,
                               "noticeSource": "embedded plus vendor notices" if bundled else "embedded or standard Apache-2.0, per reviewed publisher POM"})
    return {"ndkVersion": revision, "ndkLLVMBase": NDK_BASE, "ndkRuntimeArchives": native,
            "javaRuntimeArtifacts": artifact_audit, "sqliteVersion": version,
            "vendorNoticePolicy": "Preserve complete vendor notices for bundled/obfuscated code; no inferred removal",
            "sqliteSourceSHA256": hashlib.sha256(sqlite.read_bytes()).hexdigest()}

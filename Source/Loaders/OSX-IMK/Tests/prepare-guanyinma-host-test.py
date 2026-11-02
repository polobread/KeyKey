#!/usr/bin/env python3
"""Prepare a namespaced Rust-only IMK app and a real NSTextView manual host.

prepare/build/verify never install, launch, or call TIS register/enable/select.
Xcode can register raw build apps with LaunchServices; the manual host validates
and re-registers the exact installed app before any TIS operation.
The separate stage command only copies the verified app to the per-user Input
Methods directory. TIS mutations require the host's explicit activation button.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys

TESTS = Path(__file__).resolve().parent
SOURCE = TESTS.parents[2]
ROOT = SOURCE.parent
MODEL_REL = Path("Distributions/Takao/CookedDatabase/KeyKey.db")
MAIN_PLIST = Path("Loaders/OSX-IMK/Takao-Info.plist")
APP_NAME = "chichi77 KeyKey.app"
SKIP = {"target", "build", ".build", "out", ".gradle", ".cxx", ".kotlin", ".swiftpm",
        "node_modules", "__pycache__", ".DS_Store", "DerivedData", "Intermediates"}
# Only identity/metadata files in the private source copy may change. Algorithms,
# module identifiers, the Rust crate and the database keep their original bytes.
NAMESPACE_FILES = (
    "Loaders/OSX-IMK/OpenVanillaController.mm",
    "Loaders/OSX-IMK/CVApplicationController.mm",
    "PreferenceApplications/OSX/TakaoSettings.h",
    "PreferenceApplications/OSX/TakaoAbout.m",
    "PreferenceApplications/OSX/TakaoPhraseCollections.m",
    "PreferenceApplications/OSX/TakaoPhrases.m",
    "PreferenceApplications/OSX/Info.plist",
    "PreferenceApplications/DownloadUpdateOSX/Info.plist",
    "Utilities/PhraseEditor/OSX/Info.plist",
)
UPDATE_KEYS = ("SUFeedURL", "KeyKeyBetaFeedURL", "SUPublicEDKey", "CFBundleURLTypes")
CODE_SUFFIXES = {".m", ".mm", ".h", ".hpp", ".cpp", ".c", ".rs", ".toml", ".lock", ".xcconfig", ".pbxproj", ".plist", ".strings", ".py", ".sh", ".rb"}


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def run(command, *, cwd=None, env=None, log=None):
    if log is None:
        return subprocess.run(command, cwd=cwd, env=env, check=True)
    with log.open("ab") as stream:
        stream.write(("\n$ " + shlex.join(map(str, command)) + "\n").encode())
        stream.flush()
        return subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                              stderr=subprocess.STDOUT, check=True)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def plist(path):
    return plistlib.loads(path.read_bytes())


def identities(tag):
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,39}", tag):
        raise ValueError("tag must be 1–40 lowercase letters, digits or hyphens")
    prefix = "io.github.polobread.guanyinma.imktest." + tag
    bundle_id = prefix + ".inputmethod.KeyKey"
    return dict(tag=tag, bundle_id=bundle_id, source_id=bundle_id,
                loader_identifier=prefix + ".loader", loader_name="KeyKey-Guanyinma-IMK-Test-" + tag,
                server_name=bundle_id + "_Connection",
                do_name="GuanyinmaIMKTestService_" + tag,
                host_bundle_id=prefix + ".host")


def install_path(identity):
    return Path.home() / "Library/Input Methods" / ("KeyKey Guanyinma IMK Test " + identity["tag"] + ".app")


def macro_flags(identity):
    values = {
        "OPENVANILLA_CONNECTION_NAME": '@"' + identity["server_name"] + '"',
        "OPENVANILLA_DO_CONNECTION_NAME": '@"' + identity["do_name"] + '"',
        "PVLOADERPOLICY_LOADER_IDENTIFIER": '"' + identity["loader_identifier"] + '"',
        "PVLOADERPOLICY_LOADER_NAME": '"' + identity["loader_name"] + '"',
    }
    flags = []
    for name, value in values.items():
        flags.extend(["-U" + name, "-D" + name + "=" + value])
    return flags


def code_hashes(source):
    result = {}
    for folder, dirs, files in os.walk(source):
        dirs[:] = sorted(d for d in dirs if d not in SKIP)
        for name in sorted(files):
            path = Path(folder) / name
            if path.suffix in CODE_SUFFIXES and not path.is_symlink():
                result[str(path.relative_to(source))] = digest(path)
    return result


def private_namespace(source, identity):
    replacements = (
        ("io.github.polobread.inputmethod.chichi77", identity["bundle_id"]),
        ("io.github.polobread.chichi77", identity["loader_identifier"]),
    )
    changed = []
    for name in NAMESPACE_FILES:
        path = source / name
        before = path.read_text(encoding="utf-8")
        after = before
        for old, new in replacements:
            after = after.replace(old, new)
        if after == before:
            raise ValueError("namespace allowlist no longer matches source: " + name)
        path.write_text(after, encoding="utf-8")
        changed.append(name)
    path = source / MAIN_PLIST
    info = plist(path)
    info.update(CFBundleIdentifier=identity["bundle_id"], TISInputSourceID=identity["source_id"],
                InputMethodConnectionName=identity["server_name"],
                CFBundleDisplayName="Guanyinma IMK Test " + identity["tag"],
                KeyKeyIsolatedIMKTest=identity["tag"],
                KeyKeyIsolatedLoaderIdentifier=identity["loader_identifier"],
                KeyKeyIsolatedLoaderName=identity["loader_name"],
                KeyKeyIsolatedDOName=identity["do_name"])
    for key in UPDATE_KEYS:
        info.pop(key, None)
    path.write_bytes(plistlib.dumps(info))
    changed.append(str(MAIN_PLIST))
    for path in (source / "Loaders/OSX-IMK").glob("*.lproj/InfoPlist.strings"):
        label = "Guanyinma IMK Test " + identity["tag"]
        path.write_text('CFBundleName = "' + label + '";\nCFBundleDisplayName = "' + label + '";\n' +
                        identity["bundle_id"] + ' = "' + label + '";\n', encoding="utf-8")
        changed.append(str(path.relative_to(source)))
    return sorted(changed)


def prepare(args):
    tag = args.tag or datetime.now().strftime("%Y%m%d-%H%M%S-") + secrets.token_hex(3)
    identity = identities(tag)
    output = (args.output or ROOT / "Installer/local-builds" / ("guanyinma-imk-host-" + tag)).resolve()
    if output == SOURCE or SOURCE in output.parents:
        raise ValueError("output must be outside Source to avoid recursive source copies")
    if output.exists():
        raise ValueError("output must be a new directory; use build/verify for an existing snapshot")
    output.mkdir(parents=True)
    source = output / "private/Source"
    print("Copying source to", source, flush=True)
    shutil.copytree(SOURCE, source, symlinks=True,
                    ignore=lambda directory, names: [name for name in names if name in SKIP])
    originals = code_hashes(source)
    before = digest(SOURCE / MODEL_REL)
    if digest(source / MODEL_REL) != before:
        raise ValueError("snapshot database differs from source")
    changed = private_namespace(source, identity)
    snapshot = code_hashes(source)
    unexpected = [name for name in originals if originals[name] != snapshot.get(name) and name not in changed]
    if unexpected:
        raise ValueError("unexpected source edits: " + repr(unexpected))
    update = output / "private/update"
    update.mkdir()
    for name in ("prepare.py", "channels.py", "sign-macos.py"):
        shutil.copy2(ROOT / "update" / name, update / name)
    cache = ROOT / "update/.cache/macos-2.10.0"
    if not (cache / "Sparkle.framework").is_dir():
        raise ValueError("pinned Sparkle SDK is not cached; prepare it by the documented macOS build flow first")
    (update / ".cache").mkdir()
    # Read-only build dependency. embed-macos copies it into our own output.
    (update / ".cache/macos-2.10.0").symlink_to(cache, target_is_directory=True)
    config = dict(schema_version=1, public_ed25519_key="", macos_feed_url="",
                  windows_x64_feed_url="", windows_x86_feed_url="",
                  macos_beta_feed_url="", windows_x64_beta_feed_url="", windows_x86_beta_feed_url="")
    write_json(update / "config.json", config)
    manifest = dict(schema_version=1, state="prepared", created_at=datetime.now(timezone.utc).isoformat(),
                    identity=identity, original_source=str(SOURCE), private_source=str(source),
                    output=str(output), install_path=str(install_path(identity)),
                    model_sha256=before, source_hashes=snapshot, namespace_edits=changed,
                    original_code_hashes=originals,
                    version=plist(SOURCE / MAIN_PLIST)["CFBundleShortVersionString"],
                    note="No TIS operation, install, input method launch or profile read has occurred.")
    write_json(output / "manifest.json", manifest)
    print("Prepared only:", output / "manifest.json")


def load_manifest(output):
    output = output.resolve(strict=True)
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    identity = identities(manifest["identity"]["tag"])
    if (manifest.get("schema_version") != 1 or manifest["identity"] != identity or
            Path(manifest["output"]) != output or
            Path(manifest["private_source"]) != output / "private/Source" or
            Path(manifest["install_path"]) != install_path(identity)):
        raise ValueError("invalid isolated-test manifest identity/path")
    return output, manifest


def check_snapshot(manifest):
    source = Path(manifest["private_source"])
    actual = code_hashes(source)
    if actual != manifest["source_hashes"]:
        changes = [name for name in sorted(set(actual) | set(manifest["source_hashes"]))
                   if actual.get(name) != manifest["source_hashes"].get(name)]
        raise ValueError("private source changed after preparation: " + repr(changes[:20]))
    if digest(source / MODEL_REL) != manifest["model_sha256"]:
        raise ValueError("private model changed after preparation")


def check_app(app, manifest):
    if app.is_symlink() or not app.is_dir():
        raise ValueError("expected a real isolated app directory")
    identity = manifest["identity"]
    info = plist(app / "Contents/Info.plist")
    expected = dict(CFBundleIdentifier=identity["bundle_id"], TISInputSourceID=identity["source_id"],
                    InputMethodConnectionName=identity["server_name"],
                    KeyKeyIsolatedIMKTest=identity["tag"],
                    KeyKeyIsolatedLoaderIdentifier=identity["loader_identifier"],
                    KeyKeyIsolatedLoaderName=identity["loader_name"], KeyKeyIsolatedDOName=identity["do_name"])
    if any(info.get(key) != value for key, value in expected.items()) or any(key in info for key in UPDATE_KEYS):
        raise ValueError("isolated app metadata is not correctly namespaced/network-disabled")
    executable = info["CFBundleExecutable"]
    if Path(executable).name != executable:
        raise ValueError("invalid executable name")
    binary = app / "Contents/MacOS" / executable
    data = binary.read_bytes()
    for name in ("loader_identifier", "loader_name", "server_name", "do_name"):
        if identity[name].encode() not in data:
            raise ValueError("compiled identity missing: " + name)
    for value in (b"chichi77Service\0", b"chichi77_1_Connection\0", b"io.github.polobread.chichi77\0"):
        if value in data:
            raise ValueError("production profile/connection identity survived in the compiled loader")
    databases = list(app.rglob("KeyKey.db"))
    if len(databases) != 1 or digest(databases[0]) != manifest["model_sha256"]:
        raise ValueError("app must contain exactly one unchanged copy of KeyKey.db")
    if os.stat(databases[0]).st_ino == os.stat(Path(manifest["original_source"]) / MODEL_REL).st_ino:
        raise ValueError("database must be a copied file, not the formal model inode")
    for relative, suffix in (("Contents/SharedSupport/Preferences.app", ".Preferences"),
                             ("Contents/SharedSupport/PhraseEditor.app", ".PhraseEditor")):
        child = app / relative
        if child.exists() and plist(child / "Contents/Info.plist")["CFBundleIdentifier"] != identity["bundle_id"] + suffix:
            raise ValueError("child bundle identity is not isolated: " + relative)
    run(["codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app)])
    return binary, databases[0]


def build(args):
    output, manifest = load_manifest(args.output)
    check_snapshot(manifest)
    source = Path(manifest["private_source"])
    identity = manifest["identity"]
    env = os.environ.copy()
    env["KEYKEY_UPDATE_CONFIG"] = str(output / "private/update/config.json")
    env["KEYKEY_GUANYINMA_OFFLINE"] = "1"
    if args.cargo:
        cargo = Path(args.cargo).absolute()
        if not cargo.is_file() or not os.access(cargo, os.X_OK):
            raise ValueError("cargo must be an executable file")
        # rustup chooses its proxy command from argv[0]; preserve cargo symlinks.
        env["CARGO"] = str(cargo)
    # Preserve all module-ID/GCC definitions. These four -U/-D pairs follow the
    # target's own definitions in compiler flags and never replace that list.
    flags = "$(inherited) " + shlex.join(macro_flags(identity))
    command = ["xcodebuild", "-project", str(source / "Takao.xcodeproj"),
               "-target", "Takao (Loader OSX-IMK)", "-configuration", "Release",
               "-xcconfig", str(source / "Takao-macOS.xcconfig"),
               "SYMROOT=" + str(output / "products"), "OBJROOT=" + str(output / "objects"),
               "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO",
               "OTHER_CFLAGS=" + flags,
               "OTHER_CPLUSPLUSFLAGS=" + flags, "build"]
    print("Building isolated snapshot; log:", output / "build.log", flush=True)
    run(command, cwd=source, env=env, log=output / "build.log")
    built = output / "products/Release" / APP_NAME
    app = output / ("KeyKey Guanyinma IMK Test " + identity["tag"] + ".app")
    if app.exists():
        # Only the exact generated app inside this manifest-owned output.
        shutil.rmtree(app)
    shutil.copytree(built, app, symlinks=True)
    info_path = app / "Contents/Info.plist"
    info = plist(info_path)
    for key in UPDATE_KEYS:
        info.pop(key, None)
    info_path.write_bytes(plistlib.dumps(info))
    for framework in (app / "Contents/Frameworks").glob("*.framework"):
        if framework.name == "Sparkle.framework":
            continue
        for headers in (framework / "Headers", framework / "Versions/A/Headers"):
            if headers.is_symlink():
                headers.unlink()
            elif headers.exists():
                shutil.rmtree(headers)
    run([sys.executable, str(output / "private/update/sign-macos.py"), str(app), "-"],
        log=output / "sign.log")
    binary, database = check_app(app, manifest)
    host = output / "Manual Guanyinma IMK Host.app"
    (host / "Contents/MacOS").mkdir(parents=True, exist_ok=True)
    (host / "Contents/Resources").mkdir(exist_ok=True)
    host_binary = host / "Contents/MacOS/ManualGuanyinmaHost"
    run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Wno-deprecated-declarations",
         "-Wno-unused-parameter", "-mmacosx-version-min=15.0", "-arch", "arm64", "-framework", "Cocoa",
         "-framework", "Carbon", "-framework", "CoreServices", str(source / "Loaders/OSX-IMK/Tests/ManualGuanyinmaHost.m"),
         "-o", str(host_binary)], log=output / "host-build.log")
    config = dict(identity, schema_version=1, install_path=manifest["install_path"],
                  database_relative_path=str(database.relative_to(app)),
                  database_sha256=manifest["model_sha256"], executable_sha256=digest(binary),
                  log_path=str(output / "host-events.jsonl"), recovery_path=str(output / "restore-state.plist"))
    (host / "Contents/Resources/HostConfiguration.plist").write_bytes(plistlib.dumps(config))
    host_info = dict(CFBundleIdentifier=identity["host_bundle_id"], CFBundleExecutable="ManualGuanyinmaHost",
                     CFBundleName="Guanyinma IMK Host " + identity["tag"], CFBundlePackageType="APPL",
                     CFBundleVersion=manifest["version"], CFBundleShortVersionString=manifest["version"],
                     NSPrincipalClass="NSApplication", LSMinimumSystemVersion="15.0",
                     NSHighResolutionCapable=True, NSHumanReadableCopyright="KeyKey manual test host")
    (host / "Contents/Info.plist").write_bytes(plistlib.dumps(host_info))
    run(["codesign", "--force", "--sign", "-", str(host)], log=output / "sign.log")
    run(["codesign", "--verify", "--deep", "--strict", str(host)])
    check_snapshot(manifest)
    if digest(Path(manifest["original_source"]) / MODEL_REL) != manifest["model_sha256"]:
        raise ValueError("formal source DB changed while preparing; do not stage this run")
    manifest.update(state="built", app=str(app), host=str(host),
                    executable_sha256=digest(binary), host_executable_sha256=digest(host_binary),
                    database_relative_path=str(database.relative_to(app)))
    write_json(output / "manifest.json", manifest)
    print("Built and verified; NOT installed/registered/launched:", app, "\nHost:", host)


def verify(output):
    output, manifest = load_manifest(output)
    if manifest["state"] != "built":
        raise ValueError("build has not completed")
    check_snapshot(manifest)
    app = Path(manifest["app"])
    if app.parent != output or Path(manifest["host"]).parent != output:
        raise ValueError("artifact paths escaped the isolated output")
    binary, database = check_app(app, manifest)
    if digest(binary) != manifest["executable_sha256"]:
        raise ValueError("input method executable changed after build")
    host = Path(manifest["host"])
    if digest(host / "Contents/MacOS/ManualGuanyinmaHost") != manifest["host_executable_sha256"]:
        raise ValueError("manual host changed after build")
    config = plist(host / "Contents/Resources/HostConfiguration.plist")
    if any(config.get(key) != value for key, value in manifest["identity"].items()) or \
       config.get("executable_sha256") != manifest["executable_sha256"] or \
       config.get("database_sha256") != manifest["model_sha256"] or \
       config.get("install_path") != manifest["install_path"]:
        raise ValueError("manual host configuration differs from the reviewed manifest")
    run(["codesign", "--verify", "--deep", "--strict", str(host)])
    print("Verified isolated artifacts; no TIS operation performed.")
    return output, manifest


def stage(args):
    output, manifest = verify(args.output)
    destination = Path(manifest["install_path"])
    if destination.exists() or destination.is_symlink():
        raise ValueError("test install path already exists; restore/stop the old test first and remove only its verified test app")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.parent.resolve() != destination.parent:
        raise ValueError("per-user Input Methods directory must not be a symlink")
    shutil.copytree(Path(manifest["app"]), destination, symlinks=True)
    check_app(destination, manifest)
    print("Staged only:", destination, "\nNo launch/registration/enable/selection occurred.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare", help="copy/namespace source only; no build or TIS")
    p.add_argument("--tag")
    p.add_argument("--output", type=Path)
    p = sub.add_parser("build", help="build/sign private snapshot and host; no install or TIS")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--cargo", help="pinned cargo executable; CARGO_HOME/RUSTUP_HOME retain caller values")
    for name in ("verify", "stage"):
        p = sub.add_parser(name, help="verify only" if name == "verify" else "copy verified app into per-user Input Methods; no TIS")
        p.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("requires macOS/Xcode")
    try:
        if args.command == "prepare": prepare(args)
        elif args.command == "build": build(args)
        elif args.command == "verify": verify(args.output)
        elif args.command == "stage": stage(args)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print("error:", error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

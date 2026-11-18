#!/usr/bin/env python3
"""Run the complete selected X11 matrix in independent, persistent sessions.

This entry point also accepts staged addon/host environment variables directly;
unlike run-x11-e2e.sh it never installs files into /usr. Use a fresh artifact
directory. KEYKEY_E2E_WORKERS defaults to four (one retains serial scheduling).
"""

import ctypes
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET


SESSION = Path(__file__).resolve().with_name("run-x11-e2e-session.sh")
LINUX_DIR = SESSION.parent.parent


def selected_cases(env):
    """Keep all/filter/config-UI selection in the session runner itself."""
    result = subprocess.run(
        ["bash", str(SESSION), "--list-cases"], env=env, cwd=LINUX_DIR,
        text=True, stdout=subprocess.PIPE, check=True,
    )
    cases = result.stdout.splitlines()
    if not cases or any(not case for case in cases) or len(cases) != len(set(cases)):
        raise ValueError("The X11 selector returned an empty or duplicate case list.")
    return cases


def partition(cases, count):
    shards = [cases[index::min(count, len(cases))]
              for index in range(min(count, len(cases)))]
    assigned = [case for shard in shards for case in shard]
    if (not shards or any(not shard for shard in shards)
            or len(assigned) != len(set(assigned)) or set(assigned) != set(cases)):
        raise ValueError("The worker plan must assign every selected case exactly once.")
    return shards


def worker_environment(env, runtime, artifacts, cases):
    env = env.copy()
    for name in ("DISPLAY", "WAYLAND_DISPLAY", "AT_SPI_BUS_ADDRESS",
                 "DBUS_SESSION_BUS_ADDRESS", "DBUS_SESSION_BUS_PID",
                 "CHICHI77_KEYKEY_GUANYINMA_USER_DB", "FCITX_CONFIG_HOME",
                 "FCITX_DATA_HOME", "FCITX_CONFIG_DIRS", "FCITX_DATA_DIRS"):
        env.pop(name, None)
    env.update({
        "KEYKEY_E2E_SESSION_MODE": "managed",
        "KEYKEY_E2E_CASES": ",".join(cases),
        "KEYKEY_E2E_RUNTIME_ROOT": str(runtime),
        "KEYKEY_E2E_ARTIFACT_DIR": str(artifacts),
        "XDG_CONFIG_HOME": str(runtime / "config"),
        "XDG_DATA_HOME": str(runtime / "data"),
        "XDG_CACHE_HOME": str(runtime / "cache"),
        "XDG_STATE_HOME": str(runtime / "state"),
        "XDG_RUNTIME_DIR": str(runtime / "runtime"),
    })
    for name in ("config", "data", "cache", "state", "runtime"):
        (runtime / name).mkdir(parents=True, exist_ok=True)
    (runtime / "runtime").chmod(0o700)
    return env


def stop_group(process):
    # Only this worker's new process group is signalled. D-Bus-activated helpers
    # can outlive the session shell, so clean the group even after it exits.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def adopt_private_children():
    # Linux CI containers do not necessarily have a PID 1 that reaps children.
    # Adopt orphaned portal/accessibility helpers instead of leaving zombies.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        raise OSError(ctypes.get_errno(), "Could not adopt private worker children.")


def reap_private_children():
    # Called only after all direct Popen workers have been waited for. Every
    # remaining child belongs to our private workers, including helpers which
    # started a new process group and therefore survived killpg().
    children_file = Path(f"/proc/self/task/{os.getpid()}/children")
    for attempt in range(20):
        try:
            while os.waitpid(-1, os.WNOHANG)[0]:
                pass
        except ChildProcessError:
            return None
        children = children_file.read_text().split()
        if not children:
            return None
        for child in children:
            try:
                os.kill(int(child), signal.SIGTERM if attempt == 0 else signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.1)
    return "Private worker children did not exit: " + children_file.read_text().strip()


def load_json(path):
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def cleanup_runtime(runtime):
    """Bound cleanup and only detach FUSE mounts created inside our workers."""
    last_error = None
    for attempt in range(10):
        try:
            # stat()/ismount() can fail on a disconnected document portal FUSE
            # mount. The kernel mount table still identifies its exact target.
            mountpoints = {
                re.sub(r"\\([0-7]{3})", lambda match: chr(int(match[1], 8)), line.split()[4])
                for line in Path("/proc/self/mountinfo").read_text().splitlines()
            }
            fusermount = shutil.which("fusermount3") or shutil.which("fusermount")
            if fusermount:
                for worker in runtime.glob("worker-*"):
                    for name in ("doc", "gvfs"):
                        mount = worker / "runtime" / name
                        if str(mount) in mountpoints:
                            subprocess.run([fusermount, "-u", "-z", str(mount)],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                           timeout=3, check=False)
            shutil.rmtree(runtime)
            return None
        except FileNotFoundError:
            if not runtime.exists():
                return None
        except (OSError, subprocess.TimeoutExpired) as error:
            last_error = error
        if attempt < 9:
            time.sleep(0.2)
    return f"Could not remove private runtime {runtime}: {last_error}"


def aggregate(artifacts, cases, workers, errors):
    """Require process, suite, main-case and nested recovery evidence to agree."""
    for worker in workers:
        directory = artifacts / "workers" / worker["id"]
        if worker["returncode"] != 0:
            errors.append((worker["id"], f'Worker exited with {worker["returncode"]}.'))
        try:
            result = load_json(directory / "result.json")
            if result.get("status") != "passed" or result.get("tests") != worker["cases"]:
                raise ValueError("Worker summary does not match its successful case assignment.")
        except (OSError, ValueError, TypeError, AttributeError) as error:
            errors.append((worker["id"], str(error)))
        for case in worker["cases"]:
            source = directory / case
            if source.is_dir():
                source.rename(artifacts / case)

    # Retain canonical caller paths, with complete worker evidence alongside.
    checks = artifacts / "config-checks"
    checks.mkdir()
    for filename in ("fcitx5.log", "xvfb.log", "reset-learning.jsonl"):
        with (artifacts / filename).open("wb") as output:
            for worker in workers:
                source = artifacts / "workers" / worker["id"] / filename
                if source.is_file():
                    output.write(source.read_bytes())
    for worker in workers:
        directory = artifacts / "workers" / worker["id"]
        for source in sorted((directory / "config-checks").glob("*.json")):
            shutil.copy2(source, checks / f'{worker["id"]}-{source.name}')
    for filename in ("config-baseline.json", "loaded-addon-path.txt"):
        sources = [artifacts / "workers" / worker["id"] / filename for worker in workers]
        existing = [path for path in sources if path.is_file()]
        if existing:
            if any(path.read_bytes() != existing[0].read_bytes() for path in existing[1:]):
                errors.append((filename, "Worker installation/baseline evidence differs."))
            shutil.copy2(existing[0], artifacts / filename)

    recovery = [f"{case}/recovery" for case in cases
                if case.startswith("T10-X11-") and case.endswith("-INPUT-CONTEXT-ISOLATION")]
    case_errors = {}
    for case in cases + recovery:
        try:
            result = load_json(artifacts / case / "result.json")
            if result.get("test") != case or result.get("status") != "passed":
                raise ValueError("Case result is not a matching passed result.")
        except (OSError, ValueError, TypeError, AttributeError) as error:
            case_errors[case] = str(error)
            errors.append((case, str(error)))

    apps = [app for toolkit, app in (("GTK3", "gtk3-entry"), ("GTK4", "gtk4-text"),
                                    ("QT6", "qt6-line-edit"))
            if any(f"-{toolkit}-" in case for case in cases)]
    if "T07-X11-FCITX5-CONFIG-UI-PERSISTENCE" in cases:
        if "gtk3-entry" not in apps:
            apps.insert(0, "gtk3-entry")
        apps.append("fcitx5-config-qt")
    result = {
        "tests": cases, "recoveryTests": recovery, "distro": "ubuntu-24.04",
        "arch": platform.machine(), "desktop": "none", "session": "x11-xvfb",
        "framework": "fcitx5", "app": "+".join(apps),
        "status": "failed" if errors else "passed",
        "workers": workers, "failures": [{"test": name, "message": error}
                                         for name, error in errors],
        "passed": len(cases) + len(recovery) - len(case_errors),
    }
    (artifacts / "result.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    infrastructure = [(name, error) for name, error in errors if name not in case_errors]
    suite = ET.Element("testsuite", name="chichi77-keykey-linux-x11-e2e",
                       tests=str(len(cases) + len(recovery) + len(infrastructure)),
                       failures=str(len(case_errors) + len(infrastructure)))
    for name in cases + recovery:
        element = ET.SubElement(suite, "testcase", classname="fcitx5.toolkit.x11", name=name)
        if name in case_errors:
            ET.SubElement(element, "failure", message=case_errors[name])
    for name, error in infrastructure:
        element = ET.SubElement(suite, "testcase", classname="fcitx5.worker", name=name)
        ET.SubElement(element, "failure", message=error)
    ET.ElementTree(suite).write(artifacts / "junit.xml", encoding="utf-8", xml_declaration=True)
    return result


def interrupted(signum, _frame):
    raise InterruptedError(f"X11 coordinator received signal {signum}.")


def main():
    env = os.environ.copy()
    if env.get("KEYKEY_E2E_SESSION_MODE", "managed") != "managed":
        raise ValueError("Parallel X11 tests require private managed sessions.")
    if env.get("CHICHI77_KEYKEY_GUANYINMA_USER_DB"):
        raise ValueError("Explicit user DB fixtures require the serial session runner.")
    count = int(env.get("KEYKEY_E2E_WORKERS", "4"))
    if count < 1:
        raise ValueError("KEYKEY_E2E_WORKERS must be a positive integer.")
    cases = selected_cases(env)
    shards = partition(cases, count)
    for name in ("KEYKEY_E2E_HOST", "KEYKEY_E2E_GTK4_HOST", "KEYKEY_E2E_QT6_HOST"):
        if not os.access(env.get(name, ""), os.X_OK):
            raise ValueError(f"{name} must name an executable test host.")
    adopt_private_children()
    artifacts = Path(env["KEYKEY_E2E_ARTIFACT_DIR"]).resolve()
    artifacts.mkdir(parents=True, exist_ok=True)
    if any(artifacts.iterdir()):
        raise ValueError("KEYKEY_E2E_ARTIFACT_DIR must be fresh to exclude stale results.")
    runtime_parent = env.get("KEYKEY_E2E_RUNTIME_ROOT")
    if runtime_parent:
        Path(runtime_parent).mkdir(parents=True, exist_ok=True)
    runtime = Path(tempfile.mkdtemp(prefix="keykey-x11-workers-", dir=runtime_parent))
    plan = {"requested": env.get("KEYKEY_E2E_CASES", "all"),
            "configUI": env.get("KEYKEY_E2E_CONFIG_UI", "ON"), "tests": cases,
            "workers": [{"id": f"worker-{i + 1}", "cases": shard}
                        for i, shard in enumerate(shards)]}
    (artifacts / "parallel-plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    workers, running, errors = [], [], []
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, interrupted)
    print(f"X11: {len(cases)} selected cases across {len(shards)} private workers.", flush=True)
    try:
        for assignment in plan["workers"]:
            worker = dict(assignment, returncode=None)
            workers.append(worker)
            directory = artifacts / "workers" / worker["id"]
            directory.mkdir(parents=True)
            worker_env = worker_environment(env, runtime / worker["id"], directory, worker["cases"])
            log = (directory / "session.log").open("wb")
            try:
                process = subprocess.Popen(
                    ["dbus-run-session", "--", "bash", str(SESSION)],
                    env=worker_env, cwd=LINUX_DIR, stdout=log, stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
            except BaseException:
                log.close()
                raise
            worker["pid"] = process.pid
            running.append((worker, process, log, time.monotonic()))
        pending = list(running)
        while pending:
            for entry in pending[:]:
                worker, process, log, started = entry
                if process.poll() is None:
                    continue
                worker["returncode"] = process.returncode
                worker["seconds"] = round(time.monotonic() - started, 2)
                stop_group(process)
                log.close()
                pending.remove(entry)
                print(f'{worker["id"]}: exit {worker["returncode"]}, '
                      f'{len(worker["cases"])} assigned cases, {worker["seconds"]}s.', flush=True)
            if pending:
                time.sleep(0.1)
    except (OSError, InterruptedError) as error:
        errors.append(("coordinator", str(error)))
    finally:
        # Do not let a second cancellation interrupt private-process cleanup.
        for signum in (signal.SIGINT, signal.SIGTERM):
            signal.signal(signum, signal.SIG_IGN)
        for worker, process, log, started in running:
            if worker["returncode"] is None:
                stop_group(process)
                worker["returncode"] = process.returncode
                worker["seconds"] = round(time.monotonic() - started, 2)
            log.close()
        try:
            children_error = reap_private_children()
        except OSError as error:
            children_error = str(error)
        if children_error:
            errors.append(("cleanup", children_error))
        cleanup_error = cleanup_runtime(runtime)
        if cleanup_error:
            errors.append(("cleanup", cleanup_error))
    # Include unstarted assignments as failures after an interrupted launch.
    for assignment in plan["workers"][len(workers):]:
        workers.append(dict(assignment, returncode=None))
    result = aggregate(artifacts, cases, workers, errors)
    print(f'X11: {result["status"]}; {result["passed"]}/{len(cases) + len(result["recoveryTests"])} '
          f'case/recovery results passed. Evidence: {artifacts}', flush=True)
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"X11 coordinator: {error}", file=sys.stderr)
        sys.exit(2)

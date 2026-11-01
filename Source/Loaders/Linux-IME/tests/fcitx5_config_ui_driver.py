#!/usr/bin/env python3
"""Drive the installed Fcitx settings through AT-SPI or isolated X11 input."""

import argparse
import configparser
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

import pyatspi


TIMEOUT_SECONDS = 30.0
POLL_SECONDS = 0.1


def descendants(root):
    try:
        children = list(root)
    except (LookupError, RuntimeError, ValueError):
        return
    for child in children:
        yield child
        yield from descendants(child)


def node_matches(node, role, name, showing=True, enabled=True):
    try:
        if node.getRoleName() != role or node.name != name:
            return False
        state_set = node.getState()
        if showing and not state_set.contains(pyatspi.STATE_SHOWING):
            return False
        if enabled and not state_set.contains(pyatspi.STATE_ENABLED):
            return False
        return True
    except (LookupError, RuntimeError, ValueError):
        return False


def wait_for_node(root, role, name, present=True):
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        matches = [
            node
            for node in descendants(root)
            if node_matches(node, role, name)
        ]
        if present and matches:
            return matches[0]
        if not present and not matches:
            return None
        time.sleep(POLL_SECONDS)
    qualifier = "appear" if present else "close"
    role_names = []
    for node in descendants(root):
        try:
            if node.getRoleName() == role:
                role_names.append(node.name)
        except (LookupError, RuntimeError, ValueError):
            continue
    raise RuntimeError(
        f"Timed out waiting for {role} {name!r} to {qualifier}; "
        f"available names: {role_names!r}"
    )


def wait_for_application(desktop, name):
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        for application in desktop:
            try:
                if application.name == name:
                    return application
            except (LookupError, RuntimeError, ValueError):
                continue
        time.sleep(POLL_SECONDS)
    application_names = []
    for application in desktop:
        try:
            application_names.append(application.name)
        except (LookupError, RuntimeError, ValueError):
            continue
    raise RuntimeError(
        f"Timed out waiting for application {name!r}; "
        f"AT-SPI applications: {application_names!r}"
    )


def has_state(node, state):
    try:
        return node.getState().contains(state)
    except (LookupError, RuntimeError, ValueError):
        return None


def wait_for_state(node, state, expected):
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        state_value = has_state(node, state)
        if state_value is not None and state_value == expected:
            return
        time.sleep(POLL_SECONDS)
    raise RuntimeError("Timed out waiting for the requested accessibility state")


def perform_action(node, action_name):
    action = node.queryAction()
    for index in range(action.nActions):
        if action.getName(index) == action_name:
            if not action.doAction(index):
                raise RuntimeError(f"AT-SPI action {action_name!r} failed")
            return
    raise RuntimeError(f"Node has no AT-SPI action named {action_name!r}")


def click_node(node):
    extents = node.queryComponent().getExtents(pyatspi.DESKTOP_COORDS)
    if extents.width <= 0 or extents.height <= 0:
        raise RuntimeError("Accessibility node has no clickable screen area")
    subprocess.run(
        [
            "xdotool",
            "mousemove",
            "--sync",
            str(extents.x + extents.width // 2),
            str(extents.y + extents.height // 2),
            "click",
            "1",
        ],
        check=True,
    )


def select_last_combo_value(node):
    click_node(node)
    subprocess.run(["xdotool", "key", "End", "Return"], check=True)


def capture_window(title, stem, window_id=None):
    if window_id is None:
        window_ids = subprocess.check_output(
            ["xdotool", "search", "--onlyvisible", "--name", f"^{title}$"],
            text=True,
        ).splitlines()
        if not window_ids:
            raise RuntimeError(f"No visible X11 window named {title!r}")
        window_id = window_ids[0]

    png_path = stem.with_suffix(".png")
    with tempfile.NamedTemporaryFile(suffix=".xwd") as xwd_file:
        subprocess.run(
            [
                "xwd",
                "-silent",
                "-id",
                window_id,
                "-out",
                xwd_file.name,
            ],
            check=True,
        )
        converter = subprocess.Popen(
            ["xwdtopnm", xwd_file.name],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if converter.stdout is None:
            raise RuntimeError("xwdtopnm did not create an output stream")
        with png_path.open("wb") as png_file:
            png_result = subprocess.run(
                ["pnmtopng"],
                stdin=converter.stdout,
                stdout=png_file,
                stderr=subprocess.PIPE,
                check=False,
            )
        converter.stdout.close()
        _, converter_stderr = converter.communicate()
    if converter.returncode != 0:
        raise RuntimeError(converter_stderr.decode("utf-8", errors="replace"))
    if png_result.returncode != 0:
        raise RuntimeError(png_result.stderr.decode("utf-8", errors="replace"))


def drive_isolated_x11(artifact_dir):
    # This pointer fixture is deliberately restricted to the private display,
    # fixed profile, scale and canvas established by the managed CI runner.
    runtime = Path(os.environ["KEYKEY_E2E_RUNTIME_ROOT"]).resolve()
    config_home = Path(os.environ["XDG_CONFIG_HOME"]).resolve()
    display = ":" + (runtime / "xvfb-display").read_text().strip()
    if (os.environ.get("KEYKEY_E2E_SESSION_MODE") != "managed"
            or os.environ.get("DISPLAY") != display
            or not config_home.is_relative_to(runtime)
            or os.environ.get("QT_SCALE_FACTOR") != "1"
            or os.environ.get("QT_FONT_DPI") != "100"):
        raise RuntimeError("X11 settings automation requires the managed private display")

    def xdo(*args):
        return subprocess.check_output(["xdotool", *map(str, args)], text=True).strip()

    def geometry(window):
        values = dict(line.split("=", 1) for line in xdo("getwindowgeometry", "--shell", window).splitlines())
        return {key: int(values[key]) for key in ("X", "Y", "WIDTH", "HEIGHT")}

    def find_window(pattern, present=True):
        deadline = time.monotonic() + TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            result = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", pattern],
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            windows = result.stdout.splitlines()
            if not present and not windows:
                return None
            for window in windows:
                size = geometry(window)
                if size["WIDTH"] > 400 and size["HEIGHT"] > 400 and present:
                    return window
            time.sleep(POLL_SECONDS)
        raise RuntimeError(f"Timed out waiting for X11 window {pattern!r}, present={present}")

    def click(window, x, y):
        xdo("mousemove", "--window", window, x, y, "click", 1)

    def settings():
        parser = configparser.ConfigParser(interpolation=None)
        parser.optionxform = str
        parser.read_string("[Root]\n" + (config_home / "fcitx5/conf/chichi77-keykey.conf").read_text())
        return {
            "McBopomofo": parser["AssociatedPhrases"]["McBopomofo"],
            "agriculture-food": parser["AssociatedPhrases"]["agriculture-food"],
            **{name: parser["Root"][name] for name in (
                "PlaySoundOnTypingError", "ToggleInputMethodWithControlBackslash", "CandidateWindowStyle")},
        }

    profile = configparser.ConfigParser(interpolation=None)
    profile.read(config_home / "fcitx5/profile")
    if (profile["Groups/0/Items/0"]["Name"] != "keyboard-us"
            or profile["Groups/0/Items/1"]["Name"] != "chichi77-keykey-bopomofo"):
        raise RuntimeError("Unexpected input-method order for the X11 pointer fixture")
    before = {"McBopomofo": "True", "agriculture-food": "False", "PlaySoundOnTypingError": "True",
              "ToggleInputMethodWithControlBackslash": "True", "CandidateWindowStyle": "Vertical"}
    if settings() != before:
        raise RuntimeError("Unexpected initial native settings")
    main_window = find_window("^Fcitx Configuration$")
    xdo("windowsize", main_window, 800, 600)
    xdo("windowfocus", "--sync", main_window)
    click(main_window, 110, 140)  # Second item in the verified fixed profile.
    click(main_window, 400, 314)  # Native Configure button between the lists.
    dialog = find_window("^chichi77 KeyKey Bopomofo")
    if xdo("getwindowpid", dialog) != xdo("getwindowpid", main_window):
        raise RuntimeError("Settings dialog is not owned by the configuration application")
    xdo("windowsize", dialog, 900, 3400)
    xdo("windowmove", dialog, 20, 20)
    xdo("windowfocus", "--sync", dialog)
    if geometry(dialog) != {"X": 20, "Y": 20, "WIDTH": 900, "HEIGHT": 3400}:
        raise RuntimeError("Unexpected settings geometry for the X11 pointer fixture")
    time.sleep(0.5)
    title = xdo("getwindowname", dialog)
    capture_window(title, artifact_dir / "settings-before", dialog)
    actions = [("McBopomofo", 63, 2160), ("agriculture-food", 63, 3078),
               ("PlaySoundOnTypingError", 150, 349),
               ("ToggleInputMethodWithControlBackslash", 150, 281)]
    for _, x, y in actions:
        click(dialog, x, y)
    click(dialog, 338, 247)
    xdo("key", "--delay", 80, "End", "Return")
    time.sleep(0.2)
    capture_window(title, artifact_dir / "settings-after", dialog)
    click(dialog, 849, 3375)  # Native OK button; this is the only save action.
    find_window("^chichi77 KeyKey Bopomofo", present=False)
    after = {"McBopomofo": "False", "agriculture-food": "True", "PlaySoundOnTypingError": "False",
             "ToggleInputMethodWithControlBackslash": "False", "CandidateWindowStyle": "Horizontal"}
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while settings() != after:
        if time.monotonic() >= deadline:
            raise RuntimeError(f"Native GUI did not save the expected settings: {settings()}")
        time.sleep(POLL_SECONDS)
    xdo("windowclose", main_window)
    find_window("^Fcitx Configuration$", present=False)
    (artifact_dir / "ui-actions.json").write_text(json.dumps({
        "test": "T07-X11-FCITX5-CONFIG-UI-PERSISTENCE", "application": "fcitx5-config-qt",
        "automation": "isolated-x11-pointer-keyboard", "atspi_used": False,
        "before": before, "changed": after, "pointer_actions": actions,
        "dialog_geometry": {"width": 900, "height": 3400}, "status": "passed",
    }, ensure_ascii=False, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact_dir", type=Path)
    parser.add_argument("--backend", choices=("atspi", "x11"), default="atspi")
    args = parser.parse_args()
    args.artifact_dir.mkdir(parents=True, exist_ok=True)
    if args.backend == "x11":
        drive_isolated_x11(args.artifact_dir)
        return

    desktop = pyatspi.Registry.getDesktop(0)
    application = wait_for_application(desktop, "fcitx5-config-qt")
    input_method = wait_for_node(
        application, "list item", "chichi77 KeyKey Bopomofo"
    )
    click_node(input_method)
    wait_for_state(input_method, pyatspi.STATE_SELECTED, True)

    configure_button = wait_for_node(application, "push button", "Configure")
    click_node(configure_button)
    dialog = wait_for_node(
        application, "dialog", "chichi77 KeyKey Bopomofo"
    )

    base_collection = wait_for_node(dialog, "check box", "小麥注音")
    agriculture_collection = wait_for_node(dialog, "check box", "農業食品")
    error_sound = wait_for_node(
        dialog, "check box", "輸入錯誤時播放提示音"
    )
    control_backslash = wait_for_node(
        dialog, "check box", "使用 Ctrl+\\ 切換中英文"
    )
    candidate_window_style = wait_for_node(
        dialog, "combo box", "直式"
    )
    if has_state(base_collection, pyatspi.STATE_CHECKED) is not True:
        raise RuntimeError("Expected the McBopomofo collection to be enabled")
    if has_state(agriculture_collection, pyatspi.STATE_CHECKED) is not False:
        raise RuntimeError("Expected the agriculture-food collection to be disabled")
    if has_state(error_sound, pyatspi.STATE_CHECKED) is not True:
        raise RuntimeError("Expected typing-error sound to be enabled")
    if has_state(control_backslash, pyatspi.STATE_CHECKED) is not True:
        raise RuntimeError("Expected Ctrl+backslash switching to be enabled")

    capture_window(
        "chichi77 KeyKey Bopomofo",
        args.artifact_dir / "settings-before",
    )
    perform_action(base_collection, "Toggle")
    perform_action(agriculture_collection, "Toggle")
    perform_action(error_sound, "Toggle")
    perform_action(control_backslash, "Toggle")
    select_last_combo_value(candidate_window_style)
    wait_for_node(dialog, "combo box", "橫式")
    wait_for_state(base_collection, pyatspi.STATE_CHECKED, False)
    wait_for_state(agriculture_collection, pyatspi.STATE_CHECKED, True)
    wait_for_state(error_sound, pyatspi.STATE_CHECKED, False)
    wait_for_state(control_backslash, pyatspi.STATE_CHECKED, False)
    capture_window(
        "chichi77 KeyKey Bopomofo",
        args.artifact_dir / "settings-after",
    )

    ok_button = wait_for_node(dialog, "push button", "OK")
    perform_action(ok_button, "Press")
    wait_for_node(
        application, "dialog", "chichi77 KeyKey Bopomofo", present=False
    )
    close_button = wait_for_node(application, "push button", "Close")
    perform_action(close_button, "Press")

    evidence = {
        "test": "T07-X11-FCITX5-CONFIG-UI-PERSISTENCE",
        "application": "fcitx5-config-qt",
        "inputMethod": "chichi77 KeyKey Bopomofo",
        "accessibility": "AT-SPI",
        "changed": {
            "McBopomofo": False,
            "agriculture-food": True,
            "PlaySoundOnTypingError": False,
            "ToggleInputMethodWithControlBackslash": False,
            "CandidateWindowStyle": "Horizontal",
        },
        "status": "passed",
    }
    (args.artifact_dir / "ui-actions.json").write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()

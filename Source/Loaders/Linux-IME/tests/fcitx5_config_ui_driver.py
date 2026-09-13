#!/usr/bin/env python3
"""Drive the installed Fcitx 5 configuration UI through AT-SPI."""

import argparse
import json
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
    raise RuntimeError(f"Timed out waiting for {role} {name!r} to {qualifier}")


def wait_for_application(name):
    desktop = pyatspi.Registry.getDesktop(0)
    deadline = time.monotonic() + TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        for application in desktop:
            try:
                if application.name == name:
                    return application
            except (LookupError, RuntimeError, ValueError):
                continue
        time.sleep(POLL_SECONDS)
    raise RuntimeError(f"Timed out waiting for application {name!r}")


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


def capture_window(title, stem):
    window_ids = subprocess.check_output(
        ["xdotool", "search", "--onlyvisible", "--name", f"^{title}$"],
        text=True,
    ).splitlines()
    if not window_ids:
        raise RuntimeError(f"No visible X11 window named {title!r}")

    png_path = stem.with_suffix(".png")
    with tempfile.NamedTemporaryFile(suffix=".xwd") as xwd_file:
        subprocess.run(
            [
                "xwd",
                "-silent",
                "-id",
                window_ids[0],
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact_dir", type=Path)
    args = parser.parse_args()
    args.artifact_dir.mkdir(parents=True, exist_ok=True)

    application = wait_for_application("fcitx5-config-qt")
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
    if has_state(base_collection, pyatspi.STATE_CHECKED) is not True:
        raise RuntimeError("Expected the McBopomofo collection to be enabled")
    if has_state(agriculture_collection, pyatspi.STATE_CHECKED) is not False:
        raise RuntimeError("Expected the agriculture-food collection to be disabled")

    capture_window(
        "chichi77 KeyKey Bopomofo",
        args.artifact_dir / "settings-before",
    )
    perform_action(base_collection, "Toggle")
    perform_action(agriculture_collection, "Toggle")
    wait_for_state(base_collection, pyatspi.STATE_CHECKED, False)
    wait_for_state(agriculture_collection, pyatspi.STATE_CHECKED, True)
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
        },
        "status": "passed",
    }
    (args.artifact_dir / "ui-actions.json").write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# Copyright (c) 2026 Chui-Ping Cheng. MIT License.
r"""Provide selected Simulator keyboard events while one UI-test command runs.

Some iOS XCTest versions expose Forward Delete/Return constants without sending
them to a raw UIKit responder. This host-only bridge uses the selected Xcode's
private SimulatorKit transport. It is not a product dependency or USB evidence.
Only the explicitly selected, already booted Simulator receives messages; no
events are posted to the macOS global keyboard stream.

Protocol: one ``delete\n`` or ``return\n`` per loopback connection, followed by
``OK\n`` or ``ERR ...\n``. Delivery is serialized. UI assertions must still verify
the App's behavior: a transport acknowledgement alone is not input acceptance.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import socket
import socketserver
import subprocess
import sys
import threading
import uuid


KEY_CODES = {b"delete\n": "117", b"return\n": "36"}
SENDER_TIMEOUT = 12


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Exact, already booted Simulator UUID")
    parser.add_argument("--output", required=True, type=Path, help="Build and transport-log directory")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="Command after --, usually xcodebuild")
    arguments = parser.parse_args()
    if arguments.command[:1] == ["--"]:
        arguments.command = arguments.command[1:]
    if not arguments.command:
        parser.error("a command is required after --")
    try:
        arguments.device = str(uuid.UUID(arguments.device)).upper()
    except ValueError:
        parser.error("--device must be an exact Simulator UUID, not a name or physical-device selector")
    return arguments


def verify_booted_simulator(device_id: str, environment: dict[str, str]) -> None:
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "--json"],
        env=environment, capture_output=True, text=True, check=True, timeout=30,
    )
    devices = [device for group in json.loads(result.stdout)["devices"].values() for device in group]
    matches = [device for device in devices if device.get("udid", "").upper() == device_id]
    if len(matches) != 1 or matches[0].get("state") != "Booted" or not matches[0].get("isAvailable", True):
        raise RuntimeError("--device must identify exactly one available, already booted Simulator")


def main() -> int:
    arguments = parse_arguments()
    developer_directory = subprocess.run(
        ["xcode-select", "-p"], capture_output=True, text=True, check=True, timeout=15,
    ).stdout.strip()
    if not Path(developer_directory).is_absolute():
        raise RuntimeError("xcode-select did not return an absolute active Developer directory")
    environment = os.environ.copy()
    environment["DEVELOPER_DIR"] = developer_directory
    verify_booted_simulator(arguments.device, environment)
    output = arguments.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    sender = output / "SimulatorHIDSender"
    subprocess.run(
        ["xcrun", "--sdk", "macosx", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
         "-framework", "Foundation", "-framework", "AppKit",
         str(Path(__file__).with_name("SimulatorHIDSender.m")), "-o", str(sender)],
        env=environment, check=True, timeout=60,
    )
    sender_arguments = [str(sender), "--udid", arguments.device, "--developer-dir", developer_directory]
    # The native tool independently verifies the exact CoreSimulator device and
    # its booted state. Dry-run does not construct a HID client or send a key.
    subprocess.run(sender_arguments + ["--dry-run"], env=environment, check=True, timeout=30)

    with (output / "simulator-hid-events.log").open("w", encoding="utf-8") as log:
        class Handler(socketserver.BaseRequestHandler):
            def handle(self) -> None:
                self.request.settimeout(6)
                response = b"ERR invalid command\n"
                try:
                    message = b""
                    while len(message) < 32 and b"\n" not in message:
                        chunk = self.request.recv(32 - len(message))
                        if not chunk:
                            break
                        message += chunk
                    key_code = KEY_CODES.get(message)
                    if key_code is not None:
                        stamp = datetime.now(timezone.utc).isoformat()
                        try:
                            result = subprocess.run(
                                sender_arguments + ["--keycode", key_code, "--hold-ms", "40"],
                                env=environment, capture_output=True, text=True, timeout=SENDER_TIMEOUT,
                            )
                            log.write(f"{stamp} command={message.strip().decode()} status={result.returncode}\n")
                            log.write(result.stdout)
                            log.write(result.stderr)
                            response = b"OK\n" if result.returncode == 0 else b"ERR sender failed\n"
                        except subprocess.TimeoutExpired:
                            log.write(f"{stamp} command={message.strip().decode()} sender timed out\n")
                            response = b"ERR sender timed out\n"
                        log.flush()
                    self.request.sendall(response)
                except (OSError, socket.timeout) as error:
                    log.write(f"loopback connection error: {error}\n")
                    log.flush()

        # TCPServer, rather than ThreadingTCPServer, keeps key pairs serialized.
        server = socketserver.TCPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, name="SimulatorHID", daemon=True)
        thread.start()
        environment["TEST_RUNNER_KEYKEY_SIMULATOR_HID_PORT"] = str(server.server_address[1])
        print(f"Simulator HID bridge: {arguments.device} at 127.0.0.1:{server.server_address[1]}", flush=True)

        def terminate(_number: int, _frame: object) -> None:
            raise KeyboardInterrupt

        previous_termination_handler = signal.signal(signal.SIGTERM, terminate)
        try:
            result = subprocess.run(arguments.command, env=environment, check=False)
            return result.returncode if result.returncode >= 0 else 128 - result.returncode
        except KeyboardInterrupt:
            return 130
        finally:
            signal.signal(signal.SIGTERM, previous_termination_handler)
            server.shutdown()
            server.server_close()
            thread.join(timeout=SENDER_TIMEOUT + 7)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"Simulator HID setup failed: {error}", file=sys.stderr)
        raise SystemExit(1)

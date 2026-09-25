#!/usr/bin/env python3
"""Submit, inspect, and download one OpenAI article-generation batch."""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
from pathlib import Path
import urllib.error
import urllib.request
import uuid


ROOT = Path(__file__).resolve().parent
API_ROOT = "https://api.openai.com/v1"


def api_key() -> str:
    value = os.environ.get("OPENAI_API_KEY")
    if not value:
        raise SystemExit("OPENAI_API_KEY is not set")
    return value


def request(method: str, path: str, data: bytes | None = None, content_type: str | None = None) -> tuple[dict, dict]:
    headers = {"Authorization": f"Bearer {api_key()}"}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(API_ROOT + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.loads(response.read()), dict(response.headers)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"OpenAI API HTTP {error.code}: {detail}") from error


def download(path: str) -> bytes:
    req = urllib.request.Request(API_ROOT + path, headers={"Authorization": f"Bearer {api_key()}"})
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"OpenAI API HTTP {error.code}: {detail}") from error


def upload_batch_file(path: Path) -> dict:
    boundary = "----keykey-" + uuid.uuid4().hex
    mime = mimetypes.guess_type(path.name)[0] or "application/jsonl"
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\nbatch\r\n".encode(),
        (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{path.name}\"\r\n"
            f"Content-Type: {mime}\r\n\r\n"
        ).encode(),
        path.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode(),
    ]
    result, _ = request("POST", "/files", b"".join(parts), f"multipart/form-data; boundary={boundary}")
    return result


def submission_path(input_path: Path) -> Path:
    directory = ROOT / "article-batches-v2" / "submissions"
    directory.mkdir(parents=True, exist_ok=True)
    return directory / f"{input_path.stem}.json"


def submit(input_path: Path) -> None:
    if not input_path.exists():
        raise SystemExit(f"missing batch input: {input_path}")
    target = submission_path(input_path)
    if target.exists():
        raise SystemExit(f"submission record already exists: {target}")
    uploaded = upload_batch_file(input_path)
    payload = json.dumps(
        {
            "input_file_id": uploaded["id"],
            "endpoint": "/v1/responses",
            "completion_window": "24h",
            "metadata": {"description": f"KeyKey Traditional Chinese corpus {input_path.stem}"},
        }
    ).encode()
    batch, _ = request("POST", "/batches", payload, "application/json")
    record = {"input_path": str(input_path.resolve()), "uploaded_file": uploaded, "batch": batch}
    target.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"submission": str(target), "batch_id": batch["id"], "status": batch["status"]}, ensure_ascii=False))


def load_record(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def status(path: Path) -> None:
    record = load_record(path)
    batch_id = record["batch"]["id"]
    batch, _ = request("GET", f"/batches/{batch_id}")
    record["batch"] = batch
    path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"batch_id": batch_id, "status": batch["status"], "request_counts": batch.get("request_counts")}, ensure_ascii=False))


def fetch(path: Path) -> None:
    record = load_record(path)
    batch_id = record["batch"]["id"]
    batch, _ = request("GET", f"/batches/{batch_id}")
    record["batch"] = batch
    path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    output_file_id = batch.get("output_file_id")
    if not output_file_id:
        raise SystemExit(f"batch {batch_id} has no output file; status={batch['status']}")
    output_dir = ROOT / "article-batches-v2" / "outputs"
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{path.stem}-output.jsonl"
    output_path.write_bytes(download(f"/files/{output_file_id}/content"))
    error_file_id = batch.get("error_file_id")
    if error_file_id:
        (output_dir / f"{path.stem}-errors.jsonl").write_bytes(download(f"/files/{error_file_id}/content"))
    print(json.dumps({"batch_id": batch_id, "output": str(output_path), "status": batch["status"]}, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("submit", "status", "fetch"):
        command = subparsers.add_parser(name)
        command.add_argument("path", type=Path)
    args = parser.parse_args()
    if args.command == "submit":
        submit(args.path)
    elif args.command == "status":
        status(args.path)
    else:
        fetch(args.path)


if __name__ == "__main__":
    main()

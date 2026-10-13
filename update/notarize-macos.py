#!/usr/bin/env python3
"""Save notary diagnostics and staple only an explicitly Accepted submission."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import uuid


def notarize(package, profile, output, keychain=None):
    output.mkdir(parents=True, exist_ok=True)
    # Keep each attempt separate: a failed submission must not appear to have
    # a previous attempt's Accepted response or downloaded ticket report.
    attempt = Path(tempfile.mkdtemp(prefix="submission-", dir=output))
    print(f"Notarization diagnostics: {attempt}", flush=True)
    auth = ["--keychain-profile", profile]
    if keychain:
        auth += ["--keychain", str(keychain)]
    result = subprocess.run(["xcrun", "notarytool", "submit", str(package), *auth,
                             "--wait", "--timeout", "30m", "--output-format", "json"],
                            capture_output=True)
    (attempt / "submit.json").write_bytes(result.stdout)
    (attempt / "submit.stderr.txt").write_bytes(result.stderr)
    try:
        response = json.loads(result.stdout)
        if not isinstance(response, dict):
            raise ValueError("response is not an object")
        submission_id = str(uuid.UUID(response["id"]))
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        raise ValueError(f"Notary submission failed or returned invalid JSON/id; see {attempt}") from error

    # Retrieve the rejection details even if submit itself exits nonzero.
    log = subprocess.run(["xcrun", "notarytool", "log", submission_id,
                          str(attempt / "notary-log.json"), *auth], capture_output=True)
    (attempt / "log.stdout.txt").write_bytes(log.stdout)
    (attempt / "log.stderr.txt").write_bytes(log.stderr)
    if log.returncode:
        print(f"Could not download notarization log for {submission_id}; see {attempt}", flush=True)
    status = response.get("status")
    print(f"Notarization {submission_id}: {status or 'missing status'}", flush=True)
    if result.returncode or status != "Accepted":
        raise ValueError(f"Notarization not Accepted (status={status}, exit={result.returncode}); see {attempt}")

    subprocess.run(["xcrun", "stapler", "staple", str(package)], check=True)
    subprocess.run(["xcrun", "stapler", "validate", str(package)], check=True)
    return attempt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--out", type=Path, default=Path("notarization-logs"))
    parser.add_argument("--keychain", type=Path)
    args = parser.parse_args()
    try:
        notarize(args.package, args.profile, args.out, args.keychain)
    except (ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")

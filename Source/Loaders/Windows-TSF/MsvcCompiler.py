"""Preserve localized MSVC diagnostics while exposing reliable Ninja includes."""

import pathlib
import subprocess
import sys


def main():
    prefix = pathlib.Path(sys.argv[1]).read_bytes()
    if not prefix:
        raise ValueError("Missing MSVC include prefix")
    utf8_prefix = prefix.decode("mbcs").encode("utf-8")
    process = subprocess.Popen(sys.argv[2:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    for line in process.stdout:
        if line.startswith(utf8_prefix):
            path = line[len(utf8_prefix):]
            try:
                path.decode("utf-8")
            except UnicodeDecodeError:
                path = path.decode("mbcs").encode("utf-8")
            line = b"Note: including file: " + path
        elif line.startswith(prefix):
            # MSVC output can use ANSI or UTF-8 depending on compiler flags.
            # Ninja paths are UTF-8; normalize both localized prefix encodings.
            line = b"Note: including file: " + line[len(prefix):].decode("mbcs").encode("utf-8")
        sys.stdout.buffer.write(line)
        sys.stdout.buffer.flush()
    return process.wait()


if __name__ == "__main__":
    sys.exit(main())
